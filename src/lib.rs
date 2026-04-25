use zed_extension_api::{self as zed, DownloadedFileType, Result};

const SERVER_VERSION: &str = "v0.5.3";
const GITHUB_RELEASE_URL: &str = "https://github.com/jbearak/sight/releases/download";

struct SightExtension {
    cached_node_package_path: Option<String>,
}

impl zed::Extension for SightExtension {
    fn new() -> Self {
        Self {
            cached_node_package_path: None,
        }
    }

    fn language_server_command(
        &mut self,
        _language_server_id: &zed::LanguageServerId,
        _worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        let node_path = zed::node_binary_path()?;
        let server_script = self.get_node_server_path()?;

        Ok(zed::Command {
            command: node_path,
            args: vec![server_script, "--stdio".to_string()],
            env: Default::default(),
        })
    }
}

impl SightExtension {
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

            let download_url = format!("{}/{}/sight-server.js", GITHUB_RELEASE_URL, SERVER_VERSION);

            zed::download_file(
                &download_url,
                &server_script,
                DownloadedFileType::Uncompressed,
            )
            .map_err(|e| format!("Failed to download sight-server.js: {}", e))?;
        }

        // Make the script path absolute because the LSP process is started from the worktree root.
        let absolute_path = if let Ok(current_dir) = std::env::current_dir() {
            current_dir
                .join(&server_script)
                .to_string_lossy()
                .to_string()
        } else {
            server_script.clone()
        };

        self.cached_node_package_path = Some(absolute_path.clone());
        Ok(absolute_path)
    }
}

zed::register_extension!(SightExtension);
