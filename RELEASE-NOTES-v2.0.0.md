# Koha Backup v2.0.0 - Windows Multi-Instance Automation

**Release Date:** November 1, 2025

A major release focused on simplicity, safety, and non-technical usability. This version introduces root-level launchers, TOFU host key security, comprehensive documentation, and streamlined configuration.

## 🎉 What's New

### One-Click Launchers
- **backup-no-shutdown.bat** - Daily backups, server stays online
- **backup-with-shutdown.bat** - Maintenance backups with shutdown
- No need to navigate into subfolders anymore

### Auto-Discovery
- Automatically finds all enabled Koha instances via `koha-list --enabled`
- No manual configuration of instance names needed
- Downloads both `.tar.gz` (files) and `.sql.gz` (database) for each instance

### Enhanced Security
- **TOFU (Trust-On-First-Use)** host key discovery and pinning
- Dynamic `-hostkey` enforcement on all SSH/SCP operations
- Auto-discovers server fingerprint on first run if not configured
- Prevents man-in-the-middle attacks

### Simplified Configuration
**Only 3 required settings in config.txt:**
```
USERNAME=backup
PASSWORD=your_password
IP=10.10.10.105
```

That's it! Everything else auto-configures.

### Professional Documentation
- **USER-GUIDE.md** - 70+ page comprehensive guide with:
  - Illustrated flow diagrams
  - Step-by-step setup (7 detailed steps)
  - Troubleshooting section
  - Security hardening guide (3 levels)
  - Training checklist for staff
- **CHANGELOG.md** - Version history and upgrade guides
- **Visual assets** - SVG diagrams for presentations and social media

### Setup Automation
- **setup/backup-user.sh** (Linux) - Creates restricted backup user with minimal sudo rights
- **setup/setup-backup-user.bat** (Windows) - Automated provisioning from Windows
- Interactive prompts guide you through the entire setup process

## 📦 What's Included

```
koha-backup-shutdown/
├── backup-no-shutdown.bat       # Daily launcher
├── backup-with-shutdown.bat     # Maintenance launcher
├── config.txt.example           # Configuration template
├── USER-GUIDE.md                # Complete user guide
├── CHANGELOG.md                 # Version history
├── with-shutdown/               # Scripts for shutdown mode
├── no-shutdown/                 # Scripts for no-shutdown mode
├── setup/                       # User provisioning helpers
├── build/                       # EXE compilation tools
└── assets/                      # Visual diagrams (SVG)
```

## 🚀 Quick Start

### 1. Setup (one-time, 10 minutes)
```powershell
# Create backup user on server
cd setup
.\setup-backup-user.bat

# Configure credentials
copy config.txt.example config.txt
notepad config.txt  # Fill: USERNAME, PASSWORD, IP
```

### 2. Run First Backup
```powershell
.\backup-no-shutdown.bat
```

### 3. Schedule (optional)
Use Windows Task Scheduler to run `backup-no-shutdown.bat` daily at 2 AM.

See **USER-GUIDE.md** for detailed instructions.

## 🔧 What Changed (Breaking)

### Removed Files
These legacy single-instance scripts have been removed:
- `backup-download-shutdown.bat`
- `backup-download-no-shutdown.bat`
- `backup-download-shutdown.exe`

**Migration:** Use the new root-level launchers instead.

### Configuration Simplified
Removed unused config keys:
- `BACKUP_USER`, `BACKUP_PASS` (legacy)
- `INSTANCE` (auto-discovered now)
- `KOHA_BACKUP_PATH` (uses standard location)
- `NO_SHUTDOWN` (use appropriate launcher instead)
- `PLINK_URL`, `PSCP_URL` (hard-coded defaults)

### Folder Reorganization
Scripts moved to subfolders for clarity:
- `with-shutdown/backup-all-instances.bat`
- `no-shutdown/backup-all-instances-no-shutdown.bat`

**Use the root launchers** - they handle paths automatically.

## 📋 Upgrade from v1.x

1. **Backup your current setup** (copy entire folder)
2. **Create new config.txt:**
   ```powershell
   copy config.txt.example config.txt
   # Edit and fill: USERNAME, PASSWORD, IP
   ```
3. **Test with new launcher:**
   ```powershell
   .\backup-no-shutdown.bat
   ```
4. **Update Task Scheduler:**
   - Program: `cmd.exe`
   - Arguments: `/c "D:\Path\to\backup-no-shutdown.bat"`
   - Working directory: `D:\Path\to\koha-backup-shutdown`

## 🐛 Fixes

- ✅ Removed invalid `-y` flags from plink.exe/pscp.exe (not valid options)
- ✅ Fixed "Host key not in manually configured list" via TOFU discovery
- ✅ Fixed pscp destination path quoting (removed trailing `\` inside quotes)
- ✅ Corrected config loading after folder reorganization (uses ROOT_DIR)
- ✅ Fixed duplicate config parsing loop

## ✨ Features

- Auto-downloads plink.exe and pscp.exe to `tools/` if missing
- Organizes backups per instance: `backups/<instance>/*.tar.gz|.sql.gz`
- Retention policy: keeps newest N .tar.gz files (default 30, configurable)
- Detailed logging to `backups/backup_log.txt`
- Host key auto-discovery with SHA256 fingerprint verification
- Multi-instance support without configuration

## 📊 Compatibility

**Supported:**
- Standard Koha package installation (Debian/Ubuntu)
- Single or multi-tenant Koha servers
- Windows 10/11 (PowerShell available)

**Not Supported:**
- Docker-based Koha deployments
- Custom/manual git installations with non-standard paths
- Installations without `koha-run-backups` command

**95% of Koha installations are supported!**

## 📖 Documentation

- **Getting Started:** [USER-GUIDE.md](USER-GUIDE.md) - Complete walkthrough
- **Release History:** [CHANGELOG.md](CHANGELOG.md) - All versions
- **Project Overview:** [README.md](README.md) - Quick reference
- **Folder Structure:** [STRUCTURE.md](STRUCTURE.md) - Layout explained

## 🔐 Security Notes

- Credentials stored in `config.txt` (excluded from git via .gitignore)
- Recommend file permissions: restrict read access to admins only
- Optional: Compile to EXE for obfuscation (see `build/build-exe.md`)
- Optional: Use SSH key authentication instead of passwords
- TOFU host key verification prevents MITM attacks

## 🙏 Credits

Developed for library staff and IT teams managing Koha ILS.

Special thanks to:
- Koha Community for the excellent ILS platform
- PuTTY project for reliable SSH/SCP tools

## 📝 Verification

This release was tested with:
- Windows 11 Pro (PowerShell 7)
- Koha 24.x on Debian 12
- Multi-instance setup ("library" instance)
- Both .tar.gz and .sql.gz successfully downloaded
- Retention cleanup working correctly
- Host key auto-discovery functional

## 🔗 Links

- **Repository:** https://github.com/mahsandu/koha-backup
- **Issues:** https://github.com/mahsandu/koha-backup/issues
- **Koha Community:** https://koha-community.org/

## 📦 Installation

**Download the release:**
```powershell
# Option 1: Download ZIP from GitHub
# Visit: https://github.com/mahsandu/koha-backup/releases/tag/v2.0.0
# Click "Source code (zip)"

# Option 2: Git clone
git clone https://github.com/mahsandu/koha-backup.git
cd koha-backup/koha-backup-shutdown
```

**Follow the Quick Start above** or see USER-GUIDE.md for detailed steps.

---

**Full Changelog:** https://github.com/mahsandu/koha-backup/compare/v1.0.0...v2.0.0
