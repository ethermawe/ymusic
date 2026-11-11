use std::env;
use std::io::{self, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde_json::{Value, json};

use crate::api::Track;
use crate::mpris::Status;

/// Публичный Application ID («Яндекс Музыку» для режима «Слушает …»).
const DEFAULT_CLIENT_ID: &str = "1570127971413663804";

const OP_HANDSHAKE: u32 = 0;
const OP_FRAME: u32 = 1;
const OP_CLOSE: u32 = 2;
const OP_PING: u32 = 3;
const OP_PONG: u32 = 4;

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
}

fn run(rx: mpsc::Receiver<Cmd>) {
    let client_id = env::var("YM_DISCORD_CLIENT_ID")
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| DEFAULT_CLIENT_ID.to_string());

    let mut conn: Option<UnixStream> = None;
    let mut current: Option<TrackInfo> = None;
    let mut status = Status::Stopped;
    let mut pos_secs = 0.0f64;
    let mut last_anchor_start_secs: Option<f64> = None;
    let mut nonce = 0u64;

    loop {
        let timeout = if current.is_some() && conn.is_none() {
            Duration::from_secs(5)
        } else {
            Duration::from_secs(30)
        };

        let mut dirty = false;
        match rx.recv_timeout(timeout) {
            Ok(Cmd::Track(info, st)) => {
                current = Some(info);
                status = st;
                pos_secs = 0.0;
                dirty = true;
            }
            Ok(Cmd::Status(st, secs)) => {
                pos_secs = secs;
                if st != status {
                    status = st;
                    dirty = true;
                } else if st == Status::Playing
                    && let Some(prev_anchor) = last_anchor_start_secs
                {
                    let expected_start = now_secs() - secs;
                    if (expected_start - prev_anchor).abs() > 2.5 {
                        dirty = true;
                    }
                }
            }
            Ok(Cmd::Clear) => {
                current = None;
                status = Status::Stopped;
                pos_secs = 0.0;
                dirty = true;
            }
            Err(RecvTimeoutError::Timeout) => {
                if current.is_some() && conn.is_none() {
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

        if current.is_none() || status == Status::Stopped {
            if let Some(stream) = conn.as_mut()
                && send_activity(stream, None, &mut nonce).is_err()
            {
                conn = None;
            }
            last_anchor_start_secs = None;
            continue;
        }

        let Some(track) = current.as_ref() else { continue };

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
                last_anchor_start_secs = Some(anchor_start_secs);
            }
            Err(_) => {
                conn = None;
                last_anchor_start_secs = None;
            }
        }
    }
}

fn build_activity(track: &TrackInfo, status: Status, start_secs: f64) -> Value {
    let details = pad_discord_str(&track.title, "Без названия");
    let state = if track.artists.is_empty() {
        "Неизвестный исполнитель".to_string()
    } else {
        pad_discord_str(&track.artists, "Исполнитель")
    };

    let mut activity = json!({
        // 2 = Listening ("Слушает ...")
        "type": 2,
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

    let mut assets = json!({});
    if let Some(cover) = &track.cover_url {
        assets["large_image"] = Value::String(cover.clone());
    }
    if !track.album_title.is_empty() {
        assets["large_text"] = Value::String(pad_discord_str(&track.album_title, "Альбом"));
    }
    if status == Status::Paused {
        assets["small_text"] = Value::String("На паузе".into());
    }
    if assets.as_object().is_some_and(|o| !o.is_empty()) {
        activity["assets"] = assets;
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

/// Discord отклоняет строки короче 2 символов или длиннее 128 символов.
fn pad_discord_str(s: &str, fallback: &str) -> String {
    let trimmed = s.trim();
    if trimmed.is_empty() {
        return fallback.to_string();
    }
    let count = trimmed.chars().count();
    if count < 2 {
        format!("{trimmed} ")
    } else if count > 128 {
        let mut out: String = trimmed.chars().take(127).collect();
        out.push('…');
        out
    } else {
        trimmed.to_string()
    }
}

fn connect(client_id: &str) -> Option<UnixStream> {
    for path in socket_candidates() {
        let Ok(mut stream) = UnixStream::connect(&path) else {
            continue;
        };
        let _ = stream.set_read_timeout(Some(Duration::from_secs(2)));
        let _ = stream.set_write_timeout(Some(Duration::from_secs(2)));
        let handshake = json!({
            "v": 1,
            "client_id": client_id,
        });
        if write_frame(&mut stream, OP_HANDSHAKE, &handshake).is_ok()
            && read_frame(&mut stream).is_ok()
        {
            return Some(stream);
        }
    }
    None
}

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

fn send_activity(stream: &mut UnixStream, activity: Option<Value>, nonce: &mut u64) -> io::Result<()> {
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
    let _ = read_frame(stream)?;
    Ok(())
}

fn write_frame(stream: &mut UnixStream, opcode: u32, payload: &Value) -> io::Result<()> {
    let data = serde_json::to_vec(payload).map_err(io::Error::other)?;
    let mut header = [0u8; 8];
    header[..4].copy_from_slice(&opcode.to_le_bytes());
    header[4..].copy_from_slice(&(data.len() as u32).to_le_bytes());
    stream.write_all(&header)?;
    stream.write_all(&data)?;
    stream.flush()
}

fn read_frame(stream: &mut UnixStream) -> io::Result<(u32, Vec<u8>)> {
    loop {
        let mut header = [0u8; 8];
        stream.read_exact(&mut header)?;
        let opcode = u32::from_le_bytes([header[0], header[1], header[2], header[3]]);
        let len = u32::from_le_bytes([header[4], header[5], header[6], header[7]]) as usize;
        if len > 1024 * 1024 {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "frame too large"));
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
                return Err(io::Error::new(io::ErrorKind::ConnectionAborted, "discord closed ipc"));
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
