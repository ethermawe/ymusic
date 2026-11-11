use std::fs;
use std::io;
use std::path::PathBuf;
use std::time::SystemTime;

use serde_json::Value;
use slint::Color;

fn token_path() -> Option<PathBuf> {
    dirs::config_dir().map(|d| d.join("ymusic").join("token"))
}

pub fn quickshell_colors_path() -> Option<PathBuf> {
    dirs::state_dir()
        .or_else(|| dirs::home_dir().map(|h| h.join(".local/state")))
        .map(|d| d.join("quickshell/user/generated/colors.json"))
}

#[derive(Clone, Copy)]
pub struct QsPalette {
    pub bg: Color,
    pub surface_low: Color,
    pub surface: Color,
    pub surface_hi: Color,
    pub surface_highest: Color,
    pub text: Color,
    pub muted: Color,
    pub outline: Color,
    pub accent: Color,
    pub on_accent: Color,
    pub secondary_container: Color,
    pub on_secondary_container: Color,
    pub danger: Color,
    pub on_danger: Color,
}

pub fn load_quickshell_palette() -> Option<(QsPalette, Option<SystemTime>)> {
    let path = quickshell_colors_path()?;
    let mtime = fs::metadata(&path).ok().and_then(|m| m.modified().ok());
    let content = fs::read_to_string(&path).ok()?;
    let v: Value = serde_json::from_str(&content).ok()?;
    let col = |key: &str| v[key].as_str().and_then(parse_hex_color);

    Some((
        QsPalette {
            bg: col("background").or_else(|| col("surface"))?,
            surface_low: col("surface_container_low")?,
            surface: col("surface_container")?,
            surface_hi: col("surface_container_high")?,
            surface_highest: col("surface_container_highest")?,
            text: col("on_surface")?,
            muted: col("outline")?,
            outline: col("outline_variant")?,
            accent: col("primary")?,
            on_accent: col("on_primary")?,
            secondary_container: col("secondary_container")?,
            on_secondary_container: col("on_secondary_container")?,
            danger: col("error_container")?,
            on_danger: col("on_error_container")?,
        },
        mtime,
    ))
}

fn parse_hex_color(s: &str) -> Option<Color> {
    let hex = s.trim().strip_prefix('#')?;
    if hex.len() != 6 {
        return None;
    }
    let r = u8::from_str_radix(&hex[0..2], 16).ok()?;
    let g = u8::from_str_radix(&hex[2..4], 16).ok()?;
    let b = u8::from_str_radix(&hex[4..6], 16).ok()?;
    Some(Color::from_rgb_u8(r, g, b))
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
