use crate::api::Track;
use parking_lot::Mutex;
use std::fs;

const LIMIT: usize = 100;
const SEARCH_HISTORY_LIMIT: usize = 15;
static LOCK: Mutex<()> = Mutex::new(());
static SEARCH_LOCK: Mutex<()> = Mutex::new(());

fn path() -> Option<std::path::PathBuf> {
    #[cfg(test)]
    {
        return Some(std::env::temp_dir().join("ymusic-unit-test-data/history.json"));
    }
    #[cfg(not(test))]
    {
        dirs::data_local_dir().map(|p| p.join("ymusic/history.json"))
    }
}

fn search_history_path() -> Option<std::path::PathBuf> {
    #[cfg(test)]
    {
        return Some(std::env::temp_dir().join("ymusic-unit-test-data/search_history.json"));
    }
    #[cfg(not(test))]
    {
        dirs::data_local_dir().map(|p| p.join("ymusic/search_history.json"))
    }
}

pub fn load_search_history() -> Vec<String> {
    let _guard = SEARCH_LOCK.lock();
    load_search_history_unlocked()
}

fn load_search_history_unlocked() -> Vec<String> {
    search_history_path()
        .and_then(|p| fs::read(p).ok())
        .and_then(|b| serde_json::from_slice::<Vec<String>>(&b).ok())
        .map(|items| {
            let mut deduped = Vec::with_capacity(SEARCH_HISTORY_LIMIT);
            for raw in items {
                let trimmed = raw.trim();
                if trimmed.is_empty() {
                    continue;
                }
                let lower = trimmed.to_lowercase();
                if !deduped
                    .iter()
                    .any(|existing: &String| existing.to_lowercase() == lower)
                {
                    deduped.push(trimmed.to_string());
                    if deduped.len() >= SEARCH_HISTORY_LIMIT {
                        break;
                    }
                }
            }
            deduped
        })
        .unwrap_or_default()
}

fn record_search_in(items: &mut Vec<String>, query: &str) {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return;
    }
    let needle = trimmed.to_lowercase();
    items.retain(|existing| existing.to_lowercase() != needle);
    items.insert(0, trimmed.to_string());
    items.truncate(SEARCH_HISTORY_LIMIT);
}

fn remove_search_in(items: &mut Vec<String>, query: &str) {
    let trimmed = query.trim();
    if trimmed.is_empty() {
        return;
    }
    let needle = trimmed.to_lowercase();
    items.retain(|existing| existing.to_lowercase() != needle);
}

fn save_search_history_unlocked(items: &[String]) -> std::io::Result<()> {
    let p = search_history_path().ok_or_else(|| std::io::Error::other("нет каталога данных"))?;
    fs::create_dir_all(p.parent().unwrap())?;
    let tmp = p.with_extension("json.tmp");
    fs::write(&tmp, serde_json::to_vec(items)?)?;
    fs::rename(tmp, p)
}

pub fn record_search_query(query: &str) -> Vec<String> {
    let _guard = SEARCH_LOCK.lock();
    let mut items = load_search_history_unlocked();
    record_search_in(&mut items, query);
    let _ = save_search_history_unlocked(&items);
    items
}

pub fn remove_search_query(query: &str) -> Vec<String> {
    let _guard = SEARCH_LOCK.lock();
    let mut items = load_search_history_unlocked();
    remove_search_in(&mut items, query);
    let _ = save_search_history_unlocked(&items);
    items
}

pub fn clear_search_history() -> Vec<String> {
    let _guard = SEARCH_LOCK.lock();
    let _ = save_search_history_unlocked(&[]);
    Vec::new()
}

pub fn load() -> Vec<Track> {
    path()
        .and_then(|p| fs::read(p).ok())
        .and_then(|b| serde_json::from_slice::<Vec<Track>>(&b).ok())
        .map(|mut tracks| {
            tracks.truncate(LIMIT);
            tracks
        })
        .unwrap_or_default()
}

fn record_in(tracks: &mut Vec<Track>, track: Track) {
    tracks.retain(|t| t.id != track.id);
    tracks.insert(0, track);
    tracks.truncate(LIMIT);
}

pub fn record(track: Track) -> std::io::Result<Vec<Track>> {
    let _guard = LOCK.lock();
    let mut tracks = load();
    record_in(&mut tracks, track);
    save(&tracks)?;
    Ok(tracks)
}

pub fn merge_remote(remote: Vec<Track>) -> std::io::Result<Vec<Track>> {
    let _guard = LOCK.lock();
    let local = load();
    if remote.is_empty() {
        return Ok(local);
    }
    let mut merged = Vec::with_capacity(LIMIT);
    let mut seen = std::collections::HashSet::new();
    // Remote server history is authoritative for cross-device recency, followed by local-only entries
    for t in remote.into_iter().chain(local) {
        if seen.insert(t.id.clone()) {
            merged.push(t);
            if merged.len() >= LIMIT {
                break;
            }
        }
    }
    save(&merged)?;
    Ok(merged)
}

fn save(tracks: &[Track]) -> std::io::Result<()> {
    let p = path().ok_or_else(|| std::io::Error::other("нет каталога данных"))?;
    fs::create_dir_all(p.parent().unwrap())?;
    let tmp = p.with_extension("json.tmp");
    fs::write(&tmp, serde_json::to_vec(tracks)?)?;
    fs::rename(tmp, p)
}

pub fn clear() -> std::io::Result<()> {
    let _guard = LOCK.lock();
    save(&[])
}

#[cfg(test)]
mod tests {
    use super::*;
    fn track(id: &str) -> Track {
        Track {
            id: id.into(),
            title: id.into(),
            artists: String::new(),
            album_id: None,
            album_title: String::new(),
            artist_id: None,
            artist_links: Vec::new(),
            duration_ms: 1000,
            cover_uri: None,
            available: true,
            has_sync_lyrics: false,
            has_text_lyrics: false,
            r128_i: None,
            r128_tp: None,
            is_ai: false,
        }
    }
    #[test]
    fn history_is_recent_unique_and_bounded() {
        let mut tracks = Vec::new();
        for i in 0..120 {
            record_in(&mut tracks, track(&i.to_string()));
        }
        assert_eq!(tracks.len(), LIMIT);
        record_in(&mut tracks, track("90"));
        assert_eq!(tracks[0].id, "90");
        assert_eq!(tracks.iter().filter(|t| t.id == "90").count(), 1);
    }

    #[test]
    fn search_history_deduplicates_unicode_bounds_and_removes() {
        let mut items = Vec::new();
        for i in 0..20 {
            record_search_in(&mut items, &format!("Запрос {i}"));
        }
        assert_eq!(items.len(), SEARCH_HISTORY_LIMIT);
        assert_eq!(items[0], "Запрос 19");

        record_search_in(&mut items, "  запрос 12 ");
        assert_eq!(items[0], "запрос 12");
        assert_eq!(
            items
                .iter()
                .filter(|s| s.to_lowercase() == "запрос 12")
                .count(),
            1
        );

        remove_search_in(&mut items, "ЗАПРОС 12");
        assert!(!items.iter().any(|s| s.to_lowercase() == "запрос 12"));
    }
}
