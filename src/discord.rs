use std::env;
use std::io::{self, Read, Write};
#[cfg(unix)]
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde_json::{Value, json};

use crate::api::Track;
use crate::core::{EVENT_FEATURE, EventSink};
use crate::mpris::Status;

/// Публичные Application ID («Яндекс Музыку» / «Яндекс Музыка» для режима «Слушает …»).
const DEFAULT_CLIENT_ID: &str = "1269826362399522849";
const FALLBACK_CLIENT_ID: &str = "1217562797999784007";

const OP_HANDSHAKE: u32 = 0;
const OP_FRAME: u32 = 1;
const OP_CLOSE: u32 = 2;
const OP_PING: u32 = 3;
const OP_PONG: u32 = 4;

const MAX_DISCORD_BYTES: usize = 128;
const MAX_BUTTON_LABEL_BYTES: usize = 32;
const MAX_URL_BYTES: usize = 256;
const IPC_READ_TIMEOUT: Duration = Duration::from_millis(2500);
const TRACK_START_DEBOUNCE: Duration = Duration::from_millis(250);
const MIN_UPDATE_INTERVAL: Duration = Duration::from_millis(1200);
const RECONNECT_INTERVAL: Duration = Duration::from_secs(3);
const POST_CONNECT_RESYNC_DELAY: Duration = Duration::from_secs(5);
const KEEPALIVE_INTERVAL: Duration = Duration::from_secs(15);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CompatLevel {
    Full = 0,
    ListeningBasic = 1,
    PlayingCompat = 2,
    Minimal = 3,
}

impl CompatLevel {
    fn fallback(self) -> Option<Self> {
        match self {
            Self::Full => Some(Self::ListeningBasic),
            Self::ListeningBasic => Some(Self::PlayingCompat),
            Self::PlayingCompat => Some(Self::Minimal),
            Self::Minimal => None,
        }
    }
}

#[derive(Clone, Debug)]
struct TrackInfo {
    id: String,
    album_id: Option<String>,
    title: String,
    artists: String,
    album_title: String,
    duration_secs: f64,
    cover_url: Option<String>,
}

enum Cmd {
    Track(TrackInfo, Status),
    Status(Status, f64),
    Clear,
    SetEnabled(bool),
}

pub struct Discord {
    tx: mpsc::Sender<Cmd>,
}

impl Discord {
    pub fn spawn() -> Self {
        Self::spawn_inner(None)
    }

    pub fn spawn_with_sink(sink: Arc<dyn EventSink>) -> Self {
        Self::spawn_inner(Some(sink))
    }

    fn spawn_inner(sink: Option<Arc<dyn EventSink>>) -> Self {
        let (tx, rx) = mpsc::channel();
        thread::Builder::new()
            .name("discord-rpc".into())
            .spawn(move || run(rx, sink))
            .expect("failed to spawn discord-rpc thread");
        Self { tx }
    }

    pub fn set_track(&self, track: &Track, status: Status) {
        let info = TrackInfo {
            id: track.id.clone(),
            album_id: track.album_id.clone(),
            title: track.title.clone(),
            artists: track.artists.clone(),
            album_title: track.album_title.clone(),
            duration_secs: track.duration_ms as f64 / 1000.0,
            cover_url: track.cover_url(400),
        };
        let _ = self.tx.send(Cmd::Track(info, status));
    }

    pub fn set_status(&self, status: Status, position_secs: f64) {
        let _ = self.tx.send(Cmd::Status(status, position_secs));
    }

    pub fn set_stopped(&self) {
        let _ = self.tx.send(Cmd::Clear);
    }

    pub fn set_enabled(&self, enabled: bool) {
        let _ = self.tx.send(Cmd::SetEnabled(enabled));
    }
}

struct StatusReporter {
    sink: Option<Arc<dyn EventSink>>,
    last: Option<(bool, String)>,
}

impl StatusReporter {
    fn new(sink: Option<Arc<dyn EventSink>>) -> Self {
        Self { sink, last: None }
    }

    fn report(&mut self, connected: bool, is_error: bool, text: impl Into<String>) {
        let text = text.into();
        let key = (connected, text.clone());
        if self.last.as_ref() == Some(&key) {
            return;
        }
        self.last = Some(key);
        if is_error {
            eprintln!("Discord RPC: {text}");
        }
        if let Some(sink) = &self.sink {
            let payload = json!({
                "type": "discord_status",
                "connected": connected,
                "is_error": is_error,
                "text": text,
            });
            sink.on_event(EVENT_FEATURE, &payload.to_string());
        }
    }
}

fn apply_cmd(
    cmd: Cmd,
    enabled: &mut bool,
    current: &mut Option<TrackInfo>,
    status: &mut Status,
    pos_secs: &mut f64,
    last_anchor_start_secs: Option<f64>,
    dirty: &mut bool,
    pending_until: &mut Option<Instant>,
) {
    match cmd {
        Cmd::Track(info, st) => {
            let is_same_track = current.as_ref().is_some_and(|t| t.id == info.id);
            *current = Some(info);
            *status = st;
            if !is_same_track {
                *pos_secs = 0.0;
                // Wait briefly for the immediate Status::Playing that follows audio start
                // so track changes do not burn rate-limit budget with a Paused->Playing burst.
                if st == Status::Paused {
                    *pending_until = Some(Instant::now() + TRACK_START_DEBOUNCE);
                } else {
                    *pending_until = None;
                }
            } else {
                *pending_until = None;
            }
            *dirty = true;
        }
        Cmd::Status(st, secs) => {
            *pos_secs = secs;
            if st != *status {
                *status = st;
                *dirty = true;
                *pending_until = None;
            } else if st == Status::Playing {
                *pending_until = None;
                if let Some(prev_anchor) = last_anchor_start_secs {
                    let expected_start = now_secs() - secs;
                    if (expected_start - prev_anchor).abs() > 2.5 {
                        *dirty = true;
                    }
                } else {
                    *dirty = true;
                }
            }
        }
        Cmd::Clear => {
            *current = None;
            *status = Status::Stopped;
            *pos_secs = 0.0;
            *pending_until = None;
            *dirty = true;
        }
        Cmd::SetEnabled(v) => {
            if *enabled != v {
                *enabled = v;
                *pending_until = None;
                *dirty = true;
            }
        }
    }
}

#[cfg(unix)]
type IpcStream = UnixStream;
#[cfg(windows)]
type IpcStream = std::fs::File;

fn resolve_client_ids() -> Vec<String> {
    if let Some(custom) = env::var("YM_DISCORD_CLIENT_ID")
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
    {
        return vec![custom];
    }
    vec![
        DEFAULT_CLIENT_ID.to_string(),
        FALLBACK_CLIENT_ID.to_string(),
    ]
}

fn run(rx: mpsc::Receiver<Cmd>, sink: Option<Arc<dyn EventSink>>) {
    let client_ids = resolve_client_ids();

    let mut reporter = StatusReporter::new(sink);
    let mut conn: Option<IpcStream> = None;
    let mut compat = CompatLevel::Full;
    let mut enabled = true;
    let mut current: Option<TrackInfo> = None;
    let mut status = Status::Stopped;
    let mut pos_secs = 0.0f64;
    let mut last_anchor_start_secs: Option<f64> = None;
    let mut last_send_at: Option<Instant> = None;
    let mut last_connect_attempt: Option<Instant> = None;
    let mut connected_at: Option<Instant> = None;
    let mut did_post_connect_resync = false;
    let mut pending_until: Option<Instant> = None;
    let mut dirty = false;
    let mut nonce = 0u64;

    loop {
        let now = Instant::now();
        let active_track = enabled && current.is_some() && status != Status::Stopped;
        let next_maintenance = if active_track {
            if conn.is_none() {
                Some(
                    last_connect_attempt
                        .map(|t| t + RECONNECT_INTERVAL)
                        .unwrap_or(now),
                )
            } else if !did_post_connect_resync {
                connected_at.map(|t| t + POST_CONNECT_RESYNC_DELAY)
            } else if status == Status::Playing {
                last_send_at.map(|t| t + KEEPALIVE_INTERVAL)
            } else {
                None
            }
        } else {
            None
        };

        let mut timeout = Duration::from_secs(30);
        if let Some(deadline) = pending_until {
            timeout = timeout.min(deadline.saturating_duration_since(now));
        } else if dirty && conn.is_some() {
            timeout = timeout.min(Duration::from_millis(50));
        }
        if let Some(deadline) = next_maintenance {
            timeout = timeout.min(deadline.saturating_duration_since(now));
        }

        match rx.recv_timeout(timeout) {
            Ok(first_cmd) => {
                apply_cmd(
                    first_cmd,
                    &mut enabled,
                    &mut current,
                    &mut status,
                    &mut pos_secs,
                    last_anchor_start_secs,
                    &mut dirty,
                    &mut pending_until,
                );
                for cmd in rx.try_iter() {
                    apply_cmd(
                        cmd,
                        &mut enabled,
                        &mut current,
                        &mut status,
                        &mut pos_secs,
                        last_anchor_start_secs,
                        &mut dirty,
                        &mut pending_until,
                    );
                }
            }
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => {
                if let Some(mut stream) = conn.take() {
                    let _ = send_activity(&mut stream, None, &mut nonce);
                }
                break;
            }
        }

        let now = Instant::now();
        if pending_until.is_some_and(|d| now >= d) {
            pending_until = None;
        }
        if enabled && current.is_some() && status != Status::Stopped {
            if conn.is_none() {
                if last_connect_attempt.is_none_or(|t| now.duration_since(t) >= RECONNECT_INTERVAL)
                {
                    dirty = true;
                }
            } else if !did_post_connect_resync
                && connected_at.is_some_and(|t| now.duration_since(t) >= POST_CONNECT_RESYNC_DELAY)
            {
                did_post_connect_resync = true;
                dirty = true;
            } else if status == Status::Playing
                && last_send_at.is_some_and(|t| now.duration_since(t) >= KEEPALIVE_INTERVAL)
            {
                dirty = true;
            }
        }

        if !dirty {
            continue;
        }
        if let Some(deadline) = pending_until
            && now < deadline
        {
            continue;
        }

        if !enabled {
            if let Some(mut stream) = conn.take() {
                let _ = send_activity(&mut stream, None, &mut nonce);
            }
            connected_at = None;
            did_post_connect_resync = false;
            last_anchor_start_secs = None;
            dirty = false;
            pending_until = None;
            reporter.report(false, false, "Отключено");
            continue;
        }

        if current.is_none() || status == Status::Stopped {
            if let Some(stream) = conn.as_mut()
                && send_activity(stream, None, &mut nonce).is_err()
            {
                conn = None;
                connected_at = None;
                did_post_connect_resync = false;
            }
            last_anchor_start_secs = None;
            dirty = false;
            pending_until = None;
            reporter.report(conn.is_some(), false, "Ожидание воспроизведения");
            continue;
        }

        // Throttle bursts caused by rapid seeks/skips; reschedule cleanly via pending_until.
        if let Some(prev) = last_send_at {
            let elapsed = prev.elapsed();
            if elapsed < MIN_UPDATE_INTERVAL && conn.is_some() {
                pending_until = Some(Instant::now() + (MIN_UPDATE_INTERVAL - elapsed));
                continue;
            }
        }

        let Some(track) = current.as_ref() else {
            dirty = false;
            continue;
        };

        if conn.is_none() {
            if last_connect_attempt.is_some_and(|t| now.duration_since(t) < RECONNECT_INTERVAL) {
                continue;
            }
            last_connect_attempt = Some(now);
            match connect_any(&client_ids) {
                Ok(stream) => {
                    conn = Some(stream);
                    compat = CompatLevel::Full;
                    connected_at = Some(Instant::now());
                    did_post_connect_resync = false;
                }
                Err(msg) => {
                    connected_at = None;
                    did_post_connect_resync = false;
                    last_anchor_start_secs = None;
                    dirty = false;
                    reporter.report(
                        false,
                        msg.is_some(),
                        msg.unwrap_or_else(|| "Discord не обнаружен".into()),
                    );
                    continue;
                }
            }
        }

        let anchor_start_secs = now_secs() - pos_secs;
        let mut sent = false;
        let mut last_err: Option<String> = None;

        for _attempt in 0..4 {
            if conn.is_none() {
                match connect_any(&client_ids) {
                    Ok(stream) => {
                        conn = Some(stream);
                        connected_at = Some(Instant::now());
                        did_post_connect_resync = false;
                    }
                    Err(msg) => {
                        last_err = msg.or(last_err);
                        break;
                    }
                }
            }
            let Some(stream) = conn.as_mut() else {
                break;
            };

            let activity = build_activity(track, status, anchor_start_secs, compat);
            match send_activity(stream, Some(activity), &mut nonce) {
                Ok(()) => {
                    sent = true;
                    break;
                }
                Err(err) => {
                    let msg = err.to_string();
                    last_err = Some(msg.clone());
                    let is_rejection =
                        msg.contains("Discord отклонил запрос") || msg.contains("неожиданн");
                    if !is_rejection {
                        conn = None;
                        connected_at = None;
                    }
                    if let Some(next_compat) = compat.fallback() {
                        compat = next_compat;
                        continue;
                    }
                    conn = None;
                    connected_at = None;
                    break;
                }
            }
        }

        dirty = false;
        pending_until = None;
        if sent {
            last_send_at = Some(Instant::now());
            last_anchor_start_secs = if status == Status::Playing {
                Some(anchor_start_secs)
            } else {
                None
            };
            reporter.report(true, false, "Подключён к Discord");
        } else {
            last_anchor_start_secs = None;
            reporter.report(
                false,
                true,
                last_err.unwrap_or_else(|| "Не удалось обновить статус в Discord".into()),
            );
        }
    }
}

fn build_activity(
    track: &TrackInfo,
    status: Status,
    start_secs: f64,
    compat: CompatLevel,
) -> Value {
    let details = pad_discord_str(&track.title, "Без названия");
    let raw_artists = if track.artists.trim().is_empty() {
        "Неизвестный исполнитель".to_string()
    } else {
        track.artists.trim().to_string()
    };

    let state_str = if status == Status::Paused {
        format!("{raw_artists} (На паузе)")
    } else {
        raw_artists
    };
    let state = pad_discord_str(&state_str, "Исполнитель");

    let mut activity = serde_json::Map::new();
    match compat {
        CompatLevel::Full => {
            activity.insert("type".into(), json!(2));
            activity.insert("status_display_type".into(), json!(2));
        }
        CompatLevel::ListeningBasic => {
            activity.insert("type".into(), json!(2));
        }
        CompatLevel::PlayingCompat => {
            activity.insert("type".into(), json!(0));
        }
        CompatLevel::Minimal => {}
    }
    activity.insert("details".into(), Value::String(details));
    activity.insert("state".into(), Value::String(state));

    if status == Status::Playing && track.duration_secs > 0.0 {
        let start_s = start_secs.max(0.0).floor() as u64;
        let end_s = (start_secs + track.duration_secs).max(0.0).ceil() as u64;
        if end_s > start_s {
            activity.insert(
                "timestamps".into(),
                json!({
                    "start": start_s,
                    "end": end_s,
                }),
            );
        }
    }

    let mut assets = serde_json::Map::new();
    if let Some(cover) = track.cover_url.as_deref().filter(|u| {
        (u.starts_with("https://") || u.starts_with("http://")) && u.len() <= MAX_URL_BYTES
    }) {
        assets.insert("large_image".into(), Value::String(cover.to_string()));
    }
    if !track.album_title.trim().is_empty() {
        assets.insert(
            "large_text".into(),
            Value::String(pad_discord_str(&track.album_title, "Альбом")),
        );
    }
    if !assets.is_empty() {
        activity.insert("assets".into(), Value::Object(assets));
    }

    if compat != CompatLevel::Minimal
        && !track.id.trim().is_empty()
        && !track.id.starts_with("local:")
    {
        let track_url = match &track.album_id {
            Some(album_id) if !album_id.trim().is_empty() => {
                format!(
                    "https://music.yandex.ru/album/{album_id}/track/{}",
                    track.id
                )
            }
            _ => format!("https://music.yandex.ru/track/{}", track.id),
        };
        const BUTTON_LABEL: &str = "Открыть трек";
        if track_url.len() <= MAX_URL_BYTES && BUTTON_LABEL.len() <= MAX_BUTTON_LABEL_BYTES {
            activity.insert(
                "buttons".into(),
                json!([
                    {
                        "label": BUTTON_LABEL,
                        "url": track_url,
                    }
                ]),
            );
        }
    }

    Value::Object(activity)
}

fn pad_discord_str(s: &str, fallback: &str) -> String {
    let trimmed = s.trim();
    if trimmed.is_empty() {
        return fallback.to_string();
    }
    if trimmed.chars().count() < 2 {
        return format!("{trimmed} ");
    }
    if trimmed.len() <= MAX_DISCORD_BYTES {
        return trimmed.to_string();
    }

    let max_len = MAX_DISCORD_BYTES - '…'.len_utf8();
    let mut end = 0;
    for (idx, ch) in trimmed.char_indices() {
        let next_end = idx + ch.len_utf8();
        if next_end > max_len {
            break;
        }
        end = next_end;
    }

    let mut out = trimmed[..end].to_string();
    out.push('…');
    out
}

#[cfg(unix)]
fn open_ipc(path: &Path) -> io::Result<IpcStream> {
    let stream = UnixStream::connect(path)?;
    let _ = stream.set_read_timeout(Some(IPC_READ_TIMEOUT));
    let _ = stream.set_write_timeout(Some(IPC_READ_TIMEOUT));
    Ok(stream)
}

#[cfg(windows)]
#[link(name = "kernel32")]
unsafe extern "system" {
    fn WaitNamedPipeW(lp_named_pipe_name: *const u16, n_time_out: u32) -> i32;
    fn PeekNamedPipe(
        h_named_pipe: *mut core::ffi::c_void,
        lp_buffer: *mut core::ffi::c_void,
        n_buffer_size: u32,
        lp_bytes_read: *mut u32,
        lp_total_bytes_avail: *mut u32,
        lp_bytes_left_this_message: *mut u32,
    ) -> i32;
}

#[cfg(windows)]
fn open_ipc(path: &Path) -> io::Result<IpcStream> {
    use std::os::windows::ffi::OsStrExt;
    const ERROR_PIPE_BUSY: i32 = 231;

    match std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(path)
    {
        Ok(file) => Ok(file),
        Err(err) if err.raw_os_error() == Some(ERROR_PIPE_BUSY) => {
            let wide: Vec<u16> = path.as_os_str().encode_wide().chain(Some(0)).collect();
            unsafe {
                WaitNamedPipeW(wide.as_ptr(), 500);
            }
            std::fs::OpenOptions::new()
                .read(true)
                .write(true)
                .open(path)
        }
        Err(err) => Err(err),
    }
}

#[cfg(unix)]
fn read_exact_ipc(stream: &mut IpcStream, buf: &mut [u8], _timeout: Duration) -> io::Result<()> {
    stream.read_exact(buf)
}

#[cfg(windows)]
fn read_exact_ipc(stream: &mut IpcStream, buf: &mut [u8], timeout: Duration) -> io::Result<()> {
    use std::os::windows::io::AsRawHandle;

    let deadline = Instant::now() + timeout;
    let handle = stream.as_raw_handle();
    loop {
        let mut avail: u32 = 0;
        let ok = unsafe {
            PeekNamedPipe(
                handle,
                std::ptr::null_mut(),
                0,
                std::ptr::null_mut(),
                &mut avail,
                std::ptr::null_mut(),
            )
        };
        if ok == 0 {
            return Err(io::Error::last_os_error());
        }
        if (avail as usize) >= buf.len() {
            return stream.read_exact(buf);
        }
        if Instant::now() >= deadline {
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                "Таймаут ответа Discord IPC",
            ));
        }
        thread::sleep(Duration::from_millis(20));
    }
}

fn connect_any(client_ids: &[String]) -> Result<IpcStream, Option<String>> {
    let mut last_err: Option<String> = None;
    for id in client_ids {
        match connect(id) {
            Ok(stream) => return Ok(stream),
            Err(None) => return Err(last_err),
            Err(Some(msg)) => last_err = Some(msg),
        }
    }
    Err(last_err)
}

fn connect(client_id: &str) -> Result<IpcStream, Option<String>> {
    let mut last_err: Option<String> = None;
    for path in socket_candidates() {
        let Ok(mut stream) = open_ipc(&path) else {
            continue;
        };
        let handshake = json!({
            "v": 1,
            "client_id": client_id,
        });
        if let Err(e) = write_frame(&mut stream, OP_HANDSHAKE, &handshake) {
            last_err = Some(format!("ошибка handshake: {e}"));
            continue;
        }
        match read_frame(&mut stream).and_then(|(opcode, bytes)| {
            let frame: Value = serde_json::from_slice(&bytes).map_err(io::Error::other)?;
            if opcode == OP_FRAME && frame["evt"] == "READY" {
                Ok(())
            } else {
                Err(io::Error::other("Discord не подтвердил READY"))
            }
        }) {
            Ok(()) => return Ok(stream),
            Err(e) => {
                last_err = Some(format!("ошибка подключения: {e}"));
            }
        }
    }
    Err(last_err)
}

#[cfg(unix)]
fn socket_candidates() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Ok(xdg) = env::var("XDG_RUNTIME_DIR") {
        let base = PathBuf::from(xdg);
        dirs.push(base.clone());
        dirs.push(base.join("app/com.discordapp.Discord"));
        dirs.push(base.join("app/com.discordapp.DiscordCanary"));
        dirs.push(base.join("app/com.discordapp.DiscordPTB"));
        dirs.push(base.join("app/dev.vencord.Vesktop"));
        dirs.push(base.join("app/io.github.spacingbat3.webcord"));
        dirs.push(base.join("app/xyz.armcord.ArmCord"));
        dirs.push(base.join("app/org.equicord.equibop"));
        dirs.push(base.join("snap.discord"));
        dirs.push(base.join("snap.discord-canary"));
        dirs.push(base.join(".flatpak/com.discordapp.Discord/xdg-run"));
        dirs.push(base.join(".flatpak/dev.vencord.Vesktop/xdg-run"));
    }
    dirs.push(PathBuf::from("/tmp"));

    let mut out = Vec::new();
    for dir in dirs {
        for i in 0..10 {
            let candidate = dir.join(format!("discord-ipc-{i}"));
            if candidate.exists() {
                out.push(candidate);
            }
        }
    }
    out
}

#[cfg(windows)]
fn socket_candidates() -> Vec<PathBuf> {
    (0..10)
        .map(|i| PathBuf::from(format!(r"\\.\pipe\discord-ipc-{i}")))
        .collect()
}

fn send_activity(
    stream: &mut IpcStream,
    activity: Option<Value>,
    nonce: &mut u64,
) -> io::Result<()> {
    *nonce += 1;
    let payload = json!({
        "cmd": "SET_ACTIVITY",
        "args": {
            "pid": std::process::id(),
            "activity": activity,
        },
        "nonce": nonce.to_string(),
    });
    write_frame(stream, OP_FRAME, &payload)?;
    let expected = nonce.to_string();
    // Dispatches may arrive before the SET_ACTIVITY response. Only the
    // matching nonce confirms this update, not an unrelated event.
    for _ in 0..16 {
        let (opcode, bytes) = read_frame(stream)?;
        if opcode != OP_FRAME {
            return Err(io::Error::other("неожиданный opcode Discord"));
        }
        let response: Value = serde_json::from_slice(&bytes).map_err(io::Error::other)?;
        if response["nonce"].as_str() == Some(expected.as_str()) {
            if response["cmd"] != "SET_ACTIVITY" {
                return Err(io::Error::other("неожиданное подтверждение Discord"));
            }
            return Ok(());
        }
    }
    Err(io::Error::other("Discord не подтвердил SET_ACTIVITY"))
}

fn write_raw_frame(stream: &mut IpcStream, opcode: u32, data: &[u8]) -> io::Result<()> {
    let mut packet = Vec::with_capacity(8 + data.len());
    packet.extend_from_slice(&opcode.to_le_bytes());
    packet.extend_from_slice(&(data.len() as u32).to_le_bytes());
    packet.extend_from_slice(data);
    stream.write_all(&packet)?;
    stream.flush()
}

fn write_frame(stream: &mut IpcStream, opcode: u32, payload: &Value) -> io::Result<()> {
    let data = serde_json::to_vec(payload).map_err(io::Error::other)?;
    write_raw_frame(stream, opcode, &data)
}

fn read_frame(stream: &mut IpcStream) -> io::Result<(u32, Vec<u8>)> {
    loop {
        let mut header = [0u8; 8];
        read_exact_ipc(stream, &mut header, IPC_READ_TIMEOUT)?;
        let opcode = u32::from_le_bytes([header[0], header[1], header[2], header[3]]);
        let len = u32::from_le_bytes([header[4], header[5], header[6], header[7]]) as usize;
        if len > 1024 * 1024 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "frame too large",
            ));
        }
        let mut buf = vec![0u8; len];
        if len > 0 {
            read_exact_ipc(stream, &mut buf, IPC_READ_TIMEOUT)?;
        }
        match opcode {
            OP_PING => {
                write_raw_frame(stream, OP_PONG, &buf)?;
            }
            OP_CLOSE => {
                return Err(io::Error::new(
                    io::ErrorKind::ConnectionAborted,
                    "discord closed ipc",
                ));
            }
            OP_FRAME => {
                if let Ok(val) = serde_json::from_slice::<Value>(&buf)
                    && val.get("evt").and_then(Value::as_str) == Some("ERROR")
                {
                    return Err(io::Error::other(format!(
                        "Discord отклонил запрос (код {}): {}",
                        val["data"]["code"],
                        val["data"]["message"]
                            .as_str()
                            .unwrap_or("неизвестная ошибка")
                    )));
                }
                return Ok((opcode, buf));
            }
            _ => return Ok((opcode, buf)),
        }
    }
}

fn now_secs() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn track() -> TrackInfo {
        TrackInfo {
            id: "123".into(),
            album_id: Some("456".into()),
            title: "Название трека".into(),
            artists: "Исполнитель".into(),
            album_title: "Альбом".into(),
            duration_secs: 180.0,
            cover_url: Some("https://example.org/cover.jpg".into()),
        }
    }

    #[test]
    fn listening_status_uses_track_title_and_seconds_timestamps() {
        let activity = build_activity(&track(), Status::Playing, 1000.0, CompatLevel::Full);
        assert_eq!(activity["type"], 2);
        assert_eq!(activity["status_display_type"], 2);
        assert_eq!(activity["details"], "Название трека");
        assert_eq!(activity["timestamps"]["start"], 1000u64);
        assert_eq!(activity["timestamps"]["end"], 1180u64);
        let paused = build_activity(&track(), Status::Paused, 1000.0, CompatLevel::Full);
        assert!(paused.get("timestamps").is_none());
        // assert!(paused["state"].as_str().unwrap().contains("На паузе"));
    }

    #[test]
    fn compat_fallback_strips_newer_fields() {
        let t = track();
        let b = build_activity(&t, Status::Playing, 1000.0, CompatLevel::ListeningBasic);
        assert_eq!(b["type"], 2);
        assert!(b.get("status_display_type").is_none());

        let c = build_activity(&t, Status::Playing, 1000.0, CompatLevel::PlayingCompat);
        assert_eq!(c["type"], 0);
        assert!(c.get("buttons").is_some());

        let m = build_activity(&t, Status::Playing, 1000.0, CompatLevel::Minimal);
        assert!(m.get("type").is_none());
        assert!(m.get("buttons").is_none());
        assert_eq!(m["details"], "Название трека");
    }

    #[test]
    fn button_label_fits_utf8_byte_limit_and_default_client_id_is_registered() {
        assert_eq!(DEFAULT_CLIENT_ID, "1269826362399522849");
        assert_eq!(FALLBACK_CLIENT_ID, "1217562797999784007");
        let activity = build_activity(&track(), Status::Playing, 1000.0, CompatLevel::Full);
        let label = activity["buttons"][0]["label"].as_str().unwrap();
        assert!(
            label.len() <= MAX_BUTTON_LABEL_BYTES,
            "label byte len = {}",
            label.len()
        );
    }

    #[cfg(unix)]
    #[test]
    fn waits_for_matching_activity_acknowledgement() {
        let (mut client, mut server) = UnixStream::pair().unwrap();
        client
            .set_read_timeout(Some(Duration::from_secs(2)))
            .unwrap();
        let worker = thread::spawn(move || {
            let (_, bytes) = read_frame(&mut server).unwrap();
            let request: Value = serde_json::from_slice(&bytes).unwrap();
            write_frame(
                &mut server,
                OP_FRAME,
                &json!({"evt": "ACTIVITY_JOIN", "data": {}}),
            )
            .unwrap();
            write_frame(
                &mut server,
                OP_FRAME,
                &json!({"cmd": "SET_ACTIVITY", "nonce": request["nonce"], "data": {}}),
            )
            .unwrap();
        });
        send_activity(
            &mut client,
            Some(build_activity(
                &track(),
                Status::Playing,
                1000.0,
                CompatLevel::Full,
            )),
            &mut 0,
        )
        .unwrap();
        worker.join().unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn reports_discord_rejection() {
        let (mut client, mut server) = UnixStream::pair().unwrap();
        client
            .set_read_timeout(Some(Duration::from_secs(2)))
            .unwrap();
        let worker = thread::spawn(move || {
            read_frame(&mut server).unwrap();
            write_frame(
                &mut server,
                OP_FRAME,
                &json!({"evt": "ERROR", "data": {"code": 4000, "message": "Invalid activity"}}),
            )
            .unwrap();
        });
        let error = send_activity(&mut client, None, &mut 0).unwrap_err();
        assert!(error.to_string().contains("Invalid activity"));
        worker.join().unwrap();
    }
}
