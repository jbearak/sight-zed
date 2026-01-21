use zed_extension_api::{self as zed, DownloadedFileType, Result};

const SERVER_VERSION: &str = "v0.1.16";
const GITHUB_RELEASE_URL: &str = "https://github.com/jbearak/sight/releases/download";

struct SightExtension {
    cached_binary_path: Option<String>,
    cached_node_package_path: Option<String>,
}

impl zed::Extension for SightExtension {
    fn new() -> Self {
        Self {
            cached_binary_path: None,
            cached_node_package_path: None,
        }
    }

    fn language_server_command(
        &mut self,
        _language_server_id: &zed::LanguageServerId,
        _worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        let (platform, _arch) = zed::current_platform();

        // On Windows, the native binary doesn't work, so use Node.js instead
        if platform == zed::Os::Windows {
            let node_path = zed::node_binary_path()?;
            let server_script = self.get_node_server_path()?;
            Ok(zed::Command {
                command: node_path,
                args: vec![server_script, "--stdio".to_string()],
                env: Default::default(),
            })
        } else {
            let binary_path = self.get_server_binary_path()?;
            Ok(zed::Command {
                command: binary_path,
                args: vec!["--stdio".to_string()],
                env: Default::default(),
            })
        }
    }
}

impl SightExtension {
    fn get_server_binary_path(&mut self) -> Result<String> {
        if let Some(path) = &self.cached_binary_path {
            if std::fs::metadata(path).is_ok() {
                return Ok(path.clone());
            }
        }

        let (platform, arch) = zed::current_platform();
        let asset_name = match (platform, arch) {
            (zed::Os::Mac, zed::Architecture::Aarch64) => "sight-darwin-arm64",
            (zed::Os::Mac, zed::Architecture::X8664) => "sight-darwin-arm64", // Use ARM binary via Rosetta
            (zed::Os::Linux, zed::Architecture::Aarch64) => "sight-linux-arm64",
            (zed::Os::Linux, zed::Architecture::X8664) => "sight-linux-x64",
            (zed::Os::Windows, _) => "sight-windows-x64.exe",
            _ => return Err(format!("Unsupported platform: {:?} {:?}", platform, arch)),
        };

        // Use version-specific directory to ensure stable path resolution
        let version_dir = format!("sight-{}", SERVER_VERSION);
        let binary_path = format!("{}/{}", version_dir, asset_name);

        if std::fs::metadata(&binary_path).is_err() {
            std::fs::create_dir_all(&version_dir)
                .map_err(|e| format!("Failed to create directory: {}", e))?;

            // Download directly from GitHub releases URL (no API call needed)
            let download_url = format!("{}/{}/{}", GITHUB_RELEASE_URL, SERVER_VERSION, asset_name);

            zed::download_file(
                &download_url,
                &binary_path,
                DownloadedFileType::Uncompressed,
            )
            .map_err(|e| format!("Failed to download {}: {}", asset_name, e))?;

            zed::make_file_executable(&binary_path)?;
        }

        self.cached_binary_path = Some(binary_path.clone());
        Ok(binary_path)
    }

    fn get_node_server_path(&mut self) -> Result<String> {
        if let Some(path) = &self.cached_node_package_path {
            if std::fs::metadata(path).is_ok() {
                return Ok(path.clone());
            }
        }

        let version_dir = format!("sight-node-{}", SERVER_VERSION);
        let server_script = format!("{}/sight-server.js", version_dir);

        if std::fs::metadata(&server_script).is_err() {
            std::fs::create_dir_all(&version_dir)
                .map_err(|e| format!("Failed to create directory: {}", e))?;

            // Download directly from GitHub releases URL (no API call needed)
            let download_url = format!("{}/{}/sight-server.js", GITHUB_RELEASE_URL, SERVER_VERSION);

            zed::download_file(
                &download_url,
                &server_script,
                DownloadedFileType::Uncompressed,
            )
            .map_err(|e| format!("Failed to download sight-server.js: {}", e))?;
        }

        self.cached_node_package_path = Some(server_script.clone());
        Ok(server_script)
    }
}

zed::register_extension!(SightExtension);
