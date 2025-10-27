# Koha Backup, Download, and Optional Shutdown (Windows)

This repository provides Windows batch scripts that connect to a remote Koha server over SSH, trigger or skip Koha backups based on recency, download the latest backup files to your Windows machine, and can optionally shut down the remote server.

## What it does

- Ensures the PuTTY tools (`plink.exe`, `pscp.exe`) are available (auto-downloads into `tools/` if missing).
- Discovers and stores the remote server SSH host fingerprint to avoid interactive host-key prompts in batch mode (TOFU).
- Optionally runs `koha-run-backups <instance>` on the remote server unless a fresh backup already exists (within the last hour).
- Finds the two most recent Koha backup files (`.sql.gz` and `.tar.gz`) from `/var/spool/koha/<instance>`.
- Copies them to `/tmp` on the remote and adjusts permissions for download.
- Downloads both files to the local `backups/` folder next to the script.
- Keeps only the 30 newest `.tar.gz` files in `backups/` (SQL `.sql.gz` files are currently not pruned).
- Optionally shuts down the remote server (can be disabled with a flag at runtime, or provisioned server-side without shutdown rights).
- Logs progress to `backups/backup_log.txt`.

## Repository contents

- `backup-download-shutdown.bat` — Main Windows batch script (optional remote shutdown via flag).
- `backup-download-no-shutdown.bat` — Wrapper that always skips remote shutdown.
- `backup-user.sh` — Linux-side helper to provision a restricted backup user with minimal sudo rights.
- `backups/` — Destination for downloaded backup files; contains `backup_log.txt`.
- `tools/` — Holds `plink.exe` and `pscp.exe` after first run (auto-downloaded if missing).
 - `setup-backup-user.bat` — Windows CMD helper that uploads and runs `backup-user.sh` remotely as root.

## Prerequisites

- Windows 10/11 with PowerShell available (default on modern Windows).
- Network connectivity to the Koha server (SSH port, typically 22).
- Credentials for a restricted backup user on the Koha server. You can create this user with `backup-user.sh` (see below).

## Configure the Windows script

You can configure via a `config.txt` file placed next to the script (preferred), or by editing the script defaults.

1) Using `config.txt` (recommended)

- Copy `config.txt.example` to `config.txt` and edit values.
- Supported keys (key=value):
  - `USERNAME` — Remote Linux username (e.g., `backup`).
  - `PASSWORD` — Password for the user (omit if switching to key-based auth; see Security notes).
  - `IP` — IP address or hostname of the Koha server.
  - `INSTANCE` — Koha instance name, used to build the default remote backup path.
  - `KOHA_BACKUP_PATH` — Optional explicit remote path (overrides instance-based path).
    - Ensure this matches your Koha install; e.g., `/var/spool/koha/<instance>` on Debian-based installs.
  - `HOST_FINGERPRINT` — Server host key fingerprint (PuTTY format) used by plink/pscp.
  - `RETENTION_FILES` — How many `.tar.gz` files to keep in `backups/` (default 30).
  - `NO_SHUTDOWN` — 0 or 1; if 1, skip remote shutdown (CLI `--no-shutdown` overrides).
  - `PLINK_URL`, `PSCP_URL` — Optional override URLs for PuTTY tools.

2) Editing the script (fallback)

- Open `backup-download-shutdown.bat` and update the default variables near the top.

The script writes logs to `backups/backup_log.txt`. The PuTTY tools will be placed in `tools/` upon first run if missing.

## Usage

Dry-run (no remote actions):

```powershell
& '.\\backup-download-shutdown.bat' test
```

Real run (performs backup if needed, downloads files, may shut down remote):

```powershell
& '.\\backup-download-shutdown.bat'
```

Skip remote shutdown explicitly:

```powershell
& '.\\backup-download-shutdown.bat' --no-shutdown
```

Combine options:

```powershell
& '.\\backup-download-shutdown.bat' test --no-shutdown
```

Outputs:

- Downloads saved in `backups/`
- Log file at `backups/backup_log.txt`

## Linux-side: provision the backup user

Run this on the Koha server as root to create a restricted user with minimal sudo rights for the script:

```bash
sudo bash backup-user.sh \
  --user backup \
  --password 'S3curePass!' \
  --ssh-key-file /path/to/id_ed25519.pub   # optional \
  --no-shutdown                            # optional: do not grant shutdown rights
```

What it configures:

- Creates a user and sets the password (or uses an existing user if present).
- Installs an SSH public key if provided (recommended).
- Grants NOPASSWD sudo for only the required commands:
  - `koha-run-backups <instance>`
  - `cp /var/spool/koha/*/* /tmp/*`
  - `chmod 644 /tmp/*`
  - `shutdown now` (only if you don’t pass `--no-shutdown`)

### Provisioning from Windows (easier)

If you have root credentials for the Koha server and prefer to set up the backup user from your Windows machine, use the helper script:

```powershell
& '.\\setup-backup-user.bat'
```

It will:

- Prompt for the server host, root user/password, desired backup username/password
- Optionally accept a path to an SSH public key (.pub) to install for key-based auth
- Ensure PuTTY tools are available (downloads to `tools/` if missing)
- Upload `backup-user.sh` to the server and run it as root
- Try to auto-discover the SSH host fingerprint (TOFU); you can also paste it manually if needed

Notes:

- Your root password is used only to connect for setup and is not stored by the script.
- Prefer installing an SSH key and using key-based auth for the backup user afterward.
- If host key discovery fails, you can obtain the fingerprint via `ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub` on the server (or `ssh-keyscan -t ed25519 <host>`), then paste it when prompted.

## How it works (details)

- Host key: The script performs one verbose `plink` run to capture the server’s SSH fingerprint (Trust-On-First-Use). It then uses `-hostkey <fingerprint>` for all non-interactive calls.
- Recency check: If the latest backup’s hour (`YYYY-MM-DD HH`) matches the current remote hour, the script skips running `koha-run-backups` and proceeds to download the latest two files instead.
- Downloads: Each file is first copied to `/tmp` on the remote and made world-readable for download, then fetched via `pscp`.
- Retention: Only `.tar.gz` files are rotated (keeping 30 newest). `.sql.gz` files are not currently pruned.

## Security notes

- Avoid storing passwords in plaintext when possible. Prefer SSH key-based authentication:
  - Update the script to remove `-pw %PASSWORD%` and load your private key via Pageant or PuTTY session settings.
  - Provision an SSH public key with `backup-user.sh`.
- The host-key discovery uses TOFU; verify the first connection on a trusted network to avoid MITM on initial run.

## Scheduling (Windows Task Scheduler)

You can run the script on a schedule, e.g., nightly after Koha maintenance.

- Action: Start a program
- Program/script: `C:\\Windows\\System32\\cmd.exe`
- Add arguments: `/c "D:\\path\\to\\backup-download-shutdown.bat --no-shutdown"`
- Start in: `D:\\path\\to\\repo` (folder containing the script)

Alternatively, schedule via PowerShell:

- Program/script: `powershell.exe`
- Add arguments: `-NoProfile -ExecutionPolicy Bypass -Command "& 'D:\\path\\to\\backup-download-shutdown.bat' --no-shutdown"`

## Troubleshooting

- plink/pscp missing or blocked:
  - The script auto-downloads them from the official site. If blocked by policy, manually place `plink.exe` and `pscp.exe` in `tools/`.
- Host key mismatch errors:
  - The script uses a discovered `HOST_FINGERPRINT`. If the server was reinstalled or the key changed, re-run to re-discover or set `HOST_FINGERPRINT` explicitly.
- “No valid backup filenames found”:
  - Ensure the remote path is correct: `/var/spool/koha/<instance>` and that backup files exist with `.sql.gz` and `.tar.gz` extensions.
  - Confirm the remote user can run `ls` and `koha-run-backups` via sudo.
- Network/timeout issues:
  - Check firewall rules, SSH port, and that the remote server is reachable.

## Known limitations / next steps

- Only `.tar.gz` files are rotated; `.sql.gz` retention is unlimited. You can extend the cleanup section to include `.sql.gz` if desired.


---

Backups are saved next to the script to keep things simple and portable. Review the log file after your first run to confirm everything is working as expected.
