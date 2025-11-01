# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - 2025-11-01

A major release focused on simplicity, safety, and non‑technical usability. New structure, one‑click launchers, host‑key security, and a full user guide.

### Highlights
- New root launchers: `backup-no-shutdown.bat` and `backup-with-shutdown.bat`
- Auto‑discovers all Koha instances and backs up each one (DB + files)
- Trust‑On‑First‑Use (TOFU) SSH host key discovery and pinning
- Simplified configuration to 3 required values
- Clear logs and predictable local folder structure per instance

### What’s new
- Folder re‑organization for clarity:
  - `with-shutdown/`, `no-shutdown/`, `setup/`, `build/`, `assets/`
- Dynamic host key handling:
  - `HOST_FINGERPRINT` read from `config.txt` when present
  - If blank, scripts auto‑discover and enforce `-hostkey` on all plink/pscp calls
- Setup helpers:
  - `setup/backup-user.sh` (Linux) to create a restricted backup user with minimal sudo rights
  - `setup/setup-backup-user.bat` (Windows) to upload and run the Linux script via SSH
- Logging & retention:
  - `backups/backup_log.txt`
  - Keeps newest N `.tar.gz` files per instance (default 30; configurable via `RETENTION_FILES`)
- Documentation overhaul:
  - `USER-GUIDE.md` with an illustrated overview and step‑by‑step guide
  - `STRUCTURE.md` for repository layout
  - Visual assets in `assets/` (SVG placeholders for hero + architecture diagram)

### Fixes
- Removed invalid `-y` flags from `plink.exe` / `pscp.exe`
- Fixed “Host key not in manually configured list” by adding TOFU discovery
- Fixed destination path quoting for `pscp` (removed trailing `\` inside quotes)
- Corrected config loading after folder move (uses `ROOT_DIR` and `CONFIG_FILE`)

### Configuration changes (breaking)
- `config.txt` is now minimal:
  - Required: `USERNAME`, `PASSWORD`, `IP`
  - Optional: `HOST_FINGERPRINT` (auto‑discovered if blank), `RETENTION_FILES`
- Removed legacy/unused keys:
  - `BACKUP_USER`, `BACKUP_PASS`, `INSTANCE`, `KOHA_BACKUP_PATH`, `NO_SHUTDOWN`, `PLINK_URL`, `PSCP_URL`

### Script changes (breaking)
- Legacy single‑instance scripts removed:
  - `backup-download-shutdown.bat`, `backup-download-no-shutdown.bat`, `backup-download-shutdown.exe`
- Multi‑instance scripts moved into subfolders and are called via root launchers:
  - Use `backup-no-shutdown.bat` (daily) or `backup-with-shutdown.bat` (maintenance)
- Scheduled Task paths likely need updating (see Upgrade guide)

### Upgrade guide (from 1.x)
1. Copy `config.txt.example` to `config.txt` (in repo root) and fill:
   - `USERNAME`, `PASSWORD`, `IP`
2. Use the new root launcher you need:
   - Daily backups: `backup-no-shutdown.bat`
   - Maintenance shutdown: `backup-with-shutdown.bat`
3. Update Windows Task Scheduler to point to the new launcher path.
4. Optional: remove any old single‑instance scripts you were using.

### Compatibility
- Supported: Standard Koha package installs (Debian/Ubuntu), single or multi‑tenant
- Not supported: Docker‑based deployments or non‑standard backup locations

### Known limitations
- Only `.tar.gz` files are rotated by retention (database `.sql.gz` not pruned yet)
- First run performs TOFU host‑key discovery; if the server’s host key changes, update `HOST_FINGERPRINT` or allow re‑discovery

### Verification
- Tested on Windows with successful end‑to‑end backups for instance "library" (both `.tar.gz` and `.sql.gz` downloaded)
- Logs written to `backups/backup_log.txt`

### Documentation
- Start here: `USER-GUIDE.md` (Illustrated Overview + Step‑by‑Step)
- Project layout: `STRUCTURE.md`

---

## [1.x] - 2024-xx-xx
Initial versions with single‑instance scripts and basic download automation.

[2.0.0]: https://github.com/mahsandu/koha-backup/releases/tag/v2.0.0
