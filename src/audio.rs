use std::fs::File;
use std::io::BufReader;
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread;
use std::time::Duration;

use rodio::{Decoder, DeviceSinkBuilder, Player};

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
    Cached { file: File, len: u64 },
    Stream(StreamReader),
}

enum Cmd {
    Load(u64, SourceData),
    #[allow(dead_code)]
    Play,
    Pause,
    Toggle,
    Seek(f64),
    SeekRelative(f64),
    Volume(f32),
    Stop,
}

/// Аудио живёт в отдельном потоке: устройство вывода в cpal не всегда `Send`.
pub struct Audio {
    tx: mpsc::Sender<Cmd>,
}

impl Audio {
    pub fn spawn(on_event: impl Fn(Event) + Send + 'static) -> Self {
        let (tx, rx) = mpsc::channel();
        thread::Builder::new()
            .name("audio".into())
            .spawn(move || run(rx, on_event))
            .expect("failed to spawn audio thread");
        Self { tx }
    }

    pub fn load(&self, generation: u64, data: SourceData) {
        let _ = self.tx.send(Cmd::Load(generation, data));
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

fn run(rx: mpsc::Receiver<Cmd>, on_event: impl Fn(Event)) {
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

    // Отпускает текущий поток, чтобы `clear()` не ждал сеть внутри `read()`.
    let release = |stream: &mut Option<StreamReader>| {
        if let Some(s) = stream.take() {
            s.cancel();
        }
    };

    loop {
        let tick = if active && !player.is_paused() {
            Duration::from_millis(50)
        } else {
            Duration::from_millis(250)
        };
        match rx.recv_timeout(tick) {
            Ok(Cmd::Load(new_generation, data)) => {
                release(&mut stream);
                player.clear();
                generation = new_generation;
                let res = match data {
                    SourceData::Cached { file, len } => Decoder::builder()
                        .with_data(BufReader::new(file))
                        .with_byte_len(len)
                        .with_seekable(true)
                        .with_hint("mp3")
                        .build()
                        .map(|s| player.append(s)),
                    SourceData::Stream(reader) => {
                        stream = Some(reader.clone());
                        let mut b = Decoder::builder()
                            .with_data(reader.clone())
                            .with_seekable(true)
                            .with_hint("mp3");
                        if let Some(len) = reader.byte_len() {
                            b = b.with_byte_len(len);
                        }
                        b.build().map(|s| player.append(s))
                    }
                };
                match res {
                    Ok(()) => {
                        player.play();
                        active = true;
                        on_event(Event::Started(generation));
                    }
                    Err(e) => {
                        active = false;
                        release(&mut stream);
                        on_event(Event::Error(
                            generation,
                            format!("Не удалось декодировать трек: {e}"),
                        ));
                    }
                }
            }
            Ok(Cmd::Play) if active => player.play(),
            Ok(Cmd::Pause) if active => player.pause(),
            Ok(Cmd::Toggle) if active => {
                if player.is_paused() {
                    player.play();
                } else {
                    player.pause();
                }
            }
            Ok(Cmd::Seek(secs)) if active => {
                let _ = player.try_seek(Duration::from_secs_f64(secs.max(0.0)));
            }
            Ok(Cmd::SeekRelative(delta)) if active => {
                let cur = player.get_pos().as_secs_f64();
                let _ = player.try_seek(Duration::from_secs_f64((cur + delta).max(0.0)));
            }
            Ok(Cmd::Volume(v)) => player.set_volume(v),
            Ok(Cmd::Stop) => {
                release(&mut stream);
                player.clear();
                active = false;
            }
            Ok(_) => {}
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => {
                release(&mut stream);
                break;
            }
        }

        if active {
            if player.empty() {
                active = false;
                stream = None;
                on_event(Event::Ended(generation));
            } else {
                on_event(Event::Position {
                    generation,
                    secs: player.get_pos().as_secs_f64(),
                    paused: player.is_paused(),
                });
            }
        }
    }
}
