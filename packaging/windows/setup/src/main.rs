#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

use ymusic_setup::payload;

#[cfg(windows)]
mod os_win;
#[cfg(windows)]
use os_win as os_impl;

#[cfg(not(windows))]
mod os_unix;
#[cfg(not(windows))]
use os_unix as os_impl;

use std::cell::Cell;
use std::f32::consts::TAU;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::Arc;
use std::time::Duration;

use slint::{
    ComponentHandle, Image, PhysicalPosition, Rgba8Pixel, SharedPixelBuffer, SharedString, Timer,
    TimerMode,
};

slint::include_modules!();

#[derive(Debug, Clone)]
struct CliOptions {
    silent: bool,
    relaunch: bool,
    uninstall: bool,
    preview: bool,
    install_dir: Option<PathBuf>,
    lang_override: Option<bool>,
}

fn parse_cli_args() -> CliOptions {
    let mut opts = CliOptions {
        silent: false,
        relaunch: false,
        uninstall: false,
        preview: false,
        install_dir: None,
        lang_override: None,
    };

    if let Ok(exe) = std::env::current_exe() {
        if let Some(stem) = exe.file_stem().and_then(|s| s.to_str()) {
            if stem.eq_ignore_ascii_case("uninstall") {
                opts.uninstall = true;
            }
        }
    }

    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        let lower = a.to_ascii_lowercase();
        if lower == "/s" || lower == "--silent" {
            opts.silent = true;
        } else if lower == "/relaunch" || lower == "--relaunch" {
            opts.relaunch = true;
        } else if lower == "--uninstall" || lower == "/uninstall" {
            opts.uninstall = true;
        } else if lower == "--preview" {
            opts.preview = true;
        } else if let Some(rest) = a.strip_prefix("/D=").or_else(|| a.strip_prefix("/d=")) {
            if !rest.is_empty() {
                opts.install_dir = Some(PathBuf::from(rest));
            }
        } else if (lower == "--dir" || lower == "-d") && i + 1 < args.len() {
            i += 1;
            opts.install_dir = Some(PathBuf::from(&args[i]));
        } else if lower == "--lang" && i + 1 < args.len() {
            i += 1;
            let val = args[i].to_ascii_lowercase();
            opts.lang_override = Some(val.starts_with("ru"));
        }
        i += 1;
    }

    opts
}

fn run_install_sync<F>(
    exe_path: &Path,
    payload: Option<&payload::EmbeddedPayload>,
    install_dir: &Path,
    desktop_shortcut: bool,
    start_menu_shortcut: bool,
    is_ru: bool,
    mut on_progress: F,
) -> Result<(), String>
where
    F: FnMut(f32, &str),
{
    on_progress(
        0.04,
        if is_ru {
            "Завершение запущенного приложения…"
        } else {
            "Waiting for running app to exit…"
        },
    );
    os_impl::stop_running_app(install_dir)?;

    if let Some(pack) = payload {
        payload::extract_payload(exe_path, pack, install_dir, |done, total, file_name| {
            let frac = 0.06 + 0.84 * (done as f32 / total.max(1) as f32);
            let msg = if is_ru {
                format!("Распаковка ({done}/{total}): {file_name}")
            } else {
                format!("Extracting ({done}/{total}): {file_name}")
            };
            on_progress(frac, &msg);
        })
        .map_err(|e| format!("Extraction failed: {e}"))?;

        let uninstall_exe = install_dir.join("Uninstall.exe");
        let _ = os_impl::copy_uninstaller_fallback(exe_path, pack.offset, &uninstall_exe);

        on_progress(
            0.94,
            if is_ru {
                "Создание ярлыков и регистрация…"
            } else {
                "Creating shortcuts and registering…"
            },
        );
        os_impl::create_shortcuts_and_registry(
            install_dir,
            desktop_shortcut,
            start_menu_shortcut,
            &pack.metadata.version,
            pack.metadata.total_bytes,
            is_ru,
        )?;
    } else {
        // Preview simulation when launched un-packed locally
        for step in 1..=45 {
            let frac = 0.04 + 0.94 * (step as f32 / 45.0);
            let msg = if is_ru {
                format!("Предпросмотр установки ({step}/45)…")
            } else {
                format!("Preview install step ({step}/45)…")
            };
            on_progress(frac, &msg);
            std::thread::sleep(Duration::from_millis(60));
        }
    }

    on_progress(
        1.0,
        if is_ru { "Установка завершена" } else { "Installation complete" },
    );
    Ok(())
}

fn run_uninstall_sync<F>(
    install_dir: &Path,
    remove_data: bool,
    is_preview: bool,
    is_ru: bool,
    mut on_progress: F,
) -> Result<(), String>
where
    F: FnMut(f32, &str),
{
    on_progress(
        0.1,
        if is_ru {
            "Остановка приложения…"
        } else {
            "Stopping application…"
        },
    );
    if !is_preview {
        os_impl::stop_running_app(install_dir)?;
    }

    on_progress(
        0.35,
        if is_ru {
            "Удаление ярлыков и записей реестра…"
        } else {
            "Removing shortcuts and registry entries…"
        },
    );
    if !is_preview {
        os_impl::remove_shortcuts_and_registry();
    }

    on_progress(
        0.65,
        if is_ru {
            "Очистка файлов приложения…"
        } else {
            "Removing application files…"
        },
    );
    if !is_preview && install_dir.exists() {
        let cur_exe = std::env::current_exe().ok();
        if let Ok(entries) = std::fs::read_dir(install_dir) {
            for entry in entries.flatten() {
                let p = entry.path();
                if let Some(ref self_path) = cur_exe {
                    if &p == self_path {
                        continue;
                    }
                }
                if p.is_dir() {
                    let _ = std::fs::remove_dir_all(&p);
                } else {
                    let _ = std::fs::remove_file(&p);
                }
            }
        }
    } else if is_preview {
        std::thread::sleep(std::time::Duration::from_millis(350));
    }

    if remove_data && !is_preview {
        on_progress(
            0.85,
            if is_ru {
                "Удаление пользовательских данных…"
            } else {
                "Removing user data…"
            },
        );
        os_impl::remove_user_data_dirs();
    }

    if !is_preview {
        os_impl::schedule_self_delete_after_exit(install_dir);
    }

    on_progress(1.0, if is_ru { "Готово" } else { "Done" });
    Ok(())
}

fn main() {
    let cli = parse_cli_args();
    let is_ru = cli.lang_override.unwrap_or_else(os_impl::detect_is_russian);

    let exe_path = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("ymusic-setup"));
    let embedded = payload::read_embedded_payload(&exe_path).ok().flatten();

    let default_dir = cli.install_dir.clone().unwrap_or_else(|| {
        if cli.uninstall {
            exe_path
                .parent()
                .map(Path::to_path_buf)
                .filter(|p| p.join("ymusic-qml.exe").exists())
                .unwrap_or_else(os_impl::default_install_dir)
        } else {
            os_impl::default_install_dir()
        }
    });

    if cli.silent {
        let res = if cli.uninstall {
            run_uninstall_sync(&default_dir, false, false, is_ru, |_, _| {})
        } else {
            let Some(ref pack) = embedded else {
                std::process::exit(1);
            };
            run_install_sync(
                &exe_path,
                Some(pack),
                &default_dir,
                true,
                true,
                is_ru,
                |_, _| {},
            )
            .and_then(|_| {
                if cli.relaunch {
                    os_impl::launch_app(&default_dir)
                } else {
                    Ok(())
                }
            })
        };
        if res.is_err() {
            std::process::exit(1);
        }
        return;
    }

    let preview_mode = cli.preview || (embedded.is_none() && cfg!(debug_assertions) && !cli.uninstall);
    let missing_payload_error = !cli.uninstall && embedded.is_none() && !preview_mode;

    let ui = InstallerWindow::new().expect("Failed to create installer window");
    ui.set_is_ru(is_ru);
    ui.set_install_dir(SharedString::from(default_dir.to_string_lossy().as_ref()));
    ui.set_progress_wave(render_wavy_progress_image(0.0, 0.0, false));

    if missing_payload_error {
        ui.set_screen_mode("error".into());
        ui.set_error_text(SharedString::from(if is_ru {
            "Архив установщика не найден или повреждён. Скачайте установщик заново со страницы релизов."
        } else {
            "Installer payload is missing or corrupted. Please re-download the setup file."
        }));
    } else if cli.uninstall {
        ui.set_screen_mode("uninstall".into());
    } else {
        ui.set_screen_mode("setup".into());
    }

    let weak = ui.as_weak();
    ui.on_close_clicked(move || {
        let _ = slint::quit_event_loop();
    });

    let weak_min = ui.as_weak();
    ui.on_minimize_clicked(move || {
        if let Some(u) = weak_min.upgrade() {
            u.window().set_minimized(true);
        }
    });

    let weak_drag = ui.as_weak();
    let native_drag_active = std::cell::Cell::new(false);
    ui.on_drag_requested(move |dx, dy| {
        if dx == 0.0 && dy == 0.0 {
            native_drag_active.set(os_impl::begin_native_drag());
            return;
        }
        // On Windows, WM_NCLBUTTONDOWN(HTCAPTION) handles the entire drag natively
        // and consumes WM_LBUTTONUP, so Slint's TouchArea may stay `pressed` afterward.
        // Never run the manual set_position fallback once native drag took over.
        if native_drag_active.get() {
            return;
        }
        if let Some(u) = weak_drag.upgrade() {
            let w = u.window();
            let scale = w.scale_factor();
            let pos = w.position();
            w.set_position(PhysicalPosition::new(
                pos.x + (dx * scale) as i32,
                pos.y + (dy * scale) as i32,
            ));
        }
    });

    let weak_lang = ui.as_weak();
    ui.on_toggle_lang_clicked(move || {
        if let Some(u) = weak_lang.upgrade() {
            let next_ru = !u.get_is_ru();
            u.set_is_ru(next_ru);
        }
    });

    let weak_browse = ui.as_weak();
    ui.on_browse_clicked(move || {
        if let Some(u) = weak_browse.upgrade() {
            let cur = PathBuf::from(u.get_install_dir().as_str());
            if let Some(chosen) = os_impl::pick_folder(&cur) {
                let target = if chosen
                    .file_name()
                    .and_then(|s| s.to_str())
                    .map(|s| s.eq_ignore_ascii_case("YMusic"))
                    .unwrap_or(false)
                {
                    chosen
                } else {
                    chosen.join("YMusic")
                };
                u.set_install_dir(SharedString::from(target.to_string_lossy().as_ref()));
            }
        }
    });

    let payload_arc = Arc::new(embedded);
    let exe_arc = Arc::new(exe_path);

    let weak_install = ui.as_weak();
    let payload_inst = Arc::clone(&payload_arc);
    let exe_inst = Arc::clone(&exe_arc);
    ui.on_install_clicked(move || {
        let Some(u) = weak_install.upgrade() else {
            return;
        };
        let dir = PathBuf::from(u.get_install_dir().as_str());
        let desktop = u.get_opt_desktop();
        let start_menu = u.get_opt_start_menu();
        let auto_launch = u.get_opt_launch();
        let ru = u.get_is_ru();

        u.set_progress(0.02);
        u.set_status_text(SharedString::from(if ru {
            "Подготовка…"
        } else {
            "Preparing…"
        }));
        u.set_screen_mode("installing".into());

        let weak_worker = weak_install.clone();
        let pack_ref = Arc::clone(&payload_inst);
        let exe_ref = Arc::clone(&exe_inst);

        std::thread::spawn(move || {
            let res = run_install_sync(
                &exe_ref,
                pack_ref.as_ref().as_ref(),
                &dir,
                desktop,
                start_menu,
                ru,
                |p, msg| {
                    let weak_ui = weak_worker.clone();
                    let status = msg.to_string();
                    let _ = slint::invoke_from_event_loop(move || {
                        if let Some(u) = weak_ui.upgrade() {
                            u.set_progress(p);
                            u.set_status_text(SharedString::from(status.as_str()));
                        }
                    });
                },
            );

            let weak_done = weak_worker.clone();
            let _ = slint::invoke_from_event_loop(move || {
                let Some(u) = weak_done.upgrade() else {
                    return;
                };
                match res {
                    Ok(()) => {
                        if auto_launch && pack_ref.is_some() {
                            let _ = os_impl::launch_app(&dir);
                            let _ = slint::quit_event_loop();
                        } else {
                            u.set_progress(1.0);
                            u.set_screen_mode("done".into());
                        }
                    }
                    Err(err) => {
                        u.set_error_text(SharedString::from(err.as_str()));
                        u.set_screen_mode("error".into());
                    }
                }
            });
        });
    });

    let weak_launch = ui.as_weak();
    ui.on_launch_clicked(move || {
        if let Some(u) = weak_launch.upgrade() {
            let dir = PathBuf::from(u.get_install_dir().as_str());
            if let Err(err) = os_impl::launch_app(&dir) {
                u.set_error_text(SharedString::from(err.as_str()));
                u.set_screen_mode("error".into());
                return;
            }
            let _ = slint::quit_event_loop();
        }
    });

    let weak_uninst = ui.as_weak();
    ui.on_uninstall_clicked(move || {
        let Some(u) = weak_uninst.upgrade() else {
            return;
        };
        let dir = PathBuf::from(u.get_install_dir().as_str());
        let remove_data = u.get_opt_remove_data();
        let ru = u.get_is_ru();
        let is_prev = preview_mode;

        u.set_progress(0.05);
        u.set_status_text(SharedString::from(if ru {
            "Подготовка к удалению…"
        } else {
            "Preparing uninstall…"
        }));
        u.set_screen_mode("uninstalling".into());

        let weak_worker = weak_uninst.clone();
        std::thread::spawn(move || {
            let res = run_uninstall_sync(&dir, remove_data, is_prev, ru, |p, msg| {
                let weak_ui = weak_worker.clone();
                let status = msg.to_string();
                let _ = slint::invoke_from_event_loop(move || {
                    if let Some(u) = weak_ui.upgrade() {
                        u.set_progress(p);
                        u.set_status_text(SharedString::from(status.as_str()));
                    }
                });
            });

            let weak_done = weak_worker.clone();
            let _ = slint::invoke_from_event_loop(move || {
                let Some(u) = weak_done.upgrade() else {
                    return;
                };
                match res {
                    Ok(()) => {
                        u.set_progress(1.0);
                        u.set_screen_mode("uninstalled".into());
                    }
                    Err(err) => {
                        u.set_error_text(SharedString::from(err.as_str()));
                        u.set_screen_mode("error".into());
                    }
                }
            });
        });
    });

    let wave_timer = Timer::default();
    let wave_phase = Rc::new(Cell::new(0.0f32));
    let shown_progress = Rc::new(Cell::new(0.0f32));
    {
        let weak_wave = ui.as_weak();
        let phase_cell = Rc::clone(&wave_phase);
        let shown_cell = Rc::clone(&shown_progress);
        wave_timer.start(TimerMode::Repeated, Duration::from_millis(33), move || {
            let Some(u) = weak_wave.upgrade() else {
                return;
            };
            let mode = u.get_screen_mode();
            let is_installing = mode == "installing";
            let is_uninstalling = mode == "uninstalling";
            if !is_installing && !is_uninstalling {
                shown_cell.set(0.0);
                return;
            }
            let target = u.get_progress().clamp(0.0, 1.0);
            let prev = shown_cell.get();
            let next_prog = prev + (target - prev) * 0.25;
            shown_cell.set(next_prog);

            let next_phase = (phase_cell.get() - 0.145).rem_euclid(TAU);
            phase_cell.set(next_phase);

            u.set_progress_wave(render_wavy_progress_image(
                next_prog,
                next_phase,
                is_uninstalling,
            ));
        });
    }

    ui.show().expect("Failed to show installer window");
    os_impl::apply_window_chrome();
    let _ = weak;
    ui.run().expect("Event loop failed");
}

fn render_wavy_progress_image(progress: f32, phase: f32, is_uninstall: bool) -> Image {
    const W: usize = 1000;
    const H: usize = 44;
    const SCALE: f32 = 2.0;

    let thickness = 4.0 * SCALE;
    let half = 0.5 * thickness;
    let amplitude = 2.4 * SCALE;
    let wavelength = 34.0 * SCALE;
    let gap = 5.0 * SCALE;

    let wf = W as f32;
    let hf = H as f32;
    let handle_x = progress.clamp(0.0, 1.0) * wf;
    let active_end = handle_x;
    let track_start = if active_end > half {
        active_end + gap
    } else {
        half
    };

    let active_rgb: [u8; 3] = if is_uninstall {
        [242, 184, 181]
    } else {
        [208, 188, 255]
    };
    let track_rgb: [u8; 3] = [56, 52, 68];

    let mut buffer = SharedPixelBuffer::<Rgba8Pixel>::new(W as u32, H as u32);
    let pixels = buffer.make_mut_slice();

    let slope_k = amplitude * TAU / wavelength;

    for py in 0..H {
        let point_y = py as f32 + 0.5 - 0.5 * hf;
        let row_offset = py * W;
        for px in 0..W {
            let point_x = px as f32 + 0.5;

            let mut played = 0.0f32;
            if active_end > half && point_x <= active_end + half + 2.0 {
                let x = point_x.clamp(half, active_end);
                let angle = TAU * x / wavelength + phase;
                let y = amplitude * angle.sin();
                let slope = slope_k * angle.cos();
                let dx = point_x - x;
                let dy = (point_y - y) / (1.0 + slope * slope).sqrt();
                let dist = (dx * dx + dy * dy).sqrt();
                played = (half + 0.7 - dist).clamp(0.0, 1.0);
            }

            let mut track = 0.0f32;
            if track_start < wf - half && point_x >= track_start - half - 2.0 {
                let x = point_x.clamp(track_start, wf - half);
                let dx = point_x - x;
                let dist = (dx * dx + point_y * point_y).sqrt();
                track = (half + 0.7 - dist).clamp(0.0, 1.0);
            }

            let pixel = if played >= track && played > 0.0 {
                Rgba8Pixel {
                    r: active_rgb[0],
                    g: active_rgb[1],
                    b: active_rgb[2],
                    a: (played * 255.0).round() as u8,
                }
            } else if track > 0.0 {
                Rgba8Pixel {
                    r: track_rgb[0],
                    g: track_rgb[1],
                    b: track_rgb[2],
                    a: (track * 255.0).round() as u8,
                }
            } else {
                Rgba8Pixel {
                    r: 0,
                    g: 0,
                    b: 0,
                    a: 0,
                }
            };
            pixels[row_offset + px] = pixel;
        }
    }

    Image::from_rgba8(buffer)
}
