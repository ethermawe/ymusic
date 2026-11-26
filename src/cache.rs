use std::fs::{self, File};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use parking_lot::{Condvar, Mutex};

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

fn safe_track_id(track_id: &str) -> String {
    track_id
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '_' || c == '-' { c } else { '_' })
        .collect()
}

pub fn track_path(track_id: &str) -> Option<PathBuf> {
    let safe = safe_track_id(track_id);
    cache_root().map(|d| d.join("tracks").join(format!("{safe}.mp3")))
}

fn offline_root() -> Option<PathBuf> {
    dirs::data_local_dir().map(|d| d.join("ymusic").join("offline"))
}

pub fn offline_bundle_dir(track_id: &str) -> Option<PathBuf> {
    let safe = safe_track_id(track_id);
    if safe.is_empty() {
        return None;
    }
    offline_root().map(|d| d.join(safe))
}

fn legacy_offline_track_path(track_id: &str) -> Option<PathBuf> {
    let name = format!("{:x}.mp3", md5::compute(track_id.as_bytes()));
    offline_root().map(|d| d.join(name))
}

/// Explicit offline downloads live in structured per-track bundle directories:
/// `~/.local/share/ymusic/offline/<track_id>/{audio.mp3, metadata.json, cover.jpg}`.
pub fn offline_track_path(track_id: &str) -> Option<PathBuf> {
    offline_bundle_dir(track_id).map(|d| d.join("audio.mp3"))
}

pub fn offline_metadata_path(track_id: &str) -> Option<PathBuf> {
    offline_bundle_dir(track_id).map(|d| d.join("metadata.json"))
}

pub fn offline_cover_path(track_id: &str) -> Option<PathBuf> {
    offline_bundle_dir(track_id).map(|d| d.join("cover.jpg"))
}

pub fn offline_cover_url(track_id: &str) -> Option<String> {
    let path = offline_cover_path(track_id)?;
    let meta = fs::metadata(&path).ok()?;
    if meta.is_file() && meta.len() > 128 {
        Some(format!("file://{}", path.to_string_lossy()))
    } else {
        None
    }
}

pub fn is_offline(track_id: &str) -> bool {
    offline_track_path(track_id)
        .and_then(|p| fs::metadata(p).ok())
        .is_some_and(|m| m.len() > 1024)
        || legacy_offline_track_path(track_id)
            .and_then(|p| fs::metadata(p).ok())
            .is_some_and(|m| m.len() > 1024)
}

/// Автоматически мигрирует старые плоские файлы `<md5>.mp3` + `<md5>.json` в пакеты `<track_id>/`.
pub fn migrate_legacy_offline_files() {
    let Some(root) = offline_root() else { return };
    let Ok(entries) = fs::read_dir(&root) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_file() || path.extension().is_none_or(|ext| ext != "json") {
            continue;
        }
        let Ok(data) = fs::read(&path) else { continue };
        let Ok(track) = serde_json::from_slice::<crate::api::Track>(&data) else { continue };
        let legacy_mp3 = path.with_extension("mp3");
        let Some(bundle_dir) = offline_bundle_dir(&track.id) else { continue };
        if fs::create_dir_all(&bundle_dir).is_err() {
            continue;
        }
        let target_audio = bundle_dir.join("audio.mp3");
        let target_meta = bundle_dir.join("metadata.json");
        if legacy_mp3.is_file() && !target_audio.exists() {
            let _ = fs::rename(&legacy_mp3, &target_audio);
        } else if legacy_mp3.is_file() && target_audio.exists() {
            let _ = fs::remove_file(&legacy_mp3);
        }
        if !target_meta.exists() {
            let _ = fs::rename(&path, &target_meta);
        } else {
            let _ = fs::remove_file(&path);
        }
    }
}

pub fn save_offline_metadata(track: &crate::api::Track) -> Result<()> {
    let path = offline_metadata_path(&track.id).ok_or_else(|| anyhow::anyhow!("нет каталога данных"))?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let tmp = path.with_extension(format!("{}-{}.json.tmp", std::process::id(), SEQ.fetch_add(1, Ordering::Relaxed)));
    fs::write(&tmp, serde_json::to_vec_pretty(track)?)?;
    fs::rename(tmp, path)?;
    Ok(())
}

pub async fn download_offline_cover(http: &Client, track: &crate::api::Track) {
    let Some(cover_dest) = offline_cover_path(&track.id) else { return };
    if fs::metadata(&cover_dest).is_ok_and(|m| m.is_file() && m.len() > 128) {
        return;
    }
    let Some(url) = track.cover_url(400) else { return };
    if let Some(parent) = cover_dest.parent() {
        let _ = tokio::fs::create_dir_all(parent).await;
    }
    if let Ok(bytes) = fetch_cover(http, &url).await
        && bytes.len() > 128
    {
        let tmp = cover_dest.with_extension("jpg.tmp");
        if tokio::fs::write(&tmp, &bytes).await.is_ok() {
            let _ = tokio::fs::rename(&tmp, &cover_dest).await;
        }
    }
}

pub fn offline_tracks() -> Result<(Vec<crate::api::Track>, u64)> {
    migrate_legacy_offline_files();
    let dir = offline_root().ok_or_else(|| anyhow::anyhow!("нет каталога данных"))?;
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok((Vec::new(), 0)),
        Err(e) => return Err(e.into()),
    };
    let mut tracks = Vec::new();
    let mut size = 0;
    for entry in entries.flatten() {
        let entry_path = entry.path();
        if entry_path.is_dir() {
            let meta_path = entry_path.join("metadata.json");
            let audio_path = entry_path.join("audio.mp3");
            let Ok(data) = fs::read(&meta_path) else { continue };
            let Ok(mut track) = serde_json::from_slice::<crate::api::Track>(&data) else { continue };
            let Ok(meta) = fs::metadata(&audio_path) else { continue };
            if meta.len() <= 1024 { continue; }
            size += meta.len();
            track.available = true;
            tracks.push(track);
        }
    }
    tracks.sort_by(|a, b| a.artists.cmp(&b.artists).then(a.title.cmp(&b.title)));
    Ok((tracks, size))
}

/// Older downloads have audio only. Recover their metadata from cached lists.
pub fn recover_offline_metadata(known: &[crate::api::Track]) {
    migrate_legacy_offline_files();
    fn recover(track: &crate::api::Track) {
        if let Some(legacy_mp3) = legacy_offline_track_path(&track.id)
            && legacy_mp3.is_file()
            && let Some(new_audio) = offline_track_path(&track.id)
        {
            if let Some(parent) = new_audio.parent() {
                let _ = fs::create_dir_all(parent);
            }
            if !new_audio.exists() {
                let _ = fs::rename(&legacy_mp3, &new_audio);
            }
        }
        if is_offline(&track.id)
            && offline_metadata_path(&track.id).is_some_and(|p| !p.exists())
        {
            let _ = save_offline_metadata(track);
        }
    }
    for track in known { recover(track); }
    let Some(dir) = cache_root().map(|p| p.join("views")) else { return };
    let Ok(entries) = fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let Ok(bytes) = fs::read(entry.path()) else { continue };
        let Ok(view) = serde_json::from_slice::<serde_json::Value>(&bytes) else { continue };
        if let Some(tracks) = view.get("tracks").and_then(|v| v.as_array()) {
            for value in tracks {
                if let Ok(track) = serde_json::from_value::<crate::api::Track>(value.clone()) { recover(&track); }
            }
        }
    }
}

pub fn remove_offline(track_id: &str) -> Result<()> {
    if let Some(bundle_dir) = offline_bundle_dir(track_id)
        && bundle_dir.exists()
    {
        let _ = fs::remove_dir_all(&bundle_dir);
    }
    if let Some(legacy_path) = legacy_offline_track_path(track_id) {
        let _ = fs::remove_file(&legacy_path);
        let _ = fs::remove_file(legacy_path.with_extension("json"));
    }
    Ok(())
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

pub fn remove_view(key: &str) {
    if let Some(path) = view_cache_path(key) { let _ = fs::remove_file(path); }
}

pub fn read_cached_cover(url: &str) -> Option<Vec<u8>> {
    let path = cover_path(url)?;
    let bytes = fs::read(path).ok()?;
    (!bytes.is_empty()).then_some(bytes)
}

/// Возвращает локальный `file://` URL обложки (из офлайн-пакета трека или дискового кэша обложек),
/// либо исходный сетевой URL.
pub fn resolve_track_cover_url(track: &crate::api::Track, size: u32) -> String {
    if let Some(local) = offline_cover_url(&track.id) {
        return local;
    }
    if let Some(url400) = track.cover_url(400)
        && let Some(path) = cover_path(&url400)
        && fs::metadata(&path).is_ok_and(|m| m.is_file() && m.len() > 128)
    {
        return format!("file://{}", path.to_string_lossy());
    }
    if let Some(url) = track.cover_url(size) {
        if let Some(path) = cover_path(&url)
            && fs::metadata(&path).is_ok_and(|m| m.is_file() && m.len() > 128)
        {
            return format!("file://{}", path.to_string_lossy());
        }
        return url;
    }
    String::new()
}

/// Если трек уже закэширован на диске — возвращает открытый файл и его длину.
pub fn open_cached_track(track_id: &str) -> Option<(File, u64)> {
    if let Some(path) = offline_track_path(track_id)
        && let Ok(file) = File::open(path)
        && let Ok(meta) = file.metadata()
        && meta.len() > 1024
    {
        return Some((file, meta.len()));
    }
    if let Some(path) = legacy_offline_track_path(track_id)
        && let Ok(file) = File::open(path)
        && let Ok(meta) = file.metadata()
        && meta.len() > 1024
    {
        return Some((file, meta.len()));
    }
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
    is_offline(track_id)
        || track_path(track_id)
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

/// Stream to a sibling file using bounded buffers; publish only a complete file.
pub async fn download_to_file(http: &Client, url: &str, path: &std::path::Path) -> Result<()> {
    use tokio::io::AsyncWriteExt;
    const LIMIT: u64 = 128 * 1024 * 1024;
    let mut response = http.get(url).send().await?.error_for_status()?;
    let expected = response.content_length();
    anyhow::ensure!(expected.is_none_or(|n| n <= LIMIT), "файл превышает 128 МБ");
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let tmp = path.with_extension(format!("{}-{}.part", std::process::id(), SEQ.fetch_add(1, Ordering::Relaxed)));
    // Also remove an unfinished download if its async task is cancelled.
    struct PartialFile(PathBuf);
    impl Drop for PartialFile {
        fn drop(&mut self) { let _ = fs::remove_file(&self.0); }
    }
    let _partial = PartialFile(tmp.clone());
    let mut file = tokio::fs::OpenOptions::new().write(true).create_new(true).open(&tmp).await?;
    let mut received = 0u64;
    while let Some(chunk) = response.chunk().await? {
        received += chunk.len() as u64;
        anyhow::ensure!(received <= LIMIT, "файл превышает 128 МБ");
        file.write_all(&chunk).await?;
    }
    anyhow::ensure!(received > 1024, "сервер вернул пустой аудиофайл");
    anyhow::ensure!(expected.is_none_or(|n| n == received), "аудиофайл загружен не полностью");
    file.flush().await?;
    file.sync_all().await?;
    drop(file);
    tokio::fs::rename(&tmp, path).await?;
    Ok(())
}

pub fn trim_track_cache() {
    if let Some(dir) = cache_root().map(|p| p.join("tracks")) { trim_cache(&dir); }
}

pub fn clear_track_cache() {
    let Some(dir) = cache_root().map(|p| p.join("tracks")) else { return };
    if let Ok(rd) = fs::read_dir(&dir) {
        for entry in rd.flatten() {
            let _ = fs::remove_file(entry.path());
        }
    }
}

#[cfg(test)]
mod download_tests {
    use super::*;

    #[test]
    fn offline_metadata_round_trip_and_removal() {
        let id = format!("offline-test-{}", std::process::id());
        let track = crate::api::Track {
            id: id.clone(), title: "Offline test".into(), artists: "Test artist".into(),
            album_id: None, album_title: String::new(), artist_id: None, artist_links: Vec::new(),
            duration_ms: 1000, cover_uri: None, available: false,
            has_sync_lyrics: false, has_text_lyrics: false, r128_i: None, r128_tp: None, is_ai: false,
        };
        let path = offline_track_path(&id).unwrap();
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(&path, vec![42; 2048]).unwrap();
        save_offline_metadata(&track).unwrap();
        let (tracks, size) = offline_tracks().unwrap();
        let loaded = tracks.iter().find(|t| t.id == id).unwrap();
        assert_eq!(loaded.title, "Offline test");
        assert!(loaded.available);
        assert!(size >= 2048);
        assert!(is_offline(&id));
        assert_eq!(open_cached_track(&id).unwrap().1, 2048);
        remove_offline(&id).unwrap();
        assert!(!is_offline(&id));
        assert!(!path.with_extension("json").exists());
        assert!(!offline_tracks().unwrap().0.iter().any(|t| t.id == id));
    }

    fn run_response(body: Vec<u8>, declared: usize) -> (Result<()>, PathBuf) {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}/audio", listener.local_addr().unwrap());
        let server = std::thread::spawn(move || {
            let (mut socket, _) = listener.accept().unwrap();
            let mut request = [0; 4096];
            let _ = socket.read(&mut request);
            write!(socket, "HTTP/1.1 200 OK\r\nContent-Length: {declared}\r\nConnection: close\r\n\r\n").unwrap();
            socket.write_all(&body).unwrap();
        });
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let dir = std::env::temp_dir().join(format!("ymusic-download-test-{}-{}", std::process::id(), SEQ.fetch_add(1, Ordering::Relaxed)));
        fs::create_dir_all(&dir).unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
        let client = Client::builder().no_proxy().build().unwrap();
        let result = runtime.block_on(download_to_file(&client, &url, &dir.join("track.mp3")));
        server.join().unwrap();
        (result, dir)
    }

    #[test]
    fn publishes_complete_download() {
        let bytes = vec![42; 65536];
        let (result, dir) = run_response(bytes.clone(), bytes.len());
        result.unwrap();
        assert_eq!(fs::read(dir.join("track.mp3")).unwrap(), bytes);
        assert_eq!(fs::read_dir(&dir).unwrap().count(), 1);
        fs::remove_file(dir.join("track.mp3")).unwrap();
        fs::remove_dir(dir).unwrap();
    }

    #[test]
    fn rejects_partial_download_and_removes_temporary_file() {
        let (result, dir) = run_response(vec![42; 2048], 4096);
        assert!(result.is_err());
        assert_eq!(fs::read_dir(&dir).unwrap().count(), 0);
        fs::remove_dir(dir).unwrap();
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
        self.shared.state.lock().total_len
    }

    /// Прерывает ожидание данных. Фоновая загрузка продолжается и сохранит трек в кэш.
    pub fn cancel(&self) {
        self.shared.state.lock().cancelled = true;
        self.shared.cvar.notify_all();
    }
}

impl Read for StreamReader {
    fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
        if out.is_empty() {
            return Ok(0);
        }
        let mut st = self.shared.state.lock();
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
            self.shared.cvar.wait(&mut st);
        }
    }
}

impl Seek for StreamReader {
    fn seek(&mut self, pos: SeekFrom) -> io::Result<u64> {
        let mut st = self.shared.state.lock();
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
                    self.shared.cvar.wait(&mut st);
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
            self.shared.cvar.wait(&mut st);
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
    // Начинаем с компактного буфера под предзагрузку, не аллоцируя весь трек заранее
    let mut initial = Vec::with_capacity(PREBUFFER_BYTES * 2);

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
        let http_bg = http.clone();
        let url_bg = url.clone();
        // Подготавливаем временный файл для постепенной записи трека на диск без дублирования буфера в RAM
        let mut disk_cache_file = track_path(&track_id).and_then(|path| {
            let dir = path.parent()?;
            fs::create_dir_all(dir).ok()?;
            static SEQ: AtomicU64 = AtomicU64::new(0);
            let tmp = path.with_extension(format!(
                "{}-{}.part",
                std::process::id(),
                SEQ.fetch_add(1, Ordering::Relaxed)
            ));
            let mut f = File::create(&tmp).ok()?;
            let st = shared_bg.state.lock();
            if !st.buf.is_empty() {
                f.write_all(&st.buf).ok()?;
            }
            Some((tmp, path, f))
        });

        tokio::spawn(async move {
            let mut retries_left: u8 = 3;
            loop {
                let resume_from: Option<(u64, String)> = match resp.chunk().await {
                    Ok(Some(chunk)) => {
                        let mut st = shared_bg.state.lock();
                        if st.cancelled {
                            if let Some((tmp, _, f)) = disk_cache_file.take() {
                                drop(f);
                                let _ = fs::remove_file(&tmp);
                            }
                            break;
                        }
                        st.buf.extend_from_slice(&chunk);
                        shared_bg.cvar.notify_all();
                        if let Some((_, _, ref mut f)) = disk_cache_file {
                            let _ = f.write_all(&chunk);
                        }
                        None
                    }
                    Ok(None) => {
                        let (downloaded, expected, cancelled) = {
                            let st = shared_bg.state.lock();
                            (st.buf.len() as u64, st.total_len, st.cancelled)
                        };
                        if cancelled {
                            if let Some((tmp, _, f)) = disk_cache_file.take() {
                                drop(f);
                                let _ = fs::remove_file(&tmp);
                            }
                            break;
                        }
                        if expected.is_some_and(|len| downloaded < len) && retries_left > 0 {
                            Some((
                                downloaded,
                                format!("преждевременный обрыв потока на {downloaded} байт"),
                            ))
                        } else {
                            {
                                let mut st = shared_bg.state.lock();
                                st.done = true;
                                st.total_len = Some(downloaded);
                            }
                            shared_bg.cvar.notify_all();
                            if let Some((tmp, path, mut f)) = disk_cache_file.take() {
                                let _ = f.flush();
                                drop(f);
                                if fs::rename(&tmp, &path).is_ok() {
                                    if let Some(dir) = path.parent() {
                                        trim_cache(dir);
                                    }
                                }
                            }
                            break;
                        }
                    }
                    Err(e) => {
                        let (downloaded, cancelled) = {
                            let st = shared_bg.state.lock();
                            (st.buf.len() as u64, st.cancelled)
                        };
                        if cancelled {
                            if let Some((tmp, _, f)) = disk_cache_file.take() {
                                drop(f);
                                let _ = fs::remove_file(&tmp);
                            }
                            break;
                        }
                        Some((downloaded, e.to_string()))
                    }
                };

                if let Some((offset, reason)) = resume_from {
                    let mut resumed = None;
                    while retries_left > 0 {
                        retries_left -= 1;
                        tokio::time::sleep(std::time::Duration::from_millis(250)).await;
                        if shared_bg.state.lock().cancelled {
                            break;
                        }
                        if let Ok(r) = http_bg
                            .get(&url_bg)
                            .header(reqwest::header::RANGE, format!("bytes={offset}-"))
                            .send()
                            .await
                        {
                            if r.status() == reqwest::StatusCode::PARTIAL_CONTENT {
                                resumed = Some(r);
                                break;
                            }
                        }
                    }
                    if let Some(new_resp) = resumed {
                        resp = new_resp;
                        continue;
                    }
                    let mut st = shared_bg.state.lock();
                    st.error = Some(reason);
                    st.done = true;
                    shared_bg.cvar.notify_all();
                    if let Some((tmp, _, f)) = disk_cache_file.take() {
                        drop(f);
                        let _ = fs::remove_file(&tmp);
                    }
                    break;
                }
            }
        });
    }

    Ok(StreamReader { shared, pos: 0 })
}
