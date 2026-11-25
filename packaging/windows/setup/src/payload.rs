use std::fs::{self, File};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::{Component, Path, PathBuf};

use serde::{Deserialize, Serialize};

pub const MAGIC: &[u8; 8] = b"YMPACK01";
const TRAILER_FIXED_LEN: u64 = 4 + 8 + 8; // meta_len (u32) + payload_len (u64) + magic (8)

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackMetadata {
    pub version: String,
    pub file_count: u64,
    pub total_bytes: u64,
}

#[derive(Debug, Clone)]
pub struct EmbeddedPayload {
    pub offset: u64,
    pub len: u64,
    pub metadata: PackMetadata,
}

pub fn read_embedded_payload(exe_path: &Path) -> io::Result<Option<EmbeddedPayload>> {
    let mut file = File::open(exe_path)?;
    let total_len = file.metadata()?.len();
    if total_len < TRAILER_FIXED_LEN {
        return Ok(None);
    }

    file.seek(SeekFrom::End(-(TRAILER_FIXED_LEN as i64)))?;
    let mut footer = [0u8; TRAILER_FIXED_LEN as usize];
    file.read_exact(&mut footer)?;

    if &footer[12..20] != MAGIC {
        return Ok(None);
    }

    let meta_len = u32::from_le_bytes(footer[0..4].try_into().unwrap()) as u64;
    let payload_len = u64::from_le_bytes(footer[4..12].try_into().unwrap());

    if meta_len == 0 || meta_len > 1024 * 1024 || payload_len + meta_len + TRAILER_FIXED_LEN > total_len {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "Corrupted installer payload trailer",
        ));
    }

    let meta_offset = total_len - TRAILER_FIXED_LEN - meta_len;
    let payload_offset = meta_offset - payload_len;

    file.seek(SeekFrom::Start(meta_offset))?;
    let mut meta_bytes = vec![0u8; meta_len as usize];
    file.read_exact(&mut meta_bytes)?;

    let metadata: PackMetadata = serde_json::from_slice(&meta_bytes)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    Ok(Some(EmbeddedPayload {
        offset: payload_offset,
        len: payload_len,
        metadata,
    }))
}

pub fn sanitize_rel_path(rel: &Path) -> Option<PathBuf> {
    let mut clean = PathBuf::new();
    for comp in rel.components() {
        match comp {
            Component::Normal(part) => clean.push(part),
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => return None,
        }
    }
    if clean.as_os_str().is_empty() {
        None
    } else {
        Some(clean)
    }
}

pub fn extract_payload<F>(
    exe_path: &Path,
    payload: &EmbeddedPayload,
    dest_dir: &Path,
    mut on_progress: F,
) -> io::Result<()>
where
    F: FnMut(u64, u64, &str),
{
    fs::create_dir_all(dest_dir)?;

    let mut file = File::open(exe_path)?;
    file.seek(SeekFrom::Start(payload.offset))?;

    let limited = file.take(payload.len);
    let decoder = zstd::stream::read::Decoder::new(limited)?;
    let mut archive = tar::Archive::new(decoder);

    let mut extracted_files: u64 = 0;
    let total_files = payload.metadata.file_count.max(1);

    for entry_res in archive.entries()? {
        let mut entry = entry_res?;
        let rel_path = entry.path()?.into_owned();
        let Some(clean_rel) = sanitize_rel_path(&rel_path) else {
            continue;
        };

        let target_path = dest_dir.join(&clean_rel);
        let entry_type = entry.header().entry_type();

        if entry_type.is_dir() {
            fs::create_dir_all(&target_path)?;
            continue;
        }
        if !entry_type.is_file() {
            continue;
        }

        if let Some(parent) = target_path.parent() {
            fs::create_dir_all(parent)?;
        }

        let mut out = create_file_with_retry(&target_path)?;
        io::copy(&mut entry, &mut out)?;
        out.flush()?;
        drop(out);

        #[cfg(unix)]
        if let Ok(mode) = entry.header().mode() {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&target_path, fs::Permissions::from_mode(mode));
        }

        extracted_files += 1;
        let name = clean_rel
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("file");
        on_progress(extracted_files, total_files, name);
    }

    Ok(())
}

fn create_file_with_retry(path: &Path) -> io::Result<File> {
    let mut last_err = None;
    for attempt in 0..15 {
        match File::create(path) {
            Ok(f) => return Ok(f),
            Err(e) => {
                last_err = Some(e);
                if attempt < 14 {
                    std::thread::sleep(std::time::Duration::from_millis(200));
                }
            }
        }
    }
    Err(last_err.unwrap())
}

pub fn write_packed_installer(
    stub_path: &Path,
    input_dir: &Path,
    output_path: &Path,
    version: &str,
) -> io::Result<PackMetadata> {
    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent)?;
    }

    let mut stub_bytes = fs::read(stub_path)?;
    if let Ok(Some(existing)) = read_embedded_payload(stub_path) {
        stub_bytes.truncate(existing.offset as usize);
    }

    let mut files = Vec::new();
    collect_files_sorted(input_dir, input_dir, &mut files)?;

    let mut total_bytes: u64 = 0;
    let file_count = files.len() as u64;

    let mut compressed_payload: Vec<u8> = Vec::with_capacity(16 * 1024 * 1024);
    {
        let encoder = zstd::stream::write::Encoder::new(&mut compressed_payload, 19)?;
        let mut tar_builder = tar::Builder::new(encoder.auto_finish());

        for (rel, abs) in &files {
            let meta = fs::metadata(abs)?;
            total_bytes += meta.len();
            tar_builder.append_path_with_name(abs, rel)?;
        }
        tar_builder.finish()?;
    }

    let metadata = PackMetadata {
        version: version.trim_start_matches('v').to_string(),
        file_count,
        total_bytes,
    };
    let meta_json = serde_json::to_vec(&metadata)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    let mut out = File::create(output_path)?;
    out.write_all(&stub_bytes)?;
    out.write_all(&compressed_payload)?;
    out.write_all(&meta_json)?;
    out.write_all(&(meta_json.len() as u32).to_le_bytes())?;
    out.write_all(&(compressed_payload.len() as u64).to_le_bytes())?;
    out.write_all(MAGIC)?;
    out.flush()?;

    Ok(metadata)
}

fn collect_files_sorted(
    root: &Path,
    dir: &Path,
    out: &mut Vec<(PathBuf, PathBuf)>,
) -> io::Result<()> {
    let mut entries: Vec<_> = fs::read_dir(dir)?.collect::<Result<Vec<_>, _>>()?;
    entries.sort_by_key(|e| e.file_name());

    for entry in entries {
        let abs = entry.path();
        let ft = entry.file_type()?;
        if ft.is_dir() {
            collect_files_sorted(root, &abs, out)?;
        } else if ft.is_file() {
            let rel = abs
                .strip_prefix(root)
                .map_err(|e| io::Error::new(io::ErrorKind::Other, e))?
                .to_path_buf();
            out.push((rel, abs));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "ymusic-setup-test-{}-{}-{}",
            std::process::id(),
            name,
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn sanitize_rejects_traversal() {
        assert!(sanitize_rel_path(Path::new("../evil.txt")).is_none());
        assert!(sanitize_rel_path(Path::new("a/../../evil.txt")).is_none());
        assert!(sanitize_rel_path(Path::new("/abs/path.txt")).is_none());
        assert_eq!(
            sanitize_rel_path(Path::new("./sub/file.dll")),
            Some(PathBuf::from("sub/file.dll"))
        );
    }

    #[test]
    fn pack_and_extract_roundtrip() {
        let root = temp_dir("roundtrip");
        let stub = root.join("stub.bin");
        let src = root.join("src");
        let packed = root.join("setup.exe");
        let dst = root.join("dst");

        fs::write(&stub, b"STUBPEHEADER0123456789").unwrap();
        fs::create_dir_all(src.join("qml")).unwrap();
        fs::write(src.join("ymusic.exe"), b"binary-data-12345").unwrap();
        fs::write(src.join("qml/Main.qml"), b"import QtQuick\nItem {}\n").unwrap();

        let meta = write_packed_installer(&stub, &src, &packed, "v0.3.0").unwrap();
        assert_eq!(meta.version, "0.3.0");
        assert_eq!(meta.file_count, 2);

        let read_back = read_embedded_payload(&packed).unwrap().expect("payload missing");
        assert_eq!(read_back.offset, 22);
        assert_eq!(read_back.metadata.version, "0.3.0");

        let mut reported = Vec::new();
        extract_payload(&packed, &read_back, &dst, |done, total, name| {
            reported.push((done, total, name.to_string()));
        })
        .unwrap();

        assert_eq!(reported.len(), 2);
        assert_eq!(fs::read(dst.join("ymusic.exe")).unwrap(), b"binary-data-12345");
        assert_eq!(
            fs::read_to_string(dst.join("qml/Main.qml")).unwrap(),
            "import QtQuick\nItem {}\n"
        );
        assert!(read_embedded_payload(&stub).unwrap().is_none());

        let _ = fs::remove_dir_all(&root);
    }
}
