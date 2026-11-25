use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use reqwest::Client;
use serde::Deserialize;

use crate::api::{Track, normalize_track_id};

const API_BASE: &str = "https://slopless.art";
pub const AI_ARTIST_THRESHOLD: f64 = 0.05;
pub const AI_TRACK_THRESHOLD: f64 = 0.5;

static BUILTIN_ARTISTS: &[u8] = include_bytes!("../data/slopless_artists.bin");

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct YandexAiTrack {
    pub id: u64,
    #[serde(default)]
    pub status: i32,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ArtistData {
    pub id: u64,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub ai_tracks: u64,
    #[serde(default)]
    pub total_tracks: u64,
    #[serde(default)]
    pub yandex_ai_tracks: u64,
    #[serde(default)]
    pub yandex_checked_tracks: u64,
    #[serde(default)]
    pub yandex_ai_track_list: Vec<YandexAiTrack>,
}

impl ArtistData {
    pub fn is_ai(&self) -> bool {
        let slopless = self.total_tracks > 0
            && (self.ai_tracks as f64) / (self.total_tracks as f64) >= AI_ARTIST_THRESHOLD;
        let yandex = self.yandex_checked_tracks > 0
            && (self.yandex_ai_tracks as f64) / (self.yandex_checked_tracks as f64)
                >= AI_ARTIST_THRESHOLD;
        slopless || yandex
    }
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrackData {
    pub id: u64,
    pub score: Option<f64>,
    pub score_yandex: Option<i32>,
}

impl TrackData {
    pub fn is_ai(&self) -> bool {
        let slopless = self.score.is_some_and(|s| s > AI_TRACK_THRESHOLD);
        let yandex = self.score_yandex.is_some_and(|s| (1..=3).contains(&s));
        slopless || yandex
    }

    pub fn is_yandex_ai(&self) -> bool {
        self.score_yandex.is_some_and(|s| (1..=3).contains(&s))
    }
}

#[derive(Default)]
struct SloplessCache {
    artists: HashMap<u32, Option<bool>>,
    tracks: HashMap<u64, Option<TrackData>>,
}

fn cache() -> &'static Mutex<SloplessCache> {
    static CACHE: OnceLock<Mutex<SloplessCache>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(SloplessCache::default()))
}

/// Бинарный поиск ID артиста во встроенной базе Slopless
pub fn is_builtin_ai_artist(artist_id: u32) -> bool {
    let count = BUILTIN_ARTISTS.len() / 4;
    let mut low = 0usize;
    let mut high = count;
    while low < high {
        let mid = low + (high - low) / 2;
        let offset = mid * 4;
        let val = u32::from_le_bytes([
            BUILTIN_ARTISTS[offset],
            BUILTIN_ARTISTS[offset + 1],
            BUILTIN_ARTISTS[offset + 2],
            BUILTIN_ARTISTS[offset + 3],
        ]);
        match val.cmp(&artist_id) {
            std::cmp::Ordering::Less => low = mid + 1,
            std::cmp::Ordering::Greater => high = mid,
            std::cmp::Ordering::Equal => return true,
        }
    }
    false
}

pub fn is_builtin_ai_artist_str(artist_id: &str) -> bool {
    artist_id
        .trim()
        .parse::<u32>()
        .is_ok_and(is_builtin_ai_artist)
}

fn track_artist_ids(track: &Track) -> Vec<u32> {
    let mut out = Vec::new();
    if let Some(ref id) = track.artist_id
        && let Ok(n) = id.trim().parse::<u32>()
    {
        out.push(n);
    }
    for (id, _) in &track.artist_links {
        if let Ok(n) = id.trim().parse::<u32>()
            && !out.contains(&n)
        {
            out.push(n);
        }
    }
    out
}

/// Мгновенная проверка трека без сетевых запросов
pub fn is_track_ai_fast(track: &Track) -> bool {
    let tid = normalize_track_id(&track.id).parse::<u64>().ok();
    let artist_ids = track_artist_ids(track);

    if let Ok(guard) = cache().lock() {
        if let Some(id) = tid
            && let Some(Some(td)) = guard.tracks.get(&id)
            && td.is_ai()
        {
            return true;
        }
        for &aid in &artist_ids {
            if let Some(Some(is_ai)) = guard.artists.get(&aid) {
                if *is_ai {
                    return true;
                }
            } else if is_builtin_ai_artist(aid) {
                return true;
            }
        }
    } else {
        for &aid in &artist_ids {
            if is_builtin_ai_artist(aid) {
                return true;
            }
        }
    }
    false
}

/// Проверка, нужно ли применять автоматическое действие (пропуск/дизлайк) с учётом `strict_tracks`.
pub fn should_take_action_fast(track: &Track, strict_tracks: bool) -> bool {
    if !strict_tracks {
        return track.is_ai || is_track_ai_fast(track);
    }
    let Some(tid) = normalize_track_id(&track.id).parse::<u64>().ok() else {
        return false;
    };
    if let Ok(guard) = cache().lock()
        && let Some(Some(td)) = guard.tracks.get(&tid)
    {
        return td.is_ai();
    }
    false
}

async fn fetch_artist(http: &Client, artist_id: u32) -> Option<bool> {
    if let Ok(guard) = cache().lock()
        && let Some(&cached) = guard.artists.get(&artist_id)
    {
        return cached;
    }

    let url = format!("{API_BASE}/api/artist/{artist_id}");
    let res = http
        .get(&url)
        .timeout(Duration::from_secs(4))
        .send()
        .await
        .ok()?;
    if !res.status().is_success() {
        if let Ok(mut guard) = cache().lock() {
            guard.artists.insert(artist_id, None);
        }
        return None;
    }
    let data: ArtistData = res.json().await.ok()?;
    let is_ai = data.is_ai() || is_builtin_ai_artist(artist_id);
    if let Ok(mut guard) = cache().lock() {
        guard.artists.insert(artist_id, Some(is_ai));
        for yt in &data.yandex_ai_track_list {
            if (1..=3).contains(&yt.status) {
                guard.tracks.entry(yt.id).or_insert(Some(TrackData {
                    id: yt.id,
                    score: None,
                    score_yandex: Some(yt.status),
                }));
            }
        }
    }
    Some(is_ai)
}

async fn fetch_track(http: &Client, track_id: u64) -> Option<TrackData> {
    if let Ok(guard) = cache().lock()
        && let Some(cached) = guard.tracks.get(&track_id)
    {
        return cached.clone();
    }

    let url = format!("{API_BASE}/api/track/{track_id}");
    let res = http
        .get(&url)
        .timeout(Duration::from_secs(4))
        .send()
        .await
        .ok()?;
    if !res.status().is_success() {
        if let Ok(mut guard) = cache().lock() {
            guard.tracks.insert(track_id, None);
        }
        return None;
    }
    let data: TrackData = res.json().await.ok()?;
    if let Ok(mut guard) = cache().lock() {
        guard.tracks.insert(track_id, Some(data.clone()));
    }
    Some(data)
}

/// Онлайн проверка одного трека через `slopless.art` (возвращает `(is_ai_label, should_take_action)`).
pub async fn check_track_online(
    http: &Client,
    track: &Track,
    strict_tracks: bool,
) -> (bool, bool) {
    let artist_ids = track_artist_ids(track);
    let mut any_artist_ai = artist_ids.iter().copied().any(is_builtin_ai_artist);

    for &aid in &artist_ids {
        if let Some(ai) = fetch_artist(http, aid).await
            && ai
        {
            any_artist_ai = true;
        }
    }

    let tid = normalize_track_id(&track.id).parse::<u64>().ok();
    let track_data = if any_artist_ai || strict_tracks {
        match tid {
            Some(id) => fetch_track(http, id).await,
            None => None,
        }
    } else {
        tid.and_then(|id| {
            cache()
                .lock()
                .ok()
                .and_then(|g| g.tracks.get(&id).cloned().flatten())
        })
    };

    let track_ai = track_data.as_ref().is_some_and(TrackData::is_ai);
    let yandex_ai = track_data.as_ref().is_some_and(TrackData::is_yandex_ai);
    let is_ai_label = any_artist_ai || track_ai;
    let should_act = if yandex_ai {
        true
    } else if any_artist_ai {
        !strict_tracks || track_ai || track_data.is_none()
    } else {
        track_ai
    };

    (is_ai_label, should_act)
}

/// Пакетная проверка списка треков через `slopless.art`: возвращает ID треков, которые оказались ИИ.
pub async fn check_tracks_batch(http: &Client, tracks: &[Track]) -> HashSet<String> {
    let mut ai_track_ids = HashSet::new();
    let mut unknown_artists = Vec::new();
    let mut seen_artists = HashSet::new();

    for t in tracks {
        if t.is_ai || is_track_ai_fast(t) {
            ai_track_ids.insert(t.id.clone());
        }
        for aid in track_artist_ids(t) {
            if seen_artists.insert(aid) {
                let known = cache()
                    .lock()
                    .ok()
                    .is_some_and(|g| g.artists.contains_key(&aid));
                if !known && !is_builtin_ai_artist(aid) {
                    unknown_artists.push(aid);
                }
            }
        }
    }

    // Ограничиваем количество новых сетевых запросов за один батч, чтобы не перегружать API
    for chunk in unknown_artists.into_iter().take(24).collect::<Vec<_>>().chunks(6) {
        let mut set = tokio::task::JoinSet::new();
        for &aid in chunk {
            let client = http.clone();
            set.spawn(async move {
                let _ = fetch_artist(&client, aid).await;
            });
        }
        while set.join_next().await.is_some() {}
    }

    for t in tracks {
        if is_track_ai_fast(t) {
            ai_track_ids.insert(t.id.clone());
        }
    }

    ai_track_ids
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builtin_binary_db_is_sorted_and_finds_known_ai_artists() {
        assert_eq!(BUILTIN_ARTISTS.len() % 4, 0);
        let count = BUILTIN_ARTISTS.len() / 4;
        assert_eq!(count, 140_994);

        // Проверим первые и последние ID из slopless/data/yandex_music.json
        assert!(is_builtin_ai_artist(544));
        assert!(is_builtin_ai_artist(3134));
        assert!(is_builtin_ai_artist(25_919_284));
        assert!(!is_builtin_ai_artist(1));
        assert!(!is_builtin_ai_artist(545));
    }
}
