use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn detect_is_russian() -> bool {
    for var in ["LC_ALL", "LC_MESSAGES", "LANG"] {
        if let Ok(val) = std::env::var(var) {
            let lower = val.to_ascii_lowercase();
            if lower.starts_with("ru") {
                return true;
            }
            if !lower.is_empty() && lower != "c" && lower != "posix" {
                return false;
            }
        }
    }
    true
}

pub fn default_install_dir() -> PathBuf {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    home.join(".local").join("share").join("ymusic-setup-preview")
}

pub fn apply_window_chrome() {}

pub fn begin_native_drag() -> bool {
    false
}

pub fn pick_folder(initial: &Path) -> Option<PathBuf> {
    if let Ok(out) = Command::new("kdialog")
        .arg("--getexistingdirectory")
        .arg(initial)
        .output()
    {
        if out.status.success() {
            let p = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !p.is_empty() {
                return Some(PathBuf::from(p));
            }
        }
    }
    if let Ok(out) = Command::new("zenity")
        .args(["--file-selection", "--directory"])
        .output()
    {
        if out.status.success() {
            let p = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !p.is_empty() {
                return Some(PathBuf::from(p));
            }
        }
    }
    None
}

pub fn stop_running_app(_install_dir: &Path) -> Result<(), String> {
    Ok(())
}

pub fn create_shortcuts_and_registry(
    _install_dir: &Path,
    _desktop_shortcut: bool,
    _start_menu_shortcut: bool,
    _version: &str,
    _total_bytes: u64,
    _is_ru: bool,
) -> Result<(), String> {
    Ok(())
}

pub fn launch_app(install_dir: &Path) -> Result<(), String> {
    let bin = install_dir.join("ymusic-qml");
    if bin.exists() {
        Command::new(&bin)
            .current_dir(install_dir)
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub fn remove_shortcuts_and_registry() {}

pub fn remove_user_data_dirs() {}

pub fn schedule_self_delete_after_exit(install_dir: &Path) {
    let _ = fs::remove_dir_all(install_dir);
}

pub fn copy_uninstaller_fallback(
    exe_path: &Path,
    payload_offset: u64,
    dest_uninstall_exe: &Path,
) -> std::io::Result<()> {
    use std::io::{Read, Write};
    let mut src = fs::File::open(exe_path)?;
    let mut dst = fs::File::create(dest_uninstall_exe)?;
    let mut limited = (&mut src).take(payload_offset);
    std::io::copy(&mut limited, &mut dst)?;
    dst.flush()?;
    Ok(())
}
