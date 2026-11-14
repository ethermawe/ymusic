use std::env;
use std::io::{self, Read, Write};
#[cfg(unix)]
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde_json::{Value, json};

use crate::api::Track;
use crate::mpris::Status;

/// Публичный Application ID («Яндекс Музыка» для режима «Слушает …»).
const DEFAULT_CLIENT_ID: &str = "1570127971413663804";

const OP_HANDSHAKE: u32 = 0;
const OP_FRAME: u32 = 1;
const OP_CLOSE: u32 = 2;
const OP_PING: u32 = 3;
const OP_PONG: u32 = 4;

const MAX_DISCORD_BYTES: usize = 128;

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
        let (tx, rx) = mpsc::channel();
        thread::Builder::new()
            .name("discord-rpc".into())
            .spawn(move || run(rx))
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

fn apply_cmd(
    cmd: Cmd,
    enabled: &mut bool,
    current: &mut Option<TrackInfo>,
    status: &mut Status,
    pos_secs: &mut f64,
    last_anchor_start_secs: Option<f64>,
    dirty: &mut bool,
) {
    match cmd {
        Cmd::Track(info, st) => {
            let is_same_track = current.as_ref().is_some_and(|t| t.id == info.id);
            *current = Some(info);
            *status = st;
            if !is_same_track {
                *pos_secs = 0.0;
            }
            *dirty = true;
        }
        Cmd::Status(st, secs) => {
            *pos_secs = secs;
            if st != *status {
                *status = st;
                *dirty = true;
            } else if st == Status::Playing {
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
            *dirty = true;
        }
        Cmd::SetEnabled(v) => {
            if *enabled != v {
                *enabled = v;
                *dirty = true;
            }
        }
    }
}

#[cfg(unix)]
type IpcStream = UnixStream;
#[cfg(windows)]
type IpcStream = std::fs::File;

fn run(rx: mpsc::Receiver<Cmd>) {
    let client_id = env::var("YM_DISCORD_CLIENT_ID")
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| DEFAULT_CLIENT_ID.to_string());

    let mut conn: Option<IpcStream> = None;
    let mut enabled = true;
    let mut current: Option<TrackInfo> = None;
    let mut status = Status::Stopped;
    let mut pos_secs = 0.0f64;
    let mut last_anchor_start_secs: Option<f64> = None;
    let mut nonce = 0u64;

    loop {
        let timeout = if enabled && current.is_some() && conn.is_none() {
            Duration::from_secs(5)
        } else {
            Duration::from_secs(30)
        };

        let mut dirty = false;
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
                    );
                }
            }
            Err(RecvTimeoutError::Timeout) => {
                if enabled && current.is_some() && conn.is_none() {
                    dirty = true;
                }
            }
            Err(RecvTimeoutError::Disconnected) => {
                if let Some(mut stream) = conn.take() {
                    let _ = send_activity(&mut stream, None, &mut nonce);
                }
                break;
            }
        }

        if !dirty {
            continue;
        }

        if !enabled || current.is_none() || status == Status::Stopped {
            if let Some(stream) = conn.as_mut()
                && send_activity(stream, None, &mut nonce).is_err()
            {
                conn = None;
            }
            if !enabled {
                conn = None;
            }
            last_anchor_start_secs = None;
            continue;
        }

        let Some(track) = current.as_ref() else {
            continue;
        };

        if conn.is_none() {
            conn = connect(&client_id);
        }
        let Some(stream) = conn.as_mut() else {
            continue;
        };

        let anchor_start_secs = now_secs() - pos_secs;
        let activity = build_activity(track, status, anchor_start_secs);
        match send_activity(stream, Some(activity), &mut nonce) {
            Ok(()) => {
                last_anchor_start_secs = if status == Status::Playing {
                    Some(anchor_start_secs)
                } else {
                    None
                };
            }
            Err(e) => {
                eprintln!("Discord RPC: не удалось обновить активность: {e}");
                conn = None;
                last_anchor_start_secs = None;
            }
        }
    }
}

fn build_activity(track: &TrackInfo, status: Status, start_secs: f64) -> Value {
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

    let mut activity = json!({
        "type": 2,
        "status_display_type": 2,
        "details": details,
        "state": state,
    });

    if status == Status::Playing && track.duration_secs > 0.0 {
        let start_ms = (start_secs.max(0.0) * 1000.0) as u64;
        let end_ms = ((start_secs + track.duration_secs).max(0.0) * 1000.0) as u64;
        activity["timestamps"] = json!({
            "start": start_ms,
            "end": end_ms,
        });
    }

    let mut assets = serde_json::Map::new();
    if let Some(cover) = &track.cover_url {
        assets.insert("large_image".into(), Value::String(cover.clone()));
    }
    if !track.album_title.trim().is_empty() {
        assets.insert(
            "large_text".into(),
            Value::String(pad_discord_str(&track.album_title, "Альбом")),
        );
    }
    if !assets.is_empty() {
        activity["assets"] = Value::Object(assets);
    }

    let track_url = match &track.album_id {
        Some(album_id) => format!("https://music.yandex.ru/album/{album_id}/track/{}", track.id),
        None => format!("https://music.yandex.ru/track/{}", track.id),
    };
    activity["buttons"] = json!([
        {
            "label": "Открыть в Яндекс Музыке",
            "url": track_url,
        }
    ]);

    activity
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
    let _ = stream.set_read_timeout(Some(Duration::from_secs(2)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(2)));
    Ok(stream)
}

#[cfg(windows)]
fn open_ipc(path: &Path) -> io::Result<IpcStream> {
    std::fs::OpenOptions::new().read(true).write(true).open(path)
}

fn connect(client_id: &str) -> Option<IpcStream> {
    for path in socket_candidates() {
        let Ok(mut stream) = open_ipc(&path) else {
            continue;
        };
        let handshake = json!({
            "v": 1,
            "client_id": client_id,
        });
        if write_frame(&mut stream, OP_HANDSHAKE, &handshake).is_ok() {
            match read_frame(&mut stream).and_then(|(opcode, bytes)| {
                let frame: Value = serde_json::from_slice(&bytes).map_err(io::Error::other)?;
                if opcode == OP_FRAME && frame["evt"] == "READY" { Ok(()) }
                else { Err(io::Error::other("Discord не подтвердил READY")) }
            }) {
                Ok(()) => return Some(stream),
                Err(e) => eprintln!("Discord RPC: ошибка подключения: {e}"),
            }
        }
    }
    None
}

#[cfg(unix)]
fn socket_candidates() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Ok(xdg) = env::var("XDG_RUNTIME_DIR") {
        let base = PathBuf::from(xdg);
        dirs.push(base.clone());
        dirs.push(base.join("app/com.discordapp.Discord"));
        dirs.push(base.join("app/dev.vencord.Vesktop"));
        dirs.push(base.join("snap.discord"));
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
        if opcode != OP_FRAME { return Err(io::Error::other("неожиданный opcode Discord")); }
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

fn write_frame(stream: &mut IpcStream, opcode: u32, payload: &Value) -> io::Result<()> {
    let data = serde_json::to_vec(payload).map_err(io::Error::other)?;
    let mut header = [0u8; 8];
    header[..4].copy_from_slice(&opcode.to_le_bytes());
    header[4..].copy_from_slice(&(data.len() as u32).to_le_bytes());
    stream.write_all(&header)?;
    stream.write_all(&data)?;
    stream.flush()
}

fn read_frame(stream: &mut IpcStream) -> io::Result<(u32, Vec<u8>)> {
    loop {
        let mut header = [0u8; 8];
        stream.read_exact(&mut header)?;
        let opcode = u32::from_le_bytes([header[0], header[1], header[2], header[3]]);
        let len = u32::from_le_bytes([header[4], header[5], header[6], header[7]]) as usize;
        if len > 1024 * 1024 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "frame too large",
            ));
        }
        let mut buf = vec![0u8; len];
        stream.read_exact(&mut buf)?;
        match opcode {
            OP_PING => {
                let mut out = [0u8; 8];
                out[..4].copy_from_slice(&OP_PONG.to_le_bytes());
                out[4..].copy_from_slice(&(len as u32).to_le_bytes());
                stream.write_all(&out)?;
                stream.write_all(&buf)?;
                stream.flush()?;
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
                    return Err(io::Error::other(format!("Discord отклонил запрос (код {}): {}",
                        val["data"]["code"], val["data"]["message"].as_str().unwrap_or("неизвестная ошибка"))));
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
        TrackInfo { id: "123".into(), album_id: Some("456".into()), title: "Название трека".into(),
            artists: "Исполнитель".into(), album_title: "Альбом".into(), duration_secs: 180.0,
            cover_url: Some("https://example.org/cover.jpg".into()) }
    }

    #[test]
    fn listening_status_uses_track_title() {
        let activity = build_activity(&track(), Status::Playing, 1000.0);
        assert_eq!(activity["type"], 2);
        assert_eq!(activity["status_display_type"], 2);
        assert_eq!(activity["details"], "Название трека");
        assert_eq!(activity["timestamps"]["end"], 1180000u64);
        let paused = build_activity(&track(), Status::Paused, 1000.0);
        assert!(paused.get("timestamps").is_none());
        assert!(paused["state"].as_str().unwrap().contains("На паузе"));
    }

    #[cfg(unix)]
    #[test]
    fn waits_for_matching_activity_acknowledgement() {
        let (mut client, mut server) = UnixStream::pair().unwrap();
        client.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
        let worker = thread::spawn(move || {
            let (_, bytes) = read_frame(&mut server).unwrap();
            let request: Value = serde_json::from_slice(&bytes).unwrap();
            write_frame(&mut server, OP_FRAME, &json!({"evt": "ACTIVITY_JOIN", "data": {}})).unwrap();
            write_frame(&mut server, OP_FRAME, &json!({"cmd": "SET_ACTIVITY", "nonce": request["nonce"], "data": {}})).unwrap();
        });
        send_activity(&mut client, Some(build_activity(&track(), Status::Playing, 1000.0)), &mut 0).unwrap();
        worker.join().unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn reports_discord_rejection() {
        let (mut client, mut server) = UnixStream::pair().unwrap();
        client.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
        let worker = thread::spawn(move || {
            read_frame(&mut server).unwrap();
            write_frame(&mut server, OP_FRAME, &json!({"evt": "ERROR", "data": {"code": 4000, "message": "Invalid activity"}})).unwrap();
        });
        let error = send_activity(&mut client, None, &mut 0).unwrap_err();
        assert!(error.to_string().contains("Invalid activity"));
        worker.join().unwrap();
    }
}
