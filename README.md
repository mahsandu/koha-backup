# Koha Backup, Download, and Optional Shutdown (Windows)

This repo contains a Windows batch script that connects to a remote Koha server over SSH, triggers or skips Koha backups based on recency, fetches the latest backup files to your Windows machine, and optionally shuts down the remote server. No Telegram integration is used.

## What it does

- Ensures the PuTTY tools (`plink.exe`, `pscp.exe`) are available (auto-downloads into `tools/` if missing).
- Discovers and stores the remote server SSH host fingerprint to avoid interactive host-key prompts in batch mode.
- Optionally runs `koha-run-backups <instance>` on the remote server unless a fresh backup already exists (within the last hour).
- Finds the two most recent Koha backup files (`.sql.gz` and `.tar.gz`) from `/var/spool/koha/<instance>`.
- Copies them to `/tmp` on the remote and adjusts permissions for download.
- Downloads both files to the local `backups/` folder next to the script.
- Keeps only the 30 newest `.tar.gz` files in `backups/` (SQL `.sql.gz` files are currently not pruned).
- Optionally shuts down the remote server (can be disabled with a flag at runtime, or provisioned server-side without shutdown rights).
- Logs progress to `backups/backup_log.txt`.

## Repository contents

- `backup-download-shutdown-telegram.bat` — Main Windows batch script (name retained for continuity; no Telegram usage).
- `backup-user.sh` — Linux-side helper to provision a restricted backup user with minimal sudo rights.
- `backups/` — Destination for downloaded backup files; contains `backup_log.txt`.
- `tools/` — Holds `plink.exe` and `pscp.exe` after first run (auto-downloaded if missing).

## Prerequisites

- Windows 10/11 with PowerShell available (default on modern Windows).
- Network connectivity to the Koha server (SSH port, typically 22).
- Credentials for a restricted backup user on the Koha server. You can create this user with `backup-user.sh` (see below).

## Configure the Windows script

Open `backup-download-shutdown-telegram.bat` and set the variables near the top:

- `USERNAME` — Remote Linux username (e.g., `backup`).
- `PASSWORD` — Password for the user (omit if switching to key-based auth; see Security notes).
- `IP` — IP address or hostname of the Koha server.
- `INSTANCE` — Koha instance name, used to build the remote backup path.

The script writes logs to `backups/backup_log.txt`. The PuTTY tools are placed in `tools/`.

## Usage

Dry-run (no remote actions):

```powershell
& '.\backup-download-shutdown-telegram.bat' test
```

Real run (performs backup if needed, downloads files, may shut down remote):

```powershell
& '.\backup-download-shutdown-telegram.bat'
```

Skip remote shutdown explicitly:

```powershell
& '.\backup-download-shutdown-telegram.bat' --no-shutdown
```

Combine options:

```powershell
& '.\backup-download-shutdown-telegram.bat' test --no-shutdown
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
- Add arguments: `/c "D:\\path\\to\\backup-download-shutdown-telegram.bat --no-shutdown"`
- Start in: `D:\\path\\to\\repo` (folder containing the script)

Alternatively, call it via PowerShell:

- Program/script: `powershell.exe`
- Add arguments: `-NoProfile -ExecutionPolicy Bypass -Command "& 'D:\\path\\to\\backup-download-shutdown-telegram.bat' --no-shutdown"`

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
- The main script filename still includes `-telegram` for continuity. You can rename it (and update any scheduler entries) if you want a cleaner name.

---

Backups are saved next to the script to keep things simple and portable. Review the log file after your first run to confirm everything is working as expected.
