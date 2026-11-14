use std::fs;
use std::io;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::api::Track;

fn token_path() -> Option<PathBuf> {
    dirs::config_dir().map(|d| d.join("ymusic").join("token"))
}

pub fn load_token() -> Option<String> {
    if let Ok(token) = std::env::var("YM_TOKEN")
        && !token.trim().is_empty()
    {
        return Some(token.trim().to_string());
    }
    let token = fs::read_to_string(token_path()?).ok()?;
    let token = token.trim();
    (!token.is_empty()).then(|| token.to_string())
}

pub fn save_token(token: &str) -> io::Result<()> {
    let path = token_path().ok_or_else(|| io::Error::other("нет каталога конфигурации"))?;
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    fs::write(&path, token)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600))?;
    }
    Ok(())
}

pub fn clear_token() {
    if let Some(path) = token_path() {
        let _ = fs::remove_file(path);
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SavedWaveState {
    pub seed: String,
    pub title: String,
    pub session_id: String,
    pub batch_id: String,
    pub tracks: Vec<Track>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SavedSession {
    pub queue: Vec<Track>,
    pub current_index: usize,
    pub position_secs: f64,
    pub wave: Option<SavedWaveState>,
    #[serde(default)]
    pub unshuffled_queue: Option<Vec<Track>>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PinnedPlaylist {
    pub uid: u64,
    pub kind: u64,
    pub title: String,
    #[serde(default)]
    pub cover_uri: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct UserSettings {
    #[serde(default = "default_volume")]
    pub volume: f32,
    #[serde(default)]
    pub session: Option<SavedSession>,
    #[serde(default)]
    pub user_avatar_url: Option<String>,
    #[serde(default)]
    pub repeat_mode: u8,
    #[serde(default)]
    pub shuffle: bool,
    #[serde(default)]
    pub pinned_playlists: Vec<PinnedPlaylist>,
}

fn default_volume() -> f32 {
    0.7
}

impl Default for UserSettings {
    fn default() -> Self {
        Self {
            volume: default_volume(),
            session: None,
            user_avatar_url: None,
            repeat_mode: 0,
            shuffle: false,
            pinned_playlists: Vec::new(),
        }
    }
}

fn settings_path() -> Option<PathBuf> {
    dirs::config_dir().map(|d| d.join("ymusic").join("settings.json"))
}

pub fn load_settings_from(path: &std::path::Path) -> UserSettings {
    let Ok(data) = fs::read_to_string(path) else { return UserSettings::default() };
    serde_json::from_str(&data).unwrap_or_default()
}

pub fn load_settings() -> UserSettings {
    let Some(path) = settings_path() else { return UserSettings::default() };
    load_settings_from(&path)
}

pub fn save_settings_to(path: &std::path::Path, settings: &UserSettings) -> io::Result<()> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    let data = serde_json::to_string_pretty(settings)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    // Пишем во временный файл и переименовываем, чтобы прерванная запись не испортила настройки.
    let tmp = path.with_extension("json.tmp");
    fs::write(&tmp, data)?;
    fs::rename(tmp, path)
}

pub fn save_settings(settings: &UserSettings) -> io::Result<()> {
    let path = settings_path().ok_or_else(|| io::Error::other("нет каталога конфигурации"))?;
    save_settings_to(&path, settings)
}

/// Атомарное чтение-изменение-запись: параллельные сохранения не затирают друг друга.
#[allow(dead_code)]
pub fn update_settings(f: impl FnOnce(&mut UserSettings)) {
    static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
    let _guard = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut settings = load_settings();
    f(&mut settings);
    let _ = save_settings(&settings);
}
