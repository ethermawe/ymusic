use std::ffi::{c_void, OsStr, OsString};
use std::fs;
use std::os::windows::ffi::{OsStrExt, OsStringExt};
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::ptr::{null, null_mut};
use std::time::{Duration, Instant};

use windows_sys::core::{BOOL, GUID};
use windows_sys::Win32::Foundation::{CloseHandle, HWND, LPARAM, MAX_PATH, S_OK, TRUE};
use windows_sys::Win32::Globalization::GetUserDefaultUILanguage;
use windows_sys::Win32::Graphics::Dwm::{
    DwmSetWindowAttribute, DWMWA_USE_IMMERSIVE_DARK_MODE, DWMWA_WINDOW_CORNER_PREFERENCE,
    DWMWCP_ROUND,
};
use windows_sys::Win32::System::Com::CoTaskMemFree;
use windows_sys::Win32::System::Diagnostics::ToolHelp::{
    CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS,
};
use windows_sys::Win32::System::Registry::{
    RegCloseKey, RegCreateKeyExW, RegDeleteTreeW, RegOpenKeyExW, RegQueryValueExW, RegSetValueExW,
    HKEY, HKEY_CURRENT_USER, KEY_READ, KEY_WRITE, REG_DWORD, REG_OPTION_NON_VOLATILE, REG_SZ,
};
use windows_sys::Win32::System::Threading::{
    GetCurrentProcessId, GetCurrentThreadId, OpenProcess, TerminateProcess, WaitForSingleObject,
    CREATE_NEW_PROCESS_GROUP, CREATE_NO_WINDOW, PROCESS_SYNCHRONIZE, PROCESS_TERMINATE,
};
use windows_sys::Win32::UI::Input::KeyboardAndMouse::ReleaseCapture;
use windows_sys::Win32::UI::Shell::{
    FOLDERID_Desktop, FOLDERID_LocalAppData, FOLDERID_Programs, FOLDERID_RoamingAppData,
    SHGetKnownFolderPath, KF_FLAG_DEFAULT,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    EnumThreadWindows, IsWindowVisible, SendMessageW, HTCAPTION, WM_NCLBUTTONDOWN,
};

const UNINSTALL_REG_PATH: &str = r"Software\Microsoft\Windows\CurrentVersion\Uninstall\YMusic";
const APP_DISPLAY_NAME: &str = "Yandex Music";
const APP_EXE_NAME: &str = "ymusic-qml.exe";
const START_MENU_FOLDER: &str = "Yandex Music";

fn to_wide_null(s: &OsStr) -> Vec<u16> {
    s.encode_wide().chain(std::iter::once(0)).collect()
}

fn str_to_wide_null(s: &str) -> Vec<u16> {
    to_wide_null(OsStr::new(s))
}

unsafe fn known_folder(id: &GUID) -> Option<PathBuf> {
    let mut raw: *mut u16 = null_mut();
    let hr = unsafe { SHGetKnownFolderPath(id, KF_FLAG_DEFAULT as u32, null_mut(), &mut raw) };
    if hr != S_OK || raw.is_null() {
        return None;
    }
    let mut len = 0usize;
    while unsafe { *raw.add(len) } != 0 {
        len += 1;
    }
    let slice = unsafe { std::slice::from_raw_parts(raw, len) };
    let path = PathBuf::from(OsString::from_wide(slice));
    unsafe { CoTaskMemFree(raw as *const c_void) };
    Some(path)
}

pub fn detect_is_russian() -> bool {
    let lang = unsafe { GetUserDefaultUILanguage() };
    (lang & 0x03ff) == 0x19 // LANG_RUSSIAN
}

pub fn default_install_dir() -> PathBuf {
    if let Some(existing) = read_reg_install_location() {
        return existing;
    }
    unsafe {
        if let Some(local) = known_folder(&FOLDERID_LocalAppData) {
            return local.join("Programs").join("YMusic");
        }
    }
    PathBuf::from(r"C:\YMusic")
}

fn read_reg_install_location() -> Option<PathBuf> {
    let subkey = str_to_wide_null(UNINSTALL_REG_PATH);
    let val_name = str_to_wide_null("InstallLocation");
    let mut hkey: HKEY = null_mut();
    let err = unsafe { RegOpenKeyExW(HKEY_CURRENT_USER, subkey.as_ptr(), 0, KEY_READ, &mut hkey) };
    if err != 0 || hkey.is_null() {
        return None;
    }

    let mut buf = vec![0u16; MAX_PATH as usize * 2];
    let mut byte_len = (buf.len() * 2) as u32;
    let qerr = unsafe {
        RegQueryValueExW(
            hkey,
            val_name.as_ptr(),
            null_mut(),
            null_mut(),
            buf.as_mut_ptr() as *mut u8,
            &mut byte_len,
        )
    };
    unsafe { RegCloseKey(hkey) };

    if qerr != 0 || byte_len < 2 {
        return None;
    }
    let u16_len = (byte_len as usize / 2).min(buf.len());
    let trimmed = &buf[..u16_len];
    let nul_pos = trimmed
        .iter()
        .position(|&c| c == 0)
        .unwrap_or(trimmed.len());
    let s = String::from_utf16_lossy(&trimmed[..nul_pos])
        .trim()
        .to_string();
    if s.is_empty() {
        None
    } else {
        Some(PathBuf::from(s))
    }
}

fn find_current_thread_hwnd() -> Option<HWND> {
    unsafe extern "system" fn enum_proc(hwnd: HWND, lparam: LPARAM) -> BOOL {
        if unsafe { IsWindowVisible(hwnd) } != 0 {
            let target = lparam as *mut HWND;
            unsafe { *target = hwnd };
            return 0;
        }
        TRUE
    }
    let mut found: HWND = null_mut();
    let tid = unsafe { GetCurrentThreadId() };
    unsafe {
        EnumThreadWindows(tid, Some(enum_proc), &mut found as *mut HWND as LPARAM);
    }
    if found.is_null() {
        None
    } else {
        Some(found)
    }
}

pub fn apply_window_chrome() {
    if let Some(hwnd) = find_current_thread_hwnd() {
        unsafe {
            let dark: i32 = 1;
            let _ = DwmSetWindowAttribute(
                hwnd,
                DWMWA_USE_IMMERSIVE_DARK_MODE as u32,
                &dark as *const i32 as *const c_void,
                std::mem::size_of::<i32>() as u32,
            );
            let corner: i32 = DWMWCP_ROUND;
            let _ = DwmSetWindowAttribute(
                hwnd,
                DWMWA_WINDOW_CORNER_PREFERENCE as u32,
                &corner as *const i32 as *const c_void,
                std::mem::size_of::<i32>() as u32,
            );
        }
    }
}

pub fn begin_native_drag() -> bool {
    if let Some(hwnd) = find_current_thread_hwnd() {
        unsafe {
            ReleaseCapture();
            SendMessageW(hwnd, WM_NCLBUTTONDOWN, HTCAPTION as usize, 0);
        }
        return true;
    }
    false
}

pub fn pick_folder(initial: &Path) -> Option<PathBuf> {
    let mut dialog = rfd::FileDialog::new();
    if initial.exists() {
        dialog = dialog.set_directory(initial);
    }
    dialog.pick_folder()
}

pub fn stop_running_app(_install_dir: &Path) -> Result<(), String> {
    let my_pid = unsafe { GetCurrentProcessId() };
    let target_name = APP_EXE_NAME.to_ascii_lowercase();

    let wait_deadline = Instant::now() + Duration::from_secs(4);

    loop {
        let pids = find_pids_by_name(&target_name, my_pid);
        if pids.is_empty() {
            break;
        }

        if Instant::now() >= wait_deadline {
            for pid in pids {
                unsafe {
                    let handle = OpenProcess(PROCESS_TERMINATE | PROCESS_SYNCHRONIZE, 0, pid);
                    if !handle.is_null() {
                        TerminateProcess(handle, 0);
                        WaitForSingleObject(handle, 2000);
                        CloseHandle(handle);
                    }
                }
            }
            break;
        }
        std::thread::sleep(Duration::from_millis(200));
    }

    Ok(())
}

fn find_pids_by_name(target_lower: &str, exclude_pid: u32) -> Vec<u32> {
    let mut out = Vec::new();
    let snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
    if snapshot.is_null() || snapshot == windows_sys::Win32::Foundation::INVALID_HANDLE_VALUE {
        return out;
    }

    let mut entry: PROCESSENTRY32W = unsafe { std::mem::zeroed() };
    entry.dwSize = std::mem::size_of::<PROCESSENTRY32W>() as u32;

    if unsafe { Process32FirstW(snapshot, &mut entry) } != 0 {
        loop {
            if entry.th32ProcessID != exclude_pid {
                let nul = entry
                    .szExeFile
                    .iter()
                    .position(|&c| c == 0)
                    .unwrap_or(entry.szExeFile.len());
                let name = String::from_utf16_lossy(&entry.szExeFile[..nul]).to_ascii_lowercase();
                if name == target_lower {
                    out.push(entry.th32ProcessID);
                }
            }
            if unsafe { Process32NextW(snapshot, &mut entry) } == 0 {
                break;
            }
        }
    }

    unsafe { CloseHandle(snapshot) };
    out
}

fn base64_utf16le(script: &str) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut bytes = Vec::with_capacity(script.len() * 2);
    for u in script.encode_utf16() {
        bytes.extend_from_slice(&u.to_le_bytes());
    }
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b0 = chunk[0] as usize;
        let b1 = if chunk.len() > 1 {
            chunk[1] as usize
        } else {
            0
        };
        let b2 = if chunk.len() > 2 {
            chunk[2] as usize
        } else {
            0
        };
        out.push(TABLE[(b0 >> 2) & 0x3f] as char);
        out.push(TABLE[((b0 << 4) | (b1 >> 4)) & 0x3f] as char);
        out.push(if chunk.len() > 1 {
            TABLE[((b1 << 2) | (b2 >> 6)) & 0x3f] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            TABLE[b2 & 0x3f] as char
        } else {
            '='
        });
    }
    out
}

fn ps_escape_single_quoted(s: &str) -> String {
    s.replace('\'', "''")
}

fn create_shortcuts_batch(shortcuts: &[(&Path, &Path, &str, &Path, &Path)]) -> Result<(), String> {
    if shortcuts.is_empty() {
        return Ok(());
    }
    let mut script = String::from("$ws = New-Object -ComObject WScript.Shell\n");
    for (lnk, target, args, work_dir, icon) in shortcuts {
        script.push_str(&format!(
            "$s = $ws.CreateShortcut('{}')\n\
             $s.TargetPath = '{}'\n\
             $s.Arguments = '{}'\n\
             $s.WorkingDirectory = '{}'\n\
             $s.IconLocation = '{},0'\n\
             $s.Save()\n",
            ps_escape_single_quoted(&lnk.to_string_lossy()),
            ps_escape_single_quoted(&target.to_string_lossy()),
            ps_escape_single_quoted(args),
            ps_escape_single_quoted(&work_dir.to_string_lossy()),
            ps_escape_single_quoted(&icon.to_string_lossy()),
        ));
    }

    let encoded = base64_utf16le(&script);
    let status = Command::new("powershell.exe")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-WindowStyle",
            "Hidden",
            "-EncodedCommand",
            &encoded,
        ])
        .creation_flags(CREATE_NO_WINDOW)
        .status()
        .map_err(|e| format!("Failed to invoke powershell.exe: {e}"))?;

    if !status.success() {
        return Err(format!("Shortcut creation exited with {status}"));
    }
    Ok(())
}

pub fn create_shortcuts_and_registry(
    install_dir: &Path,
    desktop_shortcut: bool,
    start_menu_shortcut: bool,
    version: &str,
    total_bytes: u64,
    is_ru: bool,
) -> Result<(), String> {
    let app_exe = install_dir.join(APP_EXE_NAME);
    let uninstall_exe = install_dir.join("Uninstall.exe");

    let mut links: Vec<(PathBuf, PathBuf, &str, PathBuf, PathBuf)> = Vec::new();

    if start_menu_shortcut {
        if let Some(programs) = unsafe { known_folder(&FOLDERID_Programs) } {
            let sm_dir = programs.join(START_MENU_FOLDER);
            fs::create_dir_all(&sm_dir).map_err(|e| e.to_string())?;
            links.push((
                sm_dir.join(format!("{APP_DISPLAY_NAME}.lnk")),
                app_exe.clone(),
                "",
                install_dir.to_path_buf(),
                app_exe.clone(),
            ));
            let uninst_name = if is_ru {
                format!("Удалить {APP_DISPLAY_NAME}.lnk")
            } else {
                format!("Uninstall {APP_DISPLAY_NAME}.lnk")
            };
            links.push((
                sm_dir.join(uninst_name),
                uninstall_exe.clone(),
                "--uninstall",
                install_dir.to_path_buf(),
                uninstall_exe.clone(),
            ));
        }
    }

    if desktop_shortcut {
        if let Some(desktop) = unsafe { known_folder(&FOLDERID_Desktop) } {
            links.push((
                desktop.join(format!("{APP_DISPLAY_NAME}.lnk")),
                app_exe.clone(),
                "",
                install_dir.to_path_buf(),
                app_exe.clone(),
            ));
        }
    }

    let borrowed: Vec<(&Path, &Path, &str, &Path, &Path)> = links
        .iter()
        .map(|(a, b, c, d, e)| (a.as_path(), b.as_path(), *c, d.as_path(), e.as_path()))
        .collect();
    create_shortcuts_batch(&borrowed)?;

    write_uninstall_registry(install_dir, &app_exe, &uninstall_exe, version, total_bytes)?;
    Ok(())
}

fn write_uninstall_registry(
    install_dir: &Path,
    app_exe: &Path,
    uninstall_exe: &Path,
    version: &str,
    total_bytes: u64,
) -> Result<(), String> {
    let subkey = str_to_wide_null(UNINSTALL_REG_PATH);
    let mut hkey: HKEY = null_mut();
    let err = unsafe {
        RegCreateKeyExW(
            HKEY_CURRENT_USER,
            subkey.as_ptr(),
            0,
            null(),
            REG_OPTION_NON_VOLATILE,
            KEY_WRITE,
            null(),
            &mut hkey,
            null_mut(),
        )
    };
    if err != 0 || hkey.is_null() {
        return Err(format!("RegCreateKeyExW failed with code {err}"));
    }

    let set_sz = |name: &str, val: &str| -> Result<(), String> {
        let name_w = str_to_wide_null(name);
        let val_w = str_to_wide_null(val);
        let rc = unsafe {
            RegSetValueExW(
                hkey,
                name_w.as_ptr(),
                0,
                REG_SZ,
                val_w.as_ptr() as *const u8,
                (val_w.len() * 2) as u32,
            )
        };
        if rc != 0 {
            return Err(format!("RegSetValueExW {name} failed with code {rc}"));
        }
        Ok(())
    };

    let set_dword = |name: &str, val: u32| -> Result<(), String> {
        let name_w = str_to_wide_null(name);
        let bytes = val.to_le_bytes();
        let rc = unsafe {
            RegSetValueExW(
                hkey,
                name_w.as_ptr(),
                0,
                REG_DWORD,
                bytes.as_ptr(),
                bytes.len() as u32,
            )
        };
        if rc != 0 {
            return Err(format!("RegSetValueExW {name} failed with code {rc}"));
        }
        Ok(())
    };

    let res = (|| {
        set_sz("DisplayName", APP_DISPLAY_NAME)?;
        set_sz("DisplayVersion", version)?;
        set_sz("Publisher", "ethermawe")?;
        set_sz("InstallLocation", &install_dir.to_string_lossy())?;
        set_sz("DisplayIcon", &app_exe.to_string_lossy())?;
        set_sz(
            "UninstallString",
            &format!("\"{}\" --uninstall", uninstall_exe.display()),
        )?;
        set_sz(
            "QuietUninstallString",
            &format!("\"{}\" --uninstall /S", uninstall_exe.display()),
        )?;
        set_dword("NoModify", 1)?;
        set_dword("NoRepair", 1)?;
        set_dword("EstimatedSize", ((total_bytes / 1024).max(1)) as u32)?;
        Ok(())
    })();

    unsafe { RegCloseKey(hkey) };
    res
}

pub fn launch_app(install_dir: &Path) -> Result<(), String> {
    let exe = install_dir.join(APP_EXE_NAME);
    if !exe.exists() {
        return Err(format!("Executable not found: {}", exe.display()));
    }
    Command::new(&exe)
        .current_dir(install_dir)
        .creation_flags(CREATE_NEW_PROCESS_GROUP)
        .spawn()
        .map_err(|e| format!("Failed to start {}: {e}", exe.display()))?;
    Ok(())
}

pub fn remove_shortcuts_and_registry() {
    unsafe {
        if let Some(desktop) = known_folder(&FOLDERID_Desktop) {
            let _ = fs::remove_file(desktop.join(format!("{APP_DISPLAY_NAME}.lnk")));
        }
        if let Some(programs) = known_folder(&FOLDERID_Programs) {
            let _ = fs::remove_dir_all(programs.join(START_MENU_FOLDER));
        }
        let subkey = str_to_wide_null(UNINSTALL_REG_PATH);
        let _ = RegDeleteTreeW(HKEY_CURRENT_USER, subkey.as_ptr());
    }
}

pub fn remove_user_data_dirs() {
    unsafe {
        if let Some(roaming) = known_folder(&FOLDERID_RoamingAppData) {
            let _ = fs::remove_dir_all(roaming.join("ymusic"));
        }
        if let Some(local) = known_folder(&FOLDERID_LocalAppData) {
            let _ = fs::remove_dir_all(local.join("ymusic"));
            let _ = fs::remove_dir_all(local.join("cache").join("ymusic"));
        }
    }
}

pub fn schedule_self_delete_after_exit(install_dir: &Path) {
    let Ok(cur_exe) = std::env::current_exe() else {
        return;
    };
    let in_install_dir = cur_exe.parent().map(|p| p.eq(install_dir)).unwrap_or(false);
    if !in_install_dir {
        let _ = fs::remove_dir_all(install_dir);
        return;
    }

    let script = format!(
        "ping 127.0.0.1 -n 2 > nul & del /F /Q \"{}\" & rmdir \"{}\"",
        cur_exe.display(),
        install_dir.display()
    );
    let _ = Command::new("cmd.exe")
        .args(["/C", &script])
        .creation_flags(CREATE_NO_WINDOW)
        .spawn();
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
