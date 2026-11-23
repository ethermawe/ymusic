use ymusic_setup::payload;

use std::path::PathBuf;

fn print_usage() {
    eprintln!(
        "Usage: ymusic-packer --input <dist_dir> --stub <setup_stub_exe> --output <out_exe> --version <semver>"
    );
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut input: Option<PathBuf> = None;
    let mut stub: Option<PathBuf> = None;
    let mut output: Option<PathBuf> = None;
    let mut version: Option<String> = None;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--input" if i + 1 < args.len() => {
                i += 1;
                input = Some(PathBuf::from(&args[i]));
            }
            "--stub" if i + 1 < args.len() => {
                i += 1;
                stub = Some(PathBuf::from(&args[i]));
            }
            "--output" if i + 1 < args.len() => {
                i += 1;
                output = Some(PathBuf::from(&args[i]));
            }
            "--version" if i + 1 < args.len() => {
                i += 1;
                version = Some(args[i].clone());
            }
            _ => {
                print_usage();
                std::process::exit(2);
            }
        }
        i += 1;
    }

    let (Some(input), Some(stub), Some(output), Some(version)) = (input, stub, output, version)
    else {
        print_usage();
        std::process::exit(2);
    };

    match payload::write_packed_installer(&stub, &input, &output, &version) {
        Ok(meta) => {
            println!(
                "Packed {} files ({} bytes uncompressed) for v{} -> {}",
                meta.file_count,
                meta.total_bytes,
                meta.version,
                output.display()
            );
        }
        Err(e) => {
            eprintln!("Pack error: {e}");
            std::process::exit(1);
        }
    }
}
