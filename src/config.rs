use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::api::Track;

#[derive(Debug, Error)]
pub enum KeyringError {
    #[error("системное хранилище ключей недоступно: {0}")]
    Unavailable(String),
    #[error("не удалось записать секрет в системное хранилище: {0}")]
    WriteFailed(String),
    #[error("платформа не поддерживает системное хранилище ключей")]
    UnsupportedPlatform,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TokenSaveOutcome {
    Keyring,
    FileFallback { reason: String },
}

const KEYRING_SERVICE: &str = "ymusic";

#[derive(Clone, Copy)]
struct SecretSlot {
    user: &'static str,
    #[cfg(target_os = "linux")]
    label: &'static str,
    #[cfg(target_os = "windows")]
    win_target: &'static str,
    legacy_file: &'static str,
}

const YANDEX_TOKEN_SLOT: SecretSlot = SecretSlot {
    user: "oauth-token",
    #[cfg(target_os = "linux")]
    label: "Yandex Music OAuth token",
    #[cfg(target_os = "windows")]
    win_target: "ymusic/oauth-token",
    legacy_file: "token",
};

const LASTFM_SESSION_SLOT: SecretSlot = SecretSlot {
    user: "lastfm-session",
    #[cfg(target_os = "linux")]
    label: "Last.fm session key",
    #[cfg(target_os = "windows")]
    win_target: "ymusic/lastfm-session",
    legacy_file: "lastfm_session",
};

#[cfg(target_os = "windows")]
const WIN_CRED_USER: &str = "ymusic";

#[derive(Debug, PartialEq, Eq)]
enum KeyringRead {
    Found(String),
    Missing,
    Unavailable,
}

trait KeyringBackend {
    fn read(&self) -> KeyringRead;
    fn write(&self, token: &str) -> Result<(), KeyringError>;
    fn delete(&self);
}

struct PlatformKeyring(SecretSlot);

#[cfg(target_os = "linux")]
mod linux_keyring {
    use std::collections::HashMap;
    use std::sync::Arc;

    use keyring_core::{Entry, Error};
    use zbus_secret_service_keyring_store::Store;

    use super::{KEYRING_SERVICE, KeyringError, KeyringRead, SecretSlot};

    fn entry(slot: SecretSlot) -> Result<Entry, KeyringError> {
        let store: Arc<Store> = Store::new()
            .map_err(|e| KeyringError::Unavailable(e.to_string()))?;
        let mods = HashMap::from([("label", slot.label)]);
        keyring_core::api::CredentialStoreApi::build(
            store.as_ref(),
            KEYRING_SERVICE,
            slot.user,
            Some(&mods),
        )
        .map_err(|e| KeyringError::Unavailable(e.to_string()))
    }

    pub(super) fn read(slot: SecretSlot) -> KeyringRead {
        let entry = match entry(slot) {
            Ok(e) => e,
            Err(err) => {
                eprintln!("[ymusic::config] keyring read ({}): {err}", slot.user);
                return KeyringRead::Unavailable;
            }
        };
        match entry.get_password() {
            Ok(token) => {
                let trimmed = token.trim();
                if trimmed.is_empty() {
                    KeyringRead::Missing
                } else {
                    KeyringRead::Found(trimmed.to_string())
                }
            }
            Err(Error::NoEntry) => KeyringRead::Missing,
            Err(Error::Ambiguous(entries)) => {
                for candidate in entries {
                    if let Ok(token) = candidate.get_password() {
                        let trimmed = token.trim();
                        if !trimmed.is_empty() {
                            return KeyringRead::Found(trimmed.to_string());
                        }
                    }
                }
                KeyringRead::Unavailable
            }
            Err(err) => {
                eprintln!("[ymusic::config] keyring get_password ({}): {err}", slot.user);
                KeyringRead::Unavailable
            }
        }
    }

    pub(super) fn write(slot: SecretSlot, token: &str) -> Result<(), KeyringError> {
        let entry = entry(slot)?;
        match entry.set_password(token) {
            Ok(()) => Ok(()),
            Err(Error::Ambiguous(entries)) => {
                for duplicate in entries {
                    let _ = duplicate.delete_credential();
                }
                entry
                    .set_password(token)
                    .map_err(|e| KeyringError::WriteFailed(e.to_string()))
            }
            Err(err) => Err(KeyringError::WriteFailed(err.to_string())),
        }
    }

    pub(super) fn delete(slot: SecretSlot) {
        let Ok(entry) = entry(slot) else {
            return;
        };
        if let Err(Error::Ambiguous(entries)) = entry.delete_credential() {
            for duplicate in entries {
                let _ = duplicate.delete_credential();
            }
        }
    }
}

#[cfg(any(target_os = "windows", test))]
fn encode_utf16_le(text: &str) -> Vec<u8> {
    text.encode_utf16().flat_map(|u| u.to_le_bytes()).collect()
}

#[cfg(any(target_os = "windows", test))]
fn decode_utf16_blob(bytes: &[u8]) -> Option<String> {
    // Windows Credential Manager stores generic secrets as UTF-16LE blobs without a trailing NUL.
    if bytes.len() % 2 == 0 {
        let units: Vec<u16> = bytes
            .chunks_exact(2)
            .map(|c| u16::from_le_bytes([c[0], c[1]]))
            .collect();
        if let Ok(s) = String::from_utf16(&units) {
            return Some(s);
        }
    }
    String::from_utf8(bytes.to_vec()).ok()
}

#[cfg(target_os = "windows")]
mod windows_keyring {
    use std::ffi::c_void;
    use std::ptr;

    use windows_sys::Win32::Foundation::{ERROR_NOT_FOUND, GetLastError};
    use windows_sys::Win32::Security::Credentials::{
        CRED_PERSIST_LOCAL_MACHINE, CRED_TYPE_GENERIC, CREDENTIALW, CredDeleteW, CredFree,
        CredReadW, CredWriteW,
    };

    use super::{KeyringError, KeyringRead, SecretSlot, WIN_CRED_USER, decode_utf16_blob, encode_utf16_le};

    fn to_wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }

    struct CredGuard(*mut CREDENTIALW);
    impl Drop for CredGuard {
        fn drop(&mut self) {
            if !self.0.is_null() {
                unsafe { CredFree(self.0 as *const c_void) };
            }
        }
    }

    pub(super) fn read(slot: SecretSlot) -> KeyringRead {
        let target = to_wide(slot.win_target);
        let mut raw: *mut CREDENTIALW = ptr::null_mut();
        let ok = unsafe { CredReadW(target.as_ptr(), CRED_TYPE_GENERIC, 0, &mut raw) };
        if ok == 0 {
            let err = unsafe { GetLastError() };
            return if err == ERROR_NOT_FOUND {
                KeyringRead::Missing
            } else {
                KeyringRead::Unavailable
            };
        }
        let guard = CredGuard(raw);
        let cred = unsafe { &*guard.0 };
        if cred.CredentialBlob.is_null() || cred.CredentialBlobSize == 0 {
            return KeyringRead::Missing;
        }
        let bytes = unsafe {
            std::slice::from_raw_parts(cred.CredentialBlob, cred.CredentialBlobSize as usize)
        };
        let Some(decoded) = decode_utf16_blob(bytes) else {
            return KeyringRead::Unavailable;
        };
        let trimmed = decoded.trim();
        if trimmed.is_empty() {
            KeyringRead::Missing
        } else {
            KeyringRead::Found(trimmed.to_string())
        }
    }

    pub(super) fn write(slot: SecretSlot, token: &str) -> Result<(), KeyringError> {
        let mut target = to_wide(slot.win_target);
        let mut user = to_wide(WIN_CRED_USER);
        let mut blob = encode_utf16_le(token);
        let blob_size = u32::try_from(blob.len())
            .map_err(|_| KeyringError::WriteFailed("secret exceeds u32::MAX".into()))?;
        let cred = CREDENTIALW {
            Flags: 0,
            Type: CRED_TYPE_GENERIC,
            TargetName: target.as_mut_ptr(),
            Comment: ptr::null_mut(),
            LastWritten: Default::default(),
            CredentialBlobSize: blob_size,
            CredentialBlob: blob.as_mut_ptr(),
            Persist: CRED_PERSIST_LOCAL_MACHINE,
            AttributeCount: 0,
            Attributes: ptr::null_mut(),
            TargetAlias: ptr::null_mut(),
            UserName: user.as_mut_ptr(),
        };
        let ok = unsafe { CredWriteW(&cred, 0) };
        if ok == 0 {
            let code = unsafe { GetLastError() };
            Err(KeyringError::WriteFailed(format!("CredWriteW error {code}")))
        } else {
            Ok(())
        }
    }

    pub(super) fn delete(slot: SecretSlot) {
        let target = to_wide(slot.win_target);
        unsafe {
            CredDeleteW(target.as_ptr(), CRED_TYPE_GENERIC, 0);
        }
    }
}

impl KeyringBackend for PlatformKeyring {
    fn read(&self) -> KeyringRead {
        #[cfg(target_os = "linux")]
        {
            linux_keyring::read(self.0)
        }
        #[cfg(target_os = "windows")]
        {
            windows_keyring::read(self.0)
        }
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
        {
            KeyringRead::Unavailable
        }
    }

    fn write(&self, token: &str) -> Result<(), KeyringError> {
        #[cfg(target_os = "linux")]
        {
            linux_keyring::write(self.0, token)
        }
        #[cfg(target_os = "windows")]
        {
            windows_keyring::write(self.0, token)
        }
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
        {
            let _ = token;
            Err(KeyringError::UnsupportedPlatform)
        }
    }

    fn delete(&self) {
        #[cfg(target_os = "linux")]
        linux_keyring::delete(self.0);
        #[cfg(target_os = "windows")]
        windows_keyring::delete(self.0);
    }
}

fn slot_legacy_path(slot: SecretSlot) -> Option<PathBuf> {
    dirs::config_dir().map(|d| d.join("ymusic").join(slot.legacy_file))
}

fn read_legacy_token(path: Option<&Path>) -> Option<String> {
    let token = fs::read_to_string(path?).ok()?;
    let token = token.trim();
    (!token.is_empty()).then(|| token.to_string())
}

fn write_legacy_token(path: Option<&Path>, token: &str) -> io::Result<()> {
    let path = path.ok_or_else(|| io::Error::other("нет каталога конфигурации"))?;
    let dir = path
        .parent()
        .ok_or_else(|| io::Error::other("некорректный путь к файлу токена"))?;
    fs::create_dir_all(dir)?;

    static TMP_SEQ: AtomicU64 = AtomicU64::new(0);
    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("secret");
    let tmp_path = dir.join(format!(
        ".{file_name}.{}.{}.tmp",
        std::process::id(),
        TMP_SEQ.fetch_add(1, Ordering::Relaxed)
    ));

    let mut opts = OpenOptions::new();
    opts.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600);
    }

    let write_res = (|| -> io::Result<()> {
        let mut file = opts.open(&tmp_path)?;
        file.write_all(token.as_bytes())?;
        file.sync_all()?;
        Ok(())
    })();
    if let Err(err) = write_res {
        let _ = fs::remove_file(&tmp_path);
        return Err(err);
    }

    if let Err(err) = fs::rename(&tmp_path, path) {
        let _ = fs::remove_file(&tmp_path);
        return Err(err);
    }
    Ok(())
}

fn load_token_with(backend: &dyn KeyringBackend, legacy_path: Option<&Path>) -> Option<String> {
    match backend.read() {
        KeyringRead::Found(token) => Some(token),
        KeyringRead::Missing => {
            let token = read_legacy_token(legacy_path)?;
            if backend.write(&token).is_ok()
                && let Some(path) = legacy_path
            {
                let _ = fs::remove_file(path);
            }
            Some(token)
        }
        KeyringRead::Unavailable => read_legacy_token(legacy_path),
    }
}

fn save_token_with(
    backend: &dyn KeyringBackend,
    legacy_path: Option<&Path>,
    token: &str,
) -> io::Result<TokenSaveOutcome> {
    match backend.write(token) {
        Ok(()) => {
            if let Some(path) = legacy_path {
                let _ = fs::remove_file(path);
            }
            Ok(TokenSaveOutcome::Keyring)
        }
        Err(err) => {
            let reason = err.to_string();
            eprintln!("[ymusic::config] системный keyring недоступен ({reason}), сохраняю секрет в файл (0600)");
            backend.delete();
            write_legacy_token(legacy_path, token)?;
            Ok(TokenSaveOutcome::FileFallback { reason })
        }
    }
}

fn clear_token_with(backend: &dyn KeyringBackend, legacy_path: Option<&Path>) {
    backend.delete();
    if let Some(path) = legacy_path {
        let _ = fs::remove_file(path);
    }
}

pub fn load_token() -> Option<String> {
    if let Ok(token) = std::env::var("YM_TOKEN")
        && !token.trim().is_empty()
    {
        return Some(token.trim().to_string());
    }
    let path = slot_legacy_path(YANDEX_TOKEN_SLOT);
    load_token_with(&PlatformKeyring(YANDEX_TOKEN_SLOT), path.as_deref())
}

pub fn save_token(token: &str) -> io::Result<TokenSaveOutcome> {
    let path = slot_legacy_path(YANDEX_TOKEN_SLOT);
    save_token_with(&PlatformKeyring(YANDEX_TOKEN_SLOT), path.as_deref(), token)
}

pub fn clear_token() {
    let path = slot_legacy_path(YANDEX_TOKEN_SLOT);
    clear_token_with(&PlatformKeyring(YANDEX_TOKEN_SLOT), path.as_deref());
}

pub fn load_lastfm_session() -> Option<String> {
    let path = slot_legacy_path(LASTFM_SESSION_SLOT);
    load_token_with(&PlatformKeyring(LASTFM_SESSION_SLOT), path.as_deref())
}

pub fn save_lastfm_session(session_key: &str) -> io::Result<TokenSaveOutcome> {
    let path = slot_legacy_path(LASTFM_SESSION_SLOT);
    save_token_with(&PlatformKeyring(LASTFM_SESSION_SLOT), path.as_deref(), session_key)
}

pub fn clear_lastfm_session() {
    let path = slot_legacy_path(LASTFM_SESSION_SLOT);
    clear_token_with(&PlatformKeyring(LASTFM_SESSION_SLOT), path.as_deref());
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SavedWaveState {
    pub seed: String,
    pub title: String,
    pub session_id: String,
    pub batch_id: String,
    pub tracks: Vec<Track>,
    #[serde(default)]
    pub filters: Vec<String>,
    #[serde(default)]
    pub selected: std::collections::HashMap<String, String>,
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
    pub user_uid: u64,
    #[serde(default)]
    pub user_name: Option<String>,
    #[serde(default)]
    pub user_avatar_url: Option<String>,
    #[serde(default)]
    pub repeat_mode: u8,
    #[serde(default)]
    pub shuffle: bool,
    #[serde(default)]
    pub pinned_playlists: Vec<PinnedPlaylist>,
    #[serde(default = "default_audio_quality")]
    pub audio_quality: String,
    #[serde(default = "default_download_quality")]
    pub download_quality: String,
    #[serde(default = "default_normalize_volume")]
    pub normalize_volume: bool,
    #[serde(default = "default_true")]
    pub gapless_enabled: bool,
    #[serde(default)]
    pub crossfade_secs: f32,
    #[serde(default = "default_ai_music_behavior")]
    pub ai_music_behavior: String,
    #[serde(default)]
    pub ai_strict_tracks: bool,
    #[serde(default = "default_show_ai_labels")]
    pub show_ai_labels: bool,
    #[serde(default)]
    pub wave_selected: std::collections::HashMap<String, String>,
    #[serde(default = "default_true")]
    pub lastfm_enabled: bool,
    #[serde(default)]
    pub lastfm_username: Option<String>,
    #[serde(default = "default_true")]
    pub lastfm_now_playing: bool,
    #[serde(default)]
    pub lastfm_love_on_like: bool,
    #[serde(default = "default_true")]
    pub lastfm_skip_ai: bool,
    #[serde(default)]
    pub lastfm_custom_api_key: Option<String>,
    #[serde(default)]
    pub lastfm_custom_api_secret: Option<String>,
}

fn default_true() -> bool {
    true
}

fn default_volume() -> f32 {
    0.7
}

fn default_audio_quality() -> String {
    "hq".to_string()
}

fn default_download_quality() -> String {
    "mp3".to_string()
}

fn default_normalize_volume() -> bool {
    true
}

fn default_ai_music_behavior() -> String {
    "skip_if_not_liked".to_string()
}

fn default_show_ai_labels() -> bool {
    true
}

impl Default for UserSettings {
    fn default() -> Self {
        Self {
            volume: default_volume(),
            session: None,
            user_uid: 0,
            user_name: None,
            user_avatar_url: None,
            repeat_mode: 0,
            shuffle: false,
            pinned_playlists: Vec::new(),
            audio_quality: default_audio_quality(),
            download_quality: default_download_quality(),
            normalize_volume: default_normalize_volume(),
            gapless_enabled: true,
            crossfade_secs: 0.0,
            ai_music_behavior: default_ai_music_behavior(),
            ai_strict_tracks: false,
            show_ai_labels: default_show_ai_labels(),
            wave_selected: std::collections::HashMap::new(),
            lastfm_enabled: true,
            lastfm_username: None,
            lastfm_now_playing: true,
            lastfm_love_on_like: false,
            lastfm_skip_ai: true,
            lastfm_custom_api_key: None,
            lastfm_custom_api_secret: None,
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
    static LOCK: parking_lot::Mutex<()> = parking_lot::Mutex::new(());
    let _guard = LOCK.lock();
    let mut settings = load_settings();
    f(&mut settings);
    let _ = save_settings(&settings);
}

#[cfg(test)]
mod token_tests {
    use super::*;
    use std::cell::RefCell;

    struct FakeKeyring {
        available: bool,
        secret: RefCell<Option<String>>,
    }

    impl FakeKeyring {
        fn available(initial: Option<&str>) -> Self {
            Self {
                available: true,
                secret: RefCell::new(initial.map(|s| s.to_string())),
            }
        }

        fn unavailable() -> Self {
            Self {
                available: false,
                secret: RefCell::new(None),
            }
        }
    }

    impl KeyringBackend for FakeKeyring {
        fn read(&self) -> KeyringRead {
            if !self.available {
                return KeyringRead::Unavailable;
            }
            match self.secret.borrow().as_ref() {
                Some(s) if !s.trim().is_empty() => KeyringRead::Found(s.trim().to_string()),
                _ => KeyringRead::Missing,
            }
        }

        fn write(&self, token: &str) -> Result<(), KeyringError> {
            if !self.available {
                return Err(KeyringError::Unavailable("fake keyring disabled".into()));
            }
            *self.secret.borrow_mut() = Some(token.to_string());
            Ok(())
        }

        fn delete(&self) {
            if self.available {
                *self.secret.borrow_mut() = None;
            }
        }
    }

    fn temp_token_path(name: &str) -> (PathBuf, PathBuf) {
        let dir = std::env::temp_dir().join(format!("ymusic-cfg-test-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let file = dir.join("token");
        (dir, file)
    }

    #[test]
    fn save_load_clear_uses_keyring_and_removes_legacy_file() {
        let (dir, legacy) = temp_token_path("keyring");
        fs::write(&legacy, "stale-file-token").unwrap();
        let kr = FakeKeyring::available(None);

        save_token_with(&kr, Some(&legacy), "y0_fresh").unwrap();
        assert!(!legacy.exists());
        assert_eq!(kr.secret.borrow().as_deref(), Some("y0_fresh"));
        assert_eq!(load_token_with(&kr, Some(&legacy)).as_deref(), Some("y0_fresh"));

        clear_token_with(&kr, Some(&legacy));
        assert!(kr.secret.borrow().is_none());
        assert_eq!(load_token_with(&kr, Some(&legacy)), None);
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn load_migrates_legacy_file_into_keyring() {
        let (dir, legacy) = temp_token_path("migrate");
        fs::write(&legacy, "y0_legacy\n").unwrap();
        let kr = FakeKeyring::available(None);

        let loaded = load_token_with(&kr, Some(&legacy));
        assert_eq!(loaded.as_deref(), Some("y0_legacy"));
        assert_eq!(kr.secret.borrow().as_deref(), Some("y0_legacy"));
        assert!(!legacy.exists());
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn unavailable_keyring_falls_back_to_file() {
        let (dir, legacy) = temp_token_path("fallback");
        let kr = FakeKeyring::unavailable();

        let outcome = save_token_with(&kr, Some(&legacy), "y0_fallback").unwrap();
        assert!(matches!(outcome, TokenSaveOutcome::FileFallback { .. }));
        assert!(legacy.exists());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs::metadata(&legacy).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode, 0o600);
        }
        assert_eq!(load_token_with(&kr, Some(&legacy)).as_deref(), Some("y0_fallback"));

        clear_token_with(&kr, Some(&legacy));
        assert!(!legacy.exists());
        assert_eq!(load_token_with(&kr, Some(&legacy)), None);
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn windows_utf16_blob_roundtrip() {
        let token = "y0_AgAAAAAtoken-123_юникод";
        let bytes = encode_utf16_le(token);
        assert_eq!(decode_utf16_blob(&bytes).as_deref(), Some(token));
    }
}
