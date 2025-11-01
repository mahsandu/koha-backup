# Repository Structure

## Backup Scripts (Organized by Shutdown Behavior)

### WITH Server Shutdown
- **`backup-all-instances.bat`**
  - Discovers all enabled Koha instances
  - Runs `koha-run-backups` for each instance
  - Downloads `.tar.gz` and `.sql.gz` files
  - **Shuts down the server** after all backups complete

### WITHOUT Server Shutdown  
- **`backup-all-instances-no-shutdown.bat`**
  - Discovers all enabled Koha instances
  - Runs `koha-run-backups` for each instance
  - Downloads `.tar.gz` and `.sql.gz` files
  - **Keeps the server running**

---

## Setup & Configuration

### Configuration Files
- **`config.txt`** - Your active configuration (username, password, IP, host fingerprint, retention)
- **`config.txt.example`** - Template with all available settings and documentation

### Setup Scripts
- **`setup-backup-user.bat`** - Windows helper to provision backup user on remote server
- **`backup-user.sh`** - Linux script that creates restricted backup user with minimal sudo rights

### Build Tools
- **`build-exe.ps1`** - PowerShell script to package .bat files as .exe using IExpress
- **`build-exe.md`** - Documentation for building standalone executables

---

## Output Folders

### `backups/`
Structure:
```
backups/
├── backup_log.txt
├── library/
│   ├── library-2025-11-01.tar.gz
│   └── library-2025-11-01.sql.gz
├── catalog/
│   ├── catalog-2025-11-01.tar.gz
│   └── catalog-2025-11-01.sql.gz
└── ...
```

- Each Koha instance gets its own subfolder
- Retention: keeps 30 newest `.tar.gz` files per instance (configurable)
- All actions logged to `backup_log.txt`

### `tools/`
- Auto-downloaded on first run:
  - `plink.exe` - PuTTY SSH client
  - `pscp.exe` - PuTTY SCP client

---

## Removed Files (Cleanup)

The following legacy single-instance scripts were removed as they are superseded by the multi-instance scripts:
- ~~`backup-download-shutdown.bat`~~ (replaced by `backup-all-instances.bat`)
- ~~`backup-download-no-shutdown.bat`~~ (replaced by `backup-all-instances-no-shutdown.bat`)
- ~~`backup-download-shutdown.exe`~~ (can be rebuilt from current scripts if needed)

**Why removed?**  
The multi-instance scripts handle all use cases better:
- Automatically discover all instances (no manual configuration)
- Better error handling and logging
- Cleaner per-instance folder organization
- Same host key discovery and security features

---

## Quick Start

1. **Configure:** Copy `config.txt.example` to `config.txt` and edit with your credentials
2. **Run backup:** 
   - `backup-all-instances-no-shutdown.bat` (recommended for testing)
   - `backup-all-instances.bat` (when ready to include shutdown)
3. **Check results:** Review `backups\backup_log.txt` and instance folders
