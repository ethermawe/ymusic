use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use tokio::runtime::Handle;
use tokio::sync::mpsc;
use zbus::interface;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{ObjectPath, Value};

const PATH: &str = "/org/mpris/MediaPlayer2";
const BUS_NAME: &str = "org.mpris.MediaPlayer2.ymusic";

#[derive(Clone, Debug)]
pub enum Action {
    Play,
    Pause,
    Toggle,
    Stop,
    Next,
    Prev,
    SeekRelative(f64),
    SeekAbsolute(f64),
    SetVolume(f32),
    Quit,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Meta {
    pub id: String,
    pub title: String,
    pub artists: String,
    pub duration_us: i64,
    pub cover_url: Option<String>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Status {
    #[default]
    Stopped,
    Playing,
    Paused,
}

impl Status {
    fn as_str(self) -> &'static str {
        match self {
            Self::Playing => "Playing",
            Self::Paused => "Paused",
            Self::Stopped => "Stopped",
        }
    }
}

#[derive(Default)]
struct Shared {
    status: Status,
    meta: Option<Meta>,
    position_us: i64,
    volume: f64,
}

enum Notify {
    MetadataAndStatus,
    Status,
    Volume,
}

pub struct Mpris {
    shared: Arc<Mutex<Shared>>,
    tx: mpsc::UnboundedSender<Notify>,
}

impl Mpris {
    pub fn spawn(rt: &Handle, on_action: impl Fn(Action) + Send + Sync + 'static) -> Self {
        let shared = Arc::new(Mutex::new(Shared {
            volume: 0.7,
            ..Shared::default()
        }));
        let (tx, rx) = mpsc::unbounded_channel();
        let shared_bg = shared.clone();
        let on_action = Arc::new(on_action);

        rt.spawn(async move {
            let _ = serve(shared_bg, on_action, rx).await;
        });

        Self { shared, tx }
    }

    pub fn set_track(&self, meta: Meta, status: Status) {
        let mut s = self.shared.lock().unwrap();
        s.meta = Some(meta);
        s.status = status;
        s.position_us = 0;
        drop(s);
        let _ = self.tx.send(Notify::MetadataAndStatus);
    }

    pub fn set_status(&self, status: Status, position_secs: f64) {
        let mut s = self.shared.lock().unwrap();
        s.position_us = (position_secs * 1_000_000.0) as i64;
        if s.status != status {
            s.status = status;
            drop(s);
            let _ = self.tx.send(Notify::Status);
        }
    }

    pub fn set_stopped(&self) {
        let mut s = self.shared.lock().unwrap();
        s.meta = None;
        s.status = Status::Stopped;
        s.position_us = 0;
        drop(s);
        let _ = self.tx.send(Notify::MetadataAndStatus);
    }

    pub fn set_volume(&self, volume: f32) {
        let mut s = self.shared.lock().unwrap();
        s.volume = f64::from(volume.clamp(0.0, 1.0));
        drop(s);
        let _ = self.tx.send(Notify::Volume);
    }
}

async fn serve(
    shared: Arc<Mutex<Shared>>,
    on_action: Arc<dyn Fn(Action) + Send + Sync>,
    mut rx: mpsc::UnboundedReceiver<Notify>,
) -> zbus::Result<()> {
    let root = Root {
        on_action: on_action.clone(),
    };
    let player = PlayerIface { shared, on_action };

    let conn = zbus::connection::Builder::session()?
        .name(BUS_NAME)?
        .serve_at(PATH, root)?
        .serve_at(PATH, player)?
        .build()
        .await?;

    let iface_ref = conn.object_server().interface::<_, PlayerIface>(PATH).await?;

    while let Some(note) = rx.recv().await {
        let iface = iface_ref.get().await;
        let emitter = iface_ref.signal_emitter();
        match note {
            Notify::MetadataAndStatus => {
                let _ = iface.metadata_changed(emitter).await;
                let _ = iface.playback_status_changed(emitter).await;
                let _ = iface.can_play_changed(emitter).await;
                let _ = iface.can_pause_changed(emitter).await;
                let _ = iface.can_seek_changed(emitter).await;
                let _ = iface.can_go_next_changed(emitter).await;
                let _ = iface.can_go_previous_changed(emitter).await;
            }
            Notify::Status => {
                let _ = iface.playback_status_changed(emitter).await;
            }
            Notify::Volume => {
                let _ = iface.volume_changed(emitter).await;
            }
        }
    }

    Ok(())
}

struct Root {
    on_action: Arc<dyn Fn(Action) + Send + Sync>,
}

#[interface(name = "org.mpris.MediaPlayer2")]
impl Root {
    fn raise(&self) {}

    fn quit(&self) {
        (self.on_action)(Action::Quit);
    }

    #[zbus(property)]
    fn can_quit(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn can_raise(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn has_track_list(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn identity(&self) -> &'static str {
        "ymusic"
    }

    #[zbus(property)]
    fn desktop_entry(&self) -> &'static str {
        "ymusic"
    }

    #[zbus(property)]
    fn supported_uri_schemes(&self) -> Vec<&'static str> {
        vec![]
    }

    #[zbus(property)]
    fn supported_mime_types(&self) -> Vec<&'static str> {
        vec!["audio/mpeg"]
    }
}

struct PlayerIface {
    shared: Arc<Mutex<Shared>>,
    on_action: Arc<dyn Fn(Action) + Send + Sync>,
}

#[interface(name = "org.mpris.MediaPlayer2.Player")]
impl PlayerIface {
    fn next(&self) {
        (self.on_action)(Action::Next);
    }

    fn previous(&self) {
        (self.on_action)(Action::Prev);
    }

    fn pause(&self) {
        (self.on_action)(Action::Pause);
    }

    fn play_pause(&self) {
        (self.on_action)(Action::Toggle);
    }

    fn stop(&self) {
        (self.on_action)(Action::Stop);
    }

    fn play(&self) {
        (self.on_action)(Action::Play);
    }

    async fn seek(
        &self,
        offset_us: i64,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) {
        let new_pos_us = {
            let mut s = self.shared.lock().unwrap();
            s.position_us = (s.position_us + offset_us).max(0);
            s.position_us
        };
        (self.on_action)(Action::SeekRelative(offset_us as f64 / 1_000_000.0));
        let _ = Self::seeked(&emitter, new_pos_us).await;
    }

    async fn set_position(
        &self,
        _track_id: ObjectPath<'_>,
        position_us: i64,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) {
        let pos_us = position_us.max(0);
        self.shared.lock().unwrap().position_us = pos_us;
        (self.on_action)(Action::SeekAbsolute(pos_us as f64 / 1_000_000.0));
        let _ = Self::seeked(&emitter, pos_us).await;
    }

    fn open_uri(&self, _uri: &str) {}

    #[zbus(signal)]
    async fn seeked(emitter: &SignalEmitter<'_>, position: i64) -> zbus::Result<()>;

    #[zbus(property)]
    fn playback_status(&self) -> &'static str {
        self.shared.lock().unwrap().status.as_str()
    }

    #[zbus(property)]
    fn rate(&self) -> f64 {
        1.0
    }

    #[zbus(property)]
    fn minimum_rate(&self) -> f64 {
        1.0
    }

    #[zbus(property)]
    fn maximum_rate(&self) -> f64 {
        1.0
    }

    #[zbus(property)]
    fn volume(&self) -> f64 {
        self.shared.lock().unwrap().volume
    }

    #[zbus(property)]
    fn set_volume(&self, value: f64) {
        let v = value.clamp(0.0, 1.0);
        self.shared.lock().unwrap().volume = v;
        (self.on_action)(Action::SetVolume(v as f32));
    }

    #[zbus(property(emits_changed_signal = "false"))]
    fn position(&self) -> i64 {
        self.shared.lock().unwrap().position_us
    }

    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        self.shared.lock().unwrap().meta.is_some()
    }

    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        self.shared.lock().unwrap().meta.is_some()
    }

    #[zbus(property)]
    fn can_play(&self) -> bool {
        self.shared.lock().unwrap().meta.is_some()
    }

    #[zbus(property)]
    fn can_pause(&self) -> bool {
        self.shared.lock().unwrap().meta.is_some()
    }

    #[zbus(property)]
    fn can_seek(&self) -> bool {
        self.shared.lock().unwrap().meta.is_some()
    }

    #[zbus(property)]
    fn can_control(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn metadata(&self) -> HashMap<&'static str, Value<'static>> {
        let s = self.shared.lock().unwrap();
        let mut map = HashMap::new();
        let Some(meta) = &s.meta else {
            return map;
        };
        let path_str = format!(
            "/org/mpris/MediaPlayer2/Track/{}",
            meta.id
                .chars()
                .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
                .collect::<String>()
        );
        if let Ok(path) = ObjectPath::try_from(path_str) {
            map.insert("mpris:trackid", Value::from(path));
        }
        map.insert("xesam:title", Value::from(meta.title.clone()));
        let artists: Vec<String> = if meta.artists.is_empty() {
            vec![]
        } else {
            meta.artists.split(", ").map(str::to_string).collect()
        };
        map.insert("xesam:artist", Value::from(artists));
        map.insert("mpris:length", Value::from(meta.duration_us));
        if let Some(url) = &meta.cover_url {
            map.insert("mpris:artUrl", Value::from(url.clone()));
        }
        map
    }
}
