# Implementation Tasks

## Task 1: Rename Extension ID
- [x] 1.1 Update extension.toml: change `id` from "sight" to "stata"
- [x] 1.2 Update extension.toml: change `name` from "Sight - Stata Language Server" to "Stata"
- [x] 1.3 Update extension.toml: update `description` to "Stata language support for Zed"

## Task 2: Create Extension-Provided Tasks
- [x] 2.1 Create `languages/stata/tasks.json` with placeholder tasks that show install instructions
  - Include tasks: Send File, Send Statement, Include File, Include Statement, CD to Workspace, CD to File Directory
  - Use `"shell": { "program": "bash" }` for cross-platform compatibility
  - Error messages should include both macOS and Windows install commands

## Task 3: Create Tools Directory Structure
- [x] 3.1 Create `tools/send-to-stata/` directory
- [x] 3.2 Create `tools/jupyter-kernel/` directory
- [x] 3.3 Create `tools/dev/` directory

## Task 4: Move and Rename Send-to-Stata Scripts
- [x] 4.1 Move `send-to-stata.sh` to `tools/send-to-stata/send-to-stata.sh`
- [x] 4.2 Move `install-send-to-stata.sh` to `tools/send-to-stata/install-macos.sh`
- [x] 4.3 Move `install-send-to-stata.ps1` to `tools/send-to-stata/install-windows.ps1`
- [x] 4.4 Move `SEND-TO-STATA.md` to `tools/send-to-stata/README.md`

## Task 5: Move and Rename Jupyter Kernel Scripts
- [x] 5.1 Move `install-jupyter-stata.sh` to `tools/jupyter-kernel/install-macos.sh`
- [x] 5.2 Move `install-jupyter-stata.ps1` to `tools/jupyter-kernel/install-windows.ps1`
- [x] 5.3 Create `tools/jupyter-kernel/README.md` with Jupyter-specific documentation

## Task 6: Move and Rename Dev Setup Scripts
- [x] 6.1 Move `setup.sh` to `tools/dev/dev-setup-macos.sh`
- [x] 6.2 Move `setup.ps1` to `tools/dev/dev-setup-windows.ps1`
- [x] 6.3 Move `update-checksum.sh` to `tools/dev/update-send-to-stata-checksum.sh`
- [x] 6.4 Move `update-setup-checksums.ps1` to `tools/dev/update-dev-checksums.ps1`
- [x] 6.5 Create `tools/dev/README.md` with development setup documentation

## Task 7: Update Script Internal References
- [x] 7.1 Update `tools/send-to-stata/install-macos.sh`: update GITHUB_RAW_BASE path for fetching send-to-stata.sh
- [x] 7.2 Update `tools/send-to-stata/install-macos.sh`: update checksum verification paths
- [x] 7.3 Update `tools/dev/update-send-to-stata-checksum.sh`: update path to send-to-stata.sh
- [x] 7.4 Update `tools/dev/dev-setup-macos.sh`: update paths to call installers from new locations
- [x] 7.5 Update `tools/dev/dev-setup-windows.ps1`: update paths to call installers from new locations

## Task 8: Update README.md
- [x] 8.1 Update curl/irm URLs to new `tools/` paths
- [x] 8.2 Add "What the Install Scripts Do" section explaining each installer's effects
- [x] 8.3 Add "Files Created" subsections for send-to-stata and jupyter-kernel
- [x] 8.4 Update "Building from Source" section with new script paths
- [x] 8.5 Add copy-paste keybindings JSON for manual setup option

## Task 9: Update AGENTS.md
- [x] 9.1 Update all script path references to new `tools/` structure
- [x] 9.2 Update directory structure documentation
- [x] 9.3 Update any curl/irm command examples

## Task 10: Update GitHub Actions Workflows
- [x] 10.1 Update `.github/workflows/update-send-to-stata.yml`: update path to install-windows.ps1
- [x] 10.2 Review and update any other workflows that reference moved scripts

## Task 11: Update DEVELOPMENT.md
- [x] 11.1 Update directory structure diagram to reflect new `tools/` organization
- [x] 11.2 Update script references and paths
- [x] 11.3 Update checksum update instructions

## Task 12: Verify Backward Compatibility
- [x] 12.1 Verify install scripts still install to same user-facing locations (~/.local/bin, ~/.config/zed/)
- [x] 12.2 Test that existing keybindings continue to work after extension update
- [x] 12.3 Test fresh installation from new URLs works correctly

## Task 13: Manual Testing
- [x] 13.1 Install extension in Zed, verify it appears as "Stata"
- [x] 13.2 Open a .do file, run `task: spawn`, verify Stata tasks appear
- [x] 13.3 Run a task without send-to-stata installed, verify error message shows both install commands
- [x] 13.4 Run macOS install script from new URL, verify installation succeeds
- [x] 13.5 Verify keybindings work after installation
- [x] 13.6 Verify task shadowing works (installer tasks replace extension tasks)
