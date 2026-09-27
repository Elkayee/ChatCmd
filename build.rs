use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
    time::{SystemTime, UNIX_EPOCH},
};

fn main() {
    println!("cargo:rerun-if-env-changed=CHATCMD_BUILD_VERSION");
    println!("cargo:rerun-if-changed=assets/icons/favicon.ico");

    let version = std::env::var("CHATCMD_BUILD_VERSION")
        .or_else(|_| std::env::var("CARGO_PKG_VERSION"))
        .unwrap_or_else(|_| "0.1.0".to_owned());
    println!("cargo:rustc-env=CHATCMD_BUILD_VERSION={version}");
    let commit = git_commit().unwrap_or_else(|| "unknown".to_owned());
    println!("cargo:rustc-env=CHATCMD_BUILD_COMMIT={commit}");

    if std::env::var_os("CARGO_FEATURE_EMBEDDED_WEB").is_some() {
        verify_embedded_web();
    }

    #[cfg(windows)]
    {
        let mut resource = winres::WindowsResource::new();
        resource.set_icon("assets/icons/favicon.ico");
        resource.set("ProductName", "ChatCMD");
        resource.set("FileDescription", "ChatCMD");
        resource.set("FileVersion", &version);
        resource.set("ProductVersion", &version);
        resource.compile().expect("compile Windows resources");
    }
}

fn git_commit() -> Option<String> {
    let output = Command::new("git")
        .args(["rev-parse", "--short=12", "HEAD"])
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

fn verify_embedded_web() {
    let root = PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").expect("manifest directory"));
    let dist_index = root.join("web/dist/index.html");
    let dist_modified = modified(&dist_index).unwrap_or_else(|| {
        panic!("web/dist/index.html is missing; run `npm run build` in web before an embedded-web build")
    });
    for relative in [
        "web/src",
        "web/index.html",
        "web/package.json",
        "web/package-lock.json",
        "web/tsconfig.json",
        "web/vite.config.ts",
    ] {
        let path = root.join(relative);
        println!("cargo:rerun-if-changed={}", path.display());
        if newest_modified(&path).is_some_and(|source_modified| source_modified > dist_modified) {
            panic!(
                "frontend source {} is newer than web/dist/index.html; run `npm run build` in web",
                path.display()
            );
        }
    }
    let identity = format!(
        "{}-{}",
        fs::metadata(&dist_index)
            .map(|value| value.len())
            .unwrap_or(0),
        dist_modified
            .duration_since(UNIX_EPOCH)
            .map(|value| value.as_nanos())
            .unwrap_or(0)
    );
    println!("cargo:rustc-env=CHATCMD_FRONTEND_BUNDLE_ID={identity}");
}

fn newest_modified(path: &Path) -> Option<SystemTime> {
    if path.is_file() {
        return modified(path);
    }
    fs::read_dir(path)
        .ok()?
        .filter_map(Result::ok)
        .filter_map(|entry| newest_modified(&entry.path()))
        .max()
}

fn modified(path: &Path) -> Option<SystemTime> {
    fs::metadata(path).ok()?.modified().ok()
}
