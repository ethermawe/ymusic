use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::time::Duration;

use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use tokio::sync::oneshot;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HookPoint {
    SearchResults,
    WaveNextBatch,
    QueueBeforeAdd,
    TrackBeforePlay,
    TrackAfterPlay,
    LyricsLoaded,
    PlaylistLoaded,
    AlbumLoaded,
    ScrobbleBefore,
}

impl HookPoint {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::SearchResults => "search_results",
            Self::WaveNextBatch => "wave_next_batch",
            Self::QueueBeforeAdd => "queue_before_add",
            Self::TrackBeforePlay => "track_before_play",
            Self::TrackAfterPlay => "track_after_play",
            Self::LyricsLoaded => "lyrics_loaded",
            Self::PlaylistLoaded => "playlist_loaded",
            Self::AlbumLoaded => "album_loaded",
            Self::ScrobbleBefore => "scrobble_before",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s.trim() {
            "search_results" => Some(Self::SearchResults),
            "wave_next_batch" => Some(Self::WaveNextBatch),
            "queue_before_add" => Some(Self::QueueBeforeAdd),
            "track_before_play" => Some(Self::TrackBeforePlay),
            "track_after_play" => Some(Self::TrackAfterPlay),
            "lyrics_loaded" => Some(Self::LyricsLoaded),
            "playlist_loaded" => Some(Self::PlaylistLoaded),
            "album_loaded" => Some(Self::AlbumLoaded),
            "scrobble_before" => Some(Self::ScrobbleBefore),
            _ => None,
        }
    }

    fn bit(self) -> u32 {
        1u32 << (self as u32)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum HookOutcome {
    Continue(serde_json::Value),
    Cancel { reason: String },
}

#[derive(Debug, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
enum HookResponseMsg {
    Continue {
        payload: serde_json::Value,
    },
    Cancel {
        #[serde(default)]
        reason: String,
    },
}

pub struct HookPipeline {
    subscribed_mask: AtomicU32,
    next_id: AtomicU64,
    timeout_ms: AtomicU64,
    pending: Mutex<HashMap<u64, oneshot::Sender<String>>>,
}

impl Default for HookPipeline {
    fn default() -> Self {
        Self::new(Duration::from_millis(150))
    }
}

impl HookPipeline {
    pub fn new(timeout: Duration) -> Self {
        Self {
            subscribed_mask: AtomicU32::new(0),
            next_id: AtomicU64::new(1),
            timeout_ms: AtomicU64::new(timeout.as_millis().max(10) as u64),
            pending: Mutex::new(HashMap::new()),
        }
    }

    pub fn set_timeout(&self, timeout: Duration) {
        self.timeout_ms
            .store(timeout.as_millis().max(10) as u64, Ordering::Relaxed);
    }

    pub fn timeout(&self) -> Duration {
        Duration::from_millis(self.timeout_ms.load(Ordering::Relaxed))
    }

    pub fn subscribe(&self, point: HookPoint, enabled: bool) {
        let bit = point.bit();
        if enabled {
            self.subscribed_mask.fetch_or(bit, Ordering::Release);
        } else {
            self.subscribed_mask.fetch_and(!bit, Ordering::Release);
        }
    }

    #[inline]
    pub fn has_subscribers(&self, point: HookPoint) -> bool {
        (self.subscribed_mask.load(Ordering::Acquire) & point.bit()) != 0
    }

    /// Resolves a pending hook request from the Qt/JS mod host.
    pub fn respond(&self, id: u64, response_json: String) -> bool {
        if let Some(tx) = self.pending.lock().remove(&id) {
            tx.send(response_json).is_ok()
        } else {
            false
        }
    }

    /// Runs a hook point. Zero-cost when no mod is subscribed to `point`.
    /// On timeout or invalid response JSON, returns `Continue(original_payload)` and invokes `emit_warning`.
    pub async fn run<FEmit, FWarn>(
        &self,
        point: HookPoint,
        payload: serde_json::Value,
        emit_request: FEmit,
        emit_warning: FWarn,
    ) -> HookOutcome
    where
        FEmit: FnOnce(serde_json::Value),
        FWarn: FnOnce(String),
    {
        if !self.has_subscribers(point) {
            return HookOutcome::Continue(payload);
        }

        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let (tx, rx) = oneshot::channel();
        self.pending.lock().insert(id, tx);

        let req = serde_json::json!({
            "type": "hook_request",
            "id": id,
            "point": point.as_str(),
            "payload": payload,
        });
        emit_request(req);

        let wait = self.timeout();
        match tokio::time::timeout(wait, rx).await {
            Ok(Ok(raw_json)) => match serde_json::from_str::<HookResponseMsg>(&raw_json) {
                Ok(HookResponseMsg::Continue { payload: next }) => {
                    if payload_shape_compatible(&payload, &next) {
                        HookOutcome::Continue(next)
                    } else {
                        emit_warning(format!(
                            "Хук '{}' (id={id}) вернул несовместимую схему payload — изменения проигнорированы",
                            point.as_str()
                        ));
                        HookOutcome::Continue(payload)
                    }
                }
                Ok(HookResponseMsg::Cancel { reason }) => HookOutcome::Cancel { reason },
                Err(err) => {
                    emit_warning(format!(
                        "Хук '{}' (id={id}) вернул невалидный JSON ({err}) — изменения проигнорированы",
                        point.as_str()
                    ));
                    HookOutcome::Continue(payload)
                }
            },
            Ok(Err(_)) => {
                self.pending.lock().remove(&id);
                emit_warning(format!(
                    "Канал ответа хука '{}' (id={id}) закрыт",
                    point.as_str()
                ));
                HookOutcome::Continue(payload)
            }
            Err(_) => {
                self.pending.lock().remove(&id);
                emit_warning(format!(
                    "Таймаут хука '{}' (id={id}, >{} мс) — применён исходный payload",
                    point.as_str(),
                    wait.as_millis()
                ));
                HookOutcome::Continue(payload)
            }
        }
    }
}

fn payload_shape_compatible(orig: &serde_json::Value, next: &serde_json::Value) -> bool {
    matches!(
        (orig, next),
        (serde_json::Value::Object(_), serde_json::Value::Object(_))
            | (serde_json::Value::Array(_), serde_json::Value::Array(_))
            | (serde_json::Value::Null, _)
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    #[tokio::test]
    async fn unsubscribed_hook_is_fast_noop() {
        let pipeline = HookPipeline::default();
        let mut emitted = false;
        let out = pipeline
            .run(
                HookPoint::SearchResults,
                serde_json::json!({"tracks": [1, 2]}),
                |_| emitted = true,
                |_| panic!("unexpected warning"),
            )
            .await;
        assert!(!emitted);
        assert_eq!(
            out,
            HookOutcome::Continue(serde_json::json!({"tracks": [1, 2]}))
        );
    }

    #[tokio::test]
    async fn chained_handlers_transform_payload_in_order() {
        let pipeline = Arc::new(HookPipeline::new(Duration::from_millis(200)));
        pipeline.subscribe(HookPoint::SearchResults, true);

        // Simulate two chained handlers (mod A appends 3, mod B filters out 1)
        let p = pipeline.clone();
        let out = pipeline
            .run(
                HookPoint::SearchResults,
                serde_json::json!({"tracks": [1, 2]}),
                move |req| {
                    let id = req["id"].as_u64().unwrap();
                    let mut arr = req["payload"]["tracks"].as_array().unwrap().clone();
                    // Handler 1
                    arr.push(serde_json::json!(3));
                    // Handler 2
                    arr.retain(|v| v.as_i64() != Some(1));
                    let resp = serde_json::json!({
                        "action": "continue",
                        "payload": { "tracks": arr }
                    });
                    assert!(p.respond(id, resp.to_string()));
                },
                |w| panic!("unexpected warning: {w}"),
            )
            .await;

        assert_eq!(
            out,
            HookOutcome::Continue(serde_json::json!({"tracks": [2, 3]}))
        );
    }

    #[tokio::test]
    async fn handler_can_cancel_with_reason() {
        let pipeline = Arc::new(HookPipeline::new(Duration::from_millis(200)));
        pipeline.subscribe(HookPoint::QueueBeforeAdd, true);

        let p = pipeline.clone();
        let out = pipeline
            .run(
                HookPoint::QueueBeforeAdd,
                serde_json::json!({"trackId": "42"}),
                move |req| {
                    let id = req["id"].as_u64().unwrap();
                    p.respond(
                        id,
                        r#"{"action":"cancel","reason":"duplicate"}"#.to_string(),
                    );
                },
                |w| panic!("unexpected warning: {w}"),
            )
            .await;

        assert_eq!(
            out,
            HookOutcome::Cancel {
                reason: "duplicate".into()
            }
        );
    }

    #[tokio::test]
    async fn timeout_returns_original_payload_and_warns() {
        let pipeline = HookPipeline::new(Duration::from_millis(30));
        pipeline.subscribe(HookPoint::WaveNextBatch, true);

        let mut warned = false;
        let orig = serde_json::json!({"tracks": ["a"]});
        let out = pipeline
            .run(
                HookPoint::WaveNextBatch,
                orig.clone(),
                |_req| { /* intentionally never respond */ },
                |_| warned = true,
            )
            .await;

        assert!(warned);
        assert_eq!(out, HookOutcome::Continue(orig));
    }

    #[tokio::test]
    async fn invalid_json_or_schema_returns_original_payload_and_warns() {
        let pipeline = Arc::new(HookPipeline::new(Duration::from_millis(200)));
        pipeline.subscribe(HookPoint::LyricsLoaded, true);

        let mut warned = false;
        let orig = serde_json::json!({"lines": []});
        let p = pipeline.clone();
        let out = pipeline
            .run(
                HookPoint::LyricsLoaded,
                orig.clone(),
                move |req| {
                    let id = req["id"].as_u64().unwrap();
                    p.respond(id, "{broken json".to_string());
                },
                |_| warned = true,
            )
            .await;

        assert!(warned);
        assert_eq!(out, HookOutcome::Continue(orig));
    }
}
