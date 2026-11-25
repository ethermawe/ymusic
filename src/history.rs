use std::fs;
use std::sync::Mutex;
use crate::api::Track;

const LIMIT: usize = 100;
static LOCK: Mutex<()> = Mutex::new(());

fn path() -> Option<std::path::PathBuf> {
    dirs::data_local_dir().map(|p| p.join("ymusic/history.json"))
}

pub fn load() -> Vec<Track> {
    path().and_then(|p| fs::read(p).ok())
        .and_then(|b| serde_json::from_slice::<Vec<Track>>(&b).ok())
        .map(|mut tracks| { tracks.truncate(LIMIT); tracks }).unwrap_or_default()
}

fn record_in(tracks: &mut Vec<Track>, track: Track) {
    tracks.retain(|t| t.id != track.id);
    tracks.insert(0, track);
    tracks.truncate(LIMIT);
}

pub fn record(track: Track) -> std::io::Result<Vec<Track>> {
    let _guard = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut tracks = load();
    record_in(&mut tracks, track);
    save(&tracks)?;
    Ok(tracks)
}

pub fn merge_remote(remote: Vec<Track>) -> std::io::Result<Vec<Track>> {
    let _guard = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let local = load();
    if remote.is_empty() {
        return Ok(local);
    }
    let mut merged = Vec::with_capacity(LIMIT);
    let mut seen = std::collections::HashSet::new();
    // Remote server history is authoritative for cross-device recency, followed by local-only entries
    for t in remote.into_iter().chain(local.into_iter()) {
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
    let _guard = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    save(&[])
}

#[cfg(test)]
mod tests {
    use super::*;
    fn track(id: &str) -> Track { Track {
        id: id.into(), title: id.into(), artists: String::new(), album_id: None,
        album_title: String::new(), artist_id: None, artist_links: Vec::new(), duration_ms: 1000, cover_uri: None, available: true,
        has_sync_lyrics: false, has_text_lyrics: false, r128_i: None, r128_tp: None, is_ai: false,
    } }
    #[test]
    fn history_is_recent_unique_and_bounded() {
        let mut tracks = Vec::new();
        for i in 0..120 { record_in(&mut tracks, track(&i.to_string())); }
        assert_eq!(tracks.len(), LIMIT);
        record_in(&mut tracks, track("90"));
        assert_eq!(tracks[0].id, "90");
        assert_eq!(tracks.iter().filter(|t| t.id == "90").count(), 1);
    }
}
