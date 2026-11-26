use std::fs::File;
use std::io::BufReader;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{mpsc::{self, RecvTimeoutError}, Arc};
use parking_lot::Mutex;
use std::thread;
use std::time::{Duration, Instant};

use rodio::{Decoder, DeviceSinkBuilder, Player, Source};

use crate::cache::StreamReader;

/// Каждое событие помечено поколением трека, к которому относится,
/// чтобы запоздавшие события старого трека не влияли на новый.
pub enum Event {
    Started(u64),
    Position { generation: u64, secs: f64, paused: bool },
    Ended(u64),
    Error(u64, String),
}

pub enum SourceData {
    Cached { file: File, len: u64, hint: Option<String> },
    Stream { reader: StreamReader, hint: Option<String> },
}

enum Cmd {
    Load(u64, SourceData, f32),
    #[allow(dead_code)]
    Play,
    Pause,
    Toggle,
    Seek(f64),
    SeekRelative(f64),
    Volume(f32),
    Speed(f32),
    SleepFade(f32),
    TrackGain(f32),
    Stop,
}

const FFT_SIZE: usize = 2048;
const RING_SIZE: usize = 4096;
const SPECTRUM_BANDS: usize = 48;

struct SpectrumRing {
    samples: [f32; RING_SIZE],
    write_pos: usize,
    sample_rate: u32,
}

impl Default for SpectrumRing {
    fn default() -> Self {
        Self { samples: [0.0; RING_SIZE], write_pos: 0, sample_rate: 44100 }
    }
}

impl SpectrumRing {
    fn push_batch(&mut self, batch: &[f32], sample_rate: u32) {
        self.sample_rate = sample_rate.max(8000);
        for &s in batch {
            self.samples[self.write_pos] = s;
            self.write_pos = (self.write_pos + 1) % RING_SIZE;
        }
    }

    fn reset(&mut self) {
        self.samples.fill(0.0);
        self.write_pos = 0;
    }

    fn compute_bands(&self, out: &mut [f32]) -> usize {
        let count = out.len().min(SPECTRUM_BANDS);
        if count == 0 {
            return 0;
        }
        let mut buf = [(0.0f32, 0.0f32); FFT_SIZE];
        let start = (self.write_pos + RING_SIZE - FFT_SIZE) % RING_SIZE;
        let mut mean = 0.0f32;
        for i in 0..FFT_SIZE {
            mean += self.samples[(start + i) % RING_SIZE];
        }
        mean /= FFT_SIZE as f32;

        for i in 0..FFT_SIZE {
            let hann = 0.5 * (1.0 - (std::f32::consts::TAU * i as f32 / (FFT_SIZE - 1) as f32).cos());
            let s = self.samples[(start + i) % RING_SIZE] - mean;
            buf[i] = (s * hann, 0.0);
        }
        fft_in_place(&mut buf);

        let nyquist = self.sample_rate as f32 * 0.5;
        let min_freq = 36.0f32;
        let max_freq = 14000.0f32.min(nyquist * 0.95);
        let ratio = (max_freq / min_freq).max(1.1);
        let bin_hz = self.sample_rate as f32 / FFT_SIZE as f32;
        let max_bin = FFT_SIZE / 2 - 1;
        let denom = (count.saturating_sub(1)).max(1) as f32;

        for band in 0..count {
            let f0 = min_freq * ratio.powf(band as f32 / count as f32);
            let f1 = min_freq * ratio.powf((band + 1) as f32 / count as f32);
            let b0 = ((f0 / bin_hz).floor() as usize).clamp(1, max_bin);
            let b1 = ((f1 / bin_hz).ceil() as usize).clamp(b0, max_bin);
            let mut sum_sq = 0.0f32;
            let mut peak = 0.0f32;
            for b in b0..=b1 {
                let (re, im) = buf[b];
                let mag = (re * re + im * im).sqrt() / (FFT_SIZE as f32 * 0.25);
                sum_sq += mag * mag;
                peak = peak.max(mag);
            }
            let rms = (sum_sq / (b1 - b0 + 1) as f32).sqrt();
            let combined = (rms * 0.65 + peak * 0.35).max(1e-6);
            let db = 20.0 * combined.log10();

            // Перцептивный наклон (~3 dB/окт): прибирает перегруз баса на краях и поднимает СЧ/ВЧ.
            let frac = band as f32 / denom;
            let tilt = -9.0 + frac.powf(0.85) * 22.5;
            let raw = ((db + 56.0 + tilt) / 56.0).max(0.0);
            // Мягкое колено выше 0.78 вместо жёсткого упора басовых полос в 1.0.
            let level = if raw <= 0.78 {
                raw
            } else {
                0.78 + 0.22 * ((raw - 0.78) / 0.22).tanh()
            };
            out[band] = level.clamp(0.0, 1.0);
        }
        count
    }
}

fn fft_in_place(buf: &mut [(f32, f32); FFT_SIZE]) {
    let n = FFT_SIZE;
    let mut j = 0usize;
    for i in 1..n {
        let mut bit = n >> 1;
        while j & bit != 0 {
            j ^= bit;
            bit >>= 1;
        }
        j ^= bit;
        if i < j {
            buf.swap(i, j);
        }
    }
    let mut len = 2usize;
    while len <= n {
        let half = len >> 1;
        let angle = -std::f32::consts::TAU / len as f32;
        let (wlen_sin, wlen_cos) = angle.sin_cos();
        for start in (0..n).step_by(len) {
            let (mut wr, mut wi) = (1.0f32, 0.0f32);
            for k in 0..half {
                let (ur, ui) = buf[start + k];
                let (vr, vi) = buf[start + k + half];
                let tr = vr * wr - vi * wi;
                let ti = vr * wi + vi * wr;
                buf[start + k] = (ur + tr, ui + ti);
                buf[start + k + half] = (ur - tr, ui - ti);
                let next_wr = wr * wlen_cos - wi * wlen_sin;
                wi = wr * wlen_sin + wi * wlen_cos;
                wr = next_wr;
            }
        }
        len <<= 1;
    }
}

struct SpectrumTap<S> {
    inner: S,
    ring: Arc<Mutex<SpectrumRing>>,
    pos_us: Arc<AtomicU64>,
    channels: usize,
    sample_rate: u32,
    frames_played: u64,
    ch_idx: usize,
    mono_acc: f32,
    batch: [f32; 64],
    batch_len: usize,
}

impl<S: Source<Item = f32>> SpectrumTap<S> {
    fn new(inner: S, ring: Arc<Mutex<SpectrumRing>>, pos_us: Arc<AtomicU64>) -> Self {
        let channels = (inner.channels().get() as usize).max(1);
        let sample_rate = inner.sample_rate().get().max(1);
        pos_us.store(0, Ordering::Relaxed);
        Self {
            inner,
            ring,
            pos_us,
            channels,
            sample_rate,
            frames_played: 0,
            ch_idx: 0,
            mono_acc: 0.0,
            batch: [0.0; 64],
            batch_len: 0,
        }
    }

    fn flush_batch(&mut self) {
        if self.batch_len > 0 {
            if let Some(mut guard) = self.ring.try_lock() {
                guard.push_batch(&self.batch[..self.batch_len], self.sample_rate);
            }
            self.batch_len = 0;
        }
        let us = (u128::from(self.frames_played) * 1_000_000 / u128::from(self.sample_rate)) as u64;
        self.pos_us.store(us, Ordering::Relaxed);
    }
}

impl<S: Source<Item = f32>> Iterator for SpectrumTap<S> {
    type Item = f32;

    fn next(&mut self) -> Option<f32> {
        let sample = self.inner.next()?;
        self.mono_acc += sample;
        self.ch_idx += 1;
        if self.ch_idx >= self.channels {
            self.frames_played += 1;
            self.batch[self.batch_len] = self.mono_acc / self.channels as f32;
            self.batch_len += 1;
            if self.batch_len >= self.batch.len() {
                self.flush_batch();
            }
            self.ch_idx = 0;
            self.mono_acc = 0.0;
        }
        Some(sample)
    }
}

impl<S: Source<Item = f32>> Source for SpectrumTap<S> {
    fn current_span_len(&self) -> Option<usize> {
        self.inner.current_span_len()
    }

    fn channels(&self) -> rodio::ChannelCount {
        self.inner.channels()
    }

    fn sample_rate(&self) -> rodio::SampleRate {
        self.inner.sample_rate()
    }

    fn total_duration(&self) -> Option<Duration> {
        self.inner.total_duration()
    }

    fn try_seek(&mut self, pos: Duration) -> Result<(), rodio::source::SeekError> {
        self.ch_idx = 0;
        self.mono_acc = 0.0;
        self.batch_len = 0;
        if let Some(mut guard) = self.ring.try_lock() {
            guard.reset();
        }
        let res = self.inner.try_seek(pos);
        if res.is_ok() {
            self.frames_played = (pos.as_secs_f64() * f64::from(self.sample_rate)).round() as u64;
            self.pos_us.store(pos.as_micros() as u64, Ordering::Relaxed);
        }
        res
    }
}

/// Аудио живёт в отдельном потоке: устройство вывода в cpal не всегда `Send`.
pub struct Audio {
    tx: mpsc::Sender<Cmd>,
    spectrum: Arc<Mutex<SpectrumRing>>,
    spectrum_active: Arc<AtomicBool>,
}

impl Audio {
    pub fn spawn(on_event: impl Fn(Event) + Send + 'static) -> Self {
        let (tx, rx) = mpsc::channel();
        let spectrum = Arc::new(Mutex::new(SpectrumRing::default()));
        let spectrum_active = Arc::new(AtomicBool::new(false));
        let ring_clone = spectrum.clone();
        let active_clone = spectrum_active.clone();
        thread::Builder::new()
            .name("audio".into())
            .spawn(move || run(rx, ring_clone, active_clone, on_event))
            .expect("failed to spawn audio thread");
        Self { tx, spectrum, spectrum_active }
    }

    pub fn spectrum_levels(&self, out: &mut [f32]) -> usize {
        if !self.spectrum_active.load(Ordering::Relaxed) {
            out.fill(0.0);
            return out.len().min(SPECTRUM_BANDS);
        }
        self.spectrum.lock().compute_bands(out)
    }

    pub fn set_speed(&self, speed: f32) {
        let _ = self.tx.send(Cmd::Speed(speed.clamp(0.5, 2.0)));
    }

    pub fn set_sleep_fade(&self, factor: f32) {
        let _ = self.tx.send(Cmd::SleepFade(factor.clamp(0.0, 1.0)));
    }

    pub fn set_track_gain(&self, gain: f32) {
        let _ = self.tx.send(Cmd::TrackGain(gain.clamp(0.1, 2.0)));
    }

    pub fn load(&self, generation: u64, data: SourceData, track_gain: f32) {
        let _ = self.tx.send(Cmd::Load(generation, data, track_gain.clamp(0.1, 2.0)));
    }

    #[allow(dead_code)]
    pub fn play(&self) {
        let _ = self.tx.send(Cmd::Play);
    }

    pub fn pause(&self) {
        let _ = self.tx.send(Cmd::Pause);
    }

    pub fn toggle(&self) {
        let _ = self.tx.send(Cmd::Toggle);
    }

    pub fn seek(&self, secs: f64) {
        let _ = self.tx.send(Cmd::Seek(secs));
    }

    pub fn seek_relative(&self, delta_secs: f64) {
        let _ = self.tx.send(Cmd::SeekRelative(delta_secs));
    }

    pub fn set_volume(&self, volume: f32) {
        let _ = self.tx.send(Cmd::Volume(volume));
    }

    pub fn stop(&self) {
        let _ = self.tx.send(Cmd::Stop);
    }
}

const FADE_IN_STEPS: u8 = 12;
const FADE_IN_TICK: Duration = Duration::from_millis(15);
const FADE_OUT_PAUSE: Duration = Duration::from_millis(140);
const FADE_OUT_SWITCH: Duration = Duration::from_millis(90);

fn fade_out(player: &Player, from_vol: f32, duration: Duration) {
    if from_vol <= 0.001 || player.is_paused() || player.empty() {
        player.set_volume(0.0);
        return;
    }
    const STEPS: u32 = 12;
    let step_sleep = duration / STEPS;
    for i in (0..STEPS).rev() {
        player.set_volume(from_vol * (i as f32 / STEPS as f32));
        thread::sleep(step_sleep);
    }
}

fn run(
    rx: mpsc::Receiver<Cmd>,
    spectrum: Arc<Mutex<SpectrumRing>>,
    spectrum_active: Arc<AtomicBool>,
    on_event: impl Fn(Event),
) {
    let mut sink = match DeviceSinkBuilder::open_default_sink() {
        Ok(sink) => sink,
        Err(e) => {
            on_event(Event::Error(0, format!("Не удалось открыть аудиоустройство: {e}")));
            return;
        }
    };
    sink.log_on_drop(false);
    let player = Player::connect_new(sink.mixer());
    let mut active = false;
    let mut generation = 0u64;
    let mut stream: Option<StreamReader> = None;
    let mut target_volume: f32 = 1.0;
    let mut sleep_fade: f32 = 1.0;
    let mut track_gain: f32 = 1.0;
    let mut current_volume: f32 = 1.0;
    let mut current_speed: f32 = 1.0;
    let mut fade_in_remaining: u8 = 0;
    let mut last_pos_emit = Instant::now();
    let media_pos_us = Arc::new(AtomicU64::new(0));

    let effective_target = |v: f32, fade: f32, gain: f32| (v * fade * gain).clamp(0.0, 1.5);

    // Отпускает текущий поток, чтобы `clear()` не ждал сеть внутри `read()`.
    let release = |stream: &mut Option<StreamReader>| {
        if let Some(s) = stream.take() {
            s.cancel();
        }
    };

    loop {
        let tick = if fade_in_remaining > 0 && active && !player.is_paused() {
            FADE_IN_TICK
        } else if active && !player.is_paused() {
            Duration::from_millis(50)
        } else {
            Duration::from_millis(250)
        };
        match rx.recv_timeout(tick) {
            Ok(Cmd::Load(new_generation, data, new_gain)) => {
                if active && !player.is_paused() {
                    fade_out(&player, current_volume, FADE_OUT_SWITCH);
                }
                release(&mut stream);
                player.clear();
                spectrum.lock().reset();
                spectrum_active.store(false, Ordering::Relaxed);
                fade_in_remaining = 0;
                generation = new_generation;
                track_gain = new_gain;
                let res = match data {
                    SourceData::Cached { file, len, hint } => {
                        let ext = hint_ext(hint.as_deref());
                        let file_clone = file.try_clone().ok();
                        let primary = Decoder::builder()
                            .with_data(BufReader::new(file))
                            .with_byte_len(len)
                            .with_seekable(true)
                            .with_hint(ext)
                            .build();
                        let decoded = match primary {
                            Ok(s) => Ok(s),
                            Err(e) => {
                                if let Some( mut f2) = file_clone {
                                    use std::io::Seek;
                                    let _ = f2.seek(std::io::SeekFrom::Start(0));
                                    Decoder::builder()
                                        .with_data(BufReader::new(f2))
                                        .with_byte_len(len)
                                        .with_seekable(true)
                                        .build()
                                } else {
                                    Err(e)
                                }
                            }
                        };
                        decoded.map(|s| player.append(SpectrumTap::new(s, spectrum.clone(), media_pos_us.clone())))
                    }
                    SourceData::Stream { reader, hint } => {
                        stream = Some(reader.clone());
                        let ext = hint_ext(hint.as_deref());
                        let mut b = Decoder::builder()
                            .with_data(reader.clone())
                            .with_seekable(true)
                            .with_hint(ext);
                        if let Some(len) = reader.byte_len() {
                            b = b.with_byte_len(len);
                        }
                        let primary = b.build();
                        let decoded = match primary {
                            Ok(s) => Ok(s),
                            Err(_) => {
                                let mut b2 = Decoder::builder()
                                    .with_data(reader.clone())
                                    .with_seekable(true);
                                if let Some(len) = reader.byte_len() {
                                    b2 = b2.with_byte_len(len);
                                }
                                b2.build()
                            }
                        };
                        decoded.map(|s| player.append(SpectrumTap::new(s, spectrum.clone(), media_pos_us.clone())))
                    }
                };
                match res {
                    Ok(()) => {
                        current_volume = 0.0;
                        player.set_volume(0.0);
                        player.play();
                        active = true;
                        spectrum_active.store(true, Ordering::Relaxed);
                        fade_in_remaining = FADE_IN_STEPS;
                        last_pos_emit = Instant::now();
                        on_event(Event::Started(generation));
                    }
                    Err(e) => {
                        active = false;
                        spectrum_active.store(false, Ordering::Relaxed);
                        current_volume = effective_target(target_volume, sleep_fade, track_gain);
                        player.set_volume(current_volume);
                        release(&mut stream);
                        on_event(Event::Error(
                            generation,
                            format!("Не удалось декодировать трек: {e}"),
                        ));
                    }
                }
            }
            Ok(Cmd::Play) if active => {
                if player.is_paused() {
                    current_volume = 0.0;
                    player.set_volume(0.0);
                    player.play();
                    spectrum_active.store(true, Ordering::Relaxed);
                    fade_in_remaining = FADE_IN_STEPS;
                }
            }
            Ok(Cmd::Pause) if active => {
                if !player.is_paused() {
                    fade_out(&player, current_volume, FADE_OUT_PAUSE);
                    player.pause();
                    spectrum_active.store(false, Ordering::Relaxed);
                    current_volume = 0.0;
                    fade_in_remaining = 0;
                }
            }
            Ok(Cmd::Toggle) if active => {
                if player.is_paused() {
                    current_volume = 0.0;
                    player.set_volume(0.0);
                    player.play();
                    spectrum_active.store(true, Ordering::Relaxed);
                    fade_in_remaining = FADE_IN_STEPS;
                } else {
                    fade_out(&player, current_volume, FADE_OUT_PAUSE);
                    player.pause();
                    spectrum_active.store(false, Ordering::Relaxed);
                    current_volume = 0.0;
                    fade_in_remaining = 0;
                }
            }
            Ok(Cmd::Seek(secs)) if active => {
                // rodio's Speed::try_seek multiplies by speed, so divide by current_speed
                // to land on the exact media timestamp.
                let target_media = secs.max(0.0);
                let scaled = target_media / f64::from(current_speed.max(0.1));
                let _ = player.try_seek(Duration::from_secs_f64(scaled));
            }
            Ok(Cmd::SeekRelative(delta)) if active => {
                let cur = media_pos_us.load(Ordering::Relaxed) as f64 / 1_000_000.0;
                let target_media = (cur + delta).max(0.0);
                let scaled = target_media / f64::from(current_speed.max(0.1));
                let _ = player.try_seek(Duration::from_secs_f64(scaled));
            }
            Ok(Cmd::Volume(v)) => {
                target_volume = v;
                if fade_in_remaining == 0 {
                    current_volume = effective_target(target_volume, sleep_fade, track_gain);
                    player.set_volume(current_volume);
                }
            }
            Ok(Cmd::Speed(speed)) => {
                current_speed = speed.clamp(0.5, 2.0);
                player.set_speed(current_speed);
            }
            Ok(Cmd::SleepFade(factor)) => {
                sleep_fade = factor;
                if fade_in_remaining == 0 {
                    current_volume = effective_target(target_volume, sleep_fade, track_gain);
                    player.set_volume(current_volume);
                }
            }
            Ok(Cmd::TrackGain(gain)) => {
                track_gain = gain;
                if fade_in_remaining == 0 {
                    current_volume = effective_target(target_volume, sleep_fade, track_gain);
                    player.set_volume(current_volume);
                }
            }
            Ok(Cmd::Stop) => {
                if active && !player.is_paused() {
                    fade_out(&player, current_volume, FADE_OUT_PAUSE);
                }
                release(&mut stream);
                player.clear();
                spectrum.lock().reset();
                active = false;
                media_pos_us.store(0, Ordering::Relaxed);
                spectrum_active.store(false, Ordering::Relaxed);
                fade_in_remaining = 0;
                current_volume = effective_target(target_volume, sleep_fade, track_gain);
                player.set_volume(current_volume);
            }
            Ok(_) => {}
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => {
                release(&mut stream);
                break;
            }
        }

        if fade_in_remaining > 0 && active && !player.is_paused() {
            fade_in_remaining -= 1;
            let progress = 1.0 - (f32::from(fade_in_remaining) / f32::from(FADE_IN_STEPS));
            current_volume = effective_target(target_volume, sleep_fade, track_gain) * progress;
            player.set_volume(current_volume);
        }

        if active {
            if player.empty() {
                active = false;
                media_pos_us.store(0, Ordering::Relaxed);
                spectrum_active.store(false, Ordering::Relaxed);
                fade_in_remaining = 0;
                current_volume = effective_target(target_volume, sleep_fade, track_gain);
                player.set_volume(current_volume);
                stream = None;
                on_event(Event::Ended(generation));
            } else if last_pos_emit.elapsed() >= Duration::from_millis(45) {
                last_pos_emit = Instant::now();
                on_event(Event::Position {
                    generation,
                    secs: media_pos_us.load(Ordering::Relaxed) as f64 / 1_000_000.0,
                    paused: player.is_paused(),
                });
            }
        }
    }
}

fn hint_ext(codec: Option<&str>) -> &'static str {
    match codec.unwrap_or("mp3") {
        "flac" => "flac",
        "flac-mp4" | "aac-mp4" | "he-aac-mp4" | "aac" | "he-aac" | "m4a" | "mp4" => "m4a",
        _ => "mp3",
    }
}

#[cfg(test)]
mod spectrum_tests {
    use super::*;

    #[test]
    fn bass_peaks_retain_headroom_and_do_not_peg_edges() {
        let mut ring = SpectrumRing::default();
        let mut batch = [0.0f32; FFT_SIZE];
        let sr = 44100.0f32;
        for (i, sample) in batch.iter_mut().enumerate() {
            let t = i as f32 / sr;
            // Громкий 65 Гц бас + умеренные 3 кГц
            *sample = 0.55 * (std::f32::consts::TAU * 65.0 * t).sin()
                + 0.06 * (std::f32::consts::TAU * 3000.0 * t).sin();
        }
        ring.push_batch(&batch, 44100);

        let mut bands = [0.0f32; SPECTRUM_BANDS];
        let n = ring.compute_bands(&mut bands);
        assert_eq!(n, SPECTRUM_BANDS);
        let bass_peak = bands[0..8].iter().copied().fold(0.0f32, f32::max);
        let high_peak = bands[30..42].iter().copied().fold(0.0f32, f32::max);
        assert!(bass_peak > 0.45 && bass_peak < 0.92, "bass_peak={bass_peak}");
        assert!(high_peak > 0.25, "high_peak={high_peak}");
    }
}
