use std::fs::{self, File};
use std::io::{self, Read, Seek, SeekFrom};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};

use anyhow::{Context, Result};
use reqwest::Client;
use serde::Serialize;
use serde::de::DeserializeOwned;

/// Порог предбуферизации перед стартом декодера (~96 КБ ≈ 2.4 сек при 320 kbps).
const PREBUFFER_BYTES: usize = 96 * 1024;
/// Лимит дискового кэша аудио (1 ГБ).
const MAX_CACHE_BYTES: u64 = 1024 * 1024 * 1024;

fn cache_root() -> Option<PathBuf> {
    dirs::cache_dir().map(|d| d.join("ymusic"))
}

pub fn track_path(track_id: &str) -> Option<PathBuf> {
    let safe: String = track_id
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '_' || c == '-' { c } else { '_' })
        .collect();
    cache_root().map(|d| d.join("tracks").join(format!("{safe}.mp3")))
}

fn cover_path(url: &str) -> Option<PathBuf> {
    let hash = md5::compute(url.as_bytes());
    cache_root().map(|d| d.join("covers").join(format!("{hash:x}.img")))
}

fn view_cache_path(key: &str) -> Option<PathBuf> {
    let hash = md5::compute(key.as_bytes());
    cache_root().map(|d| d.join("views").join(format!("{hash:x}.json")))
}

pub fn save_view<T: Serialize>(key: &str, value: &T) {
    let Some(path) = view_cache_path(key) else { return };
    let Some(dir) = path.parent() else { return };
    if fs::create_dir_all(dir).is_err() {
        return;
    }
    if let Ok(bytes) = serde_json::to_vec(value) {
        let _ = fs::write(path, bytes);
    }
}

pub fn load_view<T: DeserializeOwned>(key: &str) -> Option<T> {
    let path = view_cache_path(key)?;
    let bytes = fs::read(path).ok()?;
    serde_json::from_slice(&bytes).ok()
}

pub fn read_cached_cover(url: &str) -> Option<Vec<u8>> {
    let path = cover_path(url)?;
    let bytes = fs::read(path).ok()?;
    (!bytes.is_empty()).then_some(bytes)
}

/// Если трек уже закэширован на диске — возвращает открытый файл и его длину.
pub fn open_cached_track(track_id: &str) -> Option<(File, u64)> {
    let path = track_path(track_id)?;
    let file = File::open(&path).ok()?;
    let len = file.metadata().ok()?.len();
    if len > 1024 {
        Some((file, len))
    } else {
        let _ = fs::remove_file(path);
        None
    }
}

pub fn is_track_cached(track_id: &str) -> bool {
    track_path(track_id)
        .and_then(|p| fs::metadata(p).ok())
        .is_some_and(|m| m.len() > 1024)
}

pub fn save_track(track_id: &str, bytes: &[u8]) {
    let Some(path) = track_path(track_id) else { return };
    let Some(dir) = path.parent() else { return };
    if fs::create_dir_all(dir).is_err() {
        return;
    }
    // Уникальное имя: стрим и предзагрузка могут сохранять один трек одновременно
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let tmp = path.with_extension(format!(
        "{}-{}.part",
        std::process::id(),
        SEQ.fetch_add(1, Ordering::Relaxed)
    ));
    if fs::write(&tmp, bytes).is_ok() {
        let _ = fs::rename(&tmp, &path);
        trim_cache(dir);
    }
}

pub async fn fetch_cover(http: &Client, url: &str) -> Result<Vec<u8>> {
    if let Some(path) = cover_path(url)
        && let Ok(bytes) = fs::read(&path)
        && !bytes.is_empty()
    {
        return Ok(bytes);
    }
    let bytes = http
        .get(url)
        .send()
        .await?
        .error_for_status()?
        .bytes()
        .await?
        .to_vec();
    if let Some(path) = cover_path(url)
        && let Some(dir) = path.parent()
        && fs::create_dir_all(dir).is_ok()
    {
        let _ = fs::write(path, &bytes);
    }
    Ok(bytes)
}

fn trim_cache(dir: & std::path::Path) {
    let Ok(entries) = fs::read_dir(dir) else { return };
    let mut files = Vec::new();
    let mut total = 0u64;
    for entry in entries.flatten() {
        let Ok(meta) = entry.metadata() else { continue };
        if !meta.is_file() || entry.path().extension().is_some_and(|e| e == "part") {
            continue;
        }
        let len = meta.len();
        let mtime = meta.modified().ok();
        total += len;
        files.push((entry.path(), len, mtime));
    }
    if total <= MAX_CACHE_BYTES {
        return;
    }
    files.sort_by_key(|(_, _, mtime)| *mtime);
    for (path, len, _) in files {
        if total <= MAX_CACHE_BYTES * 8 / 10 {
            break;
        }
        if fs::remove_file(path).is_ok() {
            total = total.saturating_sub(len);
        }
    }
}

struct StreamState {
    buf: Vec<u8>,
    total_len: Option<u64>,
    done: bool,
    error: Option<String>,
    /// Читатель больше не нужен (трек сменили): не блокировать аудиопоток ожиданием сети.
    cancelled: bool,
}

pub struct SharedStream {
    state: Mutex<StreamState>,
    cvar: Condvar,
}

#[derive(Clone)]
pub struct StreamReader {
    shared: Arc<SharedStream>,
    pos: u64,
}

impl StreamReader {
    pub fn byte_len(&self) -> Option<u64> {
        self.shared.state.lock().unwrap().total_len
    }

    /// Прерывает ожидание данных. Фоновая загрузка продолжается и сохранит трек в кэш.
    pub fn cancel(&self) {
        self.shared.state.lock().unwrap().cancelled = true;
        self.shared.cvar.notify_all();
    }
}

impl Read for StreamReader {
    fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
        if out.is_empty() {
            return Ok(0);
        }
        let mut st = self.shared.state.lock().unwrap();
        loop {
            let pos = self.pos as usize;
            if pos < st.buf.len() {
                let avail = &st.buf[pos..];
                let n = avail.len().min(out.len());
                out[..n].copy_from_slice(&avail[..n]);
                self.pos += n as u64;
                return Ok(n);
            }
            if let Some(err) = &st.error {
                return Err(io::Error::other(err.clone()));
            }
            if st.done || st.cancelled {
                return Ok(0);
            }
            st = self.shared.cvar.wait(st).unwrap();
        }
    }
}

impl Seek for StreamReader {
    fn seek(&mut self, pos: SeekFrom) -> io::Result<u64> {
        let mut st = self.shared.state.lock().unwrap();
        let target: i64 = match pos {
            SeekFrom::Start(offset) => offset as i64,
            SeekFrom::Current(delta) => self.pos as i64 + delta,
            SeekFrom::End(delta) => {
                let end = loop {
                    if let Some(len) = st.total_len {
                        break len;
                    }
                    if st.done || st.cancelled {
                        break st.buf.len() as u64;
                    }
                    if let Some(err) = &st.error {
                        return Err(io::Error::other(err.clone()));
                    }
                    st = self.shared.cvar.wait(st).unwrap();
                };
                end as i64 + delta
            }
        };
        if target < 0 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "seek before start",
            ));
        }
        let target = target as u64;
        // Дожидаемся, пока буфер докачается хотя бы до целевой позиции (или поток завершится)
        while (st.buf.len() as u64) < target && !st.done && !st.cancelled && st.error.is_none() {
            st = self.shared.cvar.wait(st).unwrap();
        }
        self.pos = target;
        Ok(self.pos)
    }
}

/// Начинает потоковую загрузку `url`, дожидается первых `PREBUFFER_BYTES`
/// и возвращает `StreamReader`, пока остаток файла докачивается в фоне и пишется в кэш.
pub async fn stream_track(http: Client, url: String, track_id: String) -> Result<StreamReader> {
    let mut resp = http
        .get(&url)
        .send()
        .await
        .context("ошибка соединения при загрузке аудио")?
        .error_for_status()
        .context("сервер вернул ошибку при загрузке аудио")?;

    let total_len = resp.content_length();
    let capacity = total_len.unwrap_or(8 * 1024 * 1024) as usize;
    let mut initial = Vec::with_capacity(capacity.min(32 * 1024 * 1024));

    while initial.len() < PREBUFFER_BYTES {
        match resp.chunk().await? {
            Some(chunk) => initial.extend_from_slice(&chunk),
            None => break,
        }
    }

    let is_complete = total_len.is_some_and(|len| initial.len() as u64 >= len);
    if is_complete {
        save_track(&track_id, &initial);
    }

    let shared = Arc::new(SharedStream {
        state: Mutex::new(StreamState {
            buf: initial,
            total_len,
            done: is_complete,
            error: None,
            cancelled: false,
        }),
        cvar: Condvar::new(),
    });

    if !is_complete {
        let shared_bg = shared.clone();
        tokio::spawn(async move {
            loop {
                match resp.chunk().await {
                    Ok(Some(chunk)) => {
                        let mut st = shared_bg.state.lock().unwrap();
                        st.buf.extend_from_slice(&chunk);
                        shared_bg.cvar.notify_all();
                    }
                    Ok(None) => {
                        {
                            let mut st = shared_bg.state.lock().unwrap();
                            st.done = true;
                            st.total_len = Some(st.buf.len() as u64);
                        }
                        shared_bg.cvar.notify_all();
                        // После done буфер больше не меняется, но копируем без удержания
                        // блокировки, чтобы не тормозить аудиопоток на мегабайтах.
                        let bytes = {
                            let st = shared_bg.state.lock().unwrap();
                            Arc::new(st.buf.clone())
                        };
                        tokio::task::spawn_blocking(move || save_track(&track_id, &bytes[..]));
                        break;
                    }
                    Err(e) => {
                        let mut st = shared_bg.state.lock().unwrap();
                        st.error = Some(e.to_string());
                        st.done = true;
                        shared_bg.cvar.notify_all();
                        break;
                    }
                }
            }
        });
    }

    Ok(StreamReader { shared, pos: 0 })
}
