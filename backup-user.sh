#!/usr/bin/env bash
# Creates a restricted backup user for Koha backups used by the Windows automation.
# - Creates user and password (or uses provided password)
# - Installs SSH public key if provided
# - Grants NOPASSWD sudo for only the required commands:
#     * koha-run-backups (any instance)
#     * cp from /var/spool/koha/*/* to /tmp/*
#     * chmod 644 /tmp/*
#     * shutdown now (can be disabled with --no-shutdown)
#
# Usage:
#   sudo bash provision-koha-backup-user.sh \
#     --user backup \
#     --password 'S3curePass!' \
#     --ssh-key-file /path/to/id_ed25519.pub \
#     --no-shutdown
#
# Or:
#   sudo bash provision-koha-backup-user.sh --user backup --ssh-key 'ssh-ed25519 AAAA... comment'
#
set -euo pipefail

# Defaults
USER_NAME="backup"
USER_PASSWORD="backup@12345"
SSH_KEY_FILE=""
SSH_KEY_TEXT=""
ALLOW_SHUTDOWN=1

print_help() {
  sed -n '1,60p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--user) USER_NAME="${2:-}"; shift 2;;
    -p|--password) USER_PASSWORD="${2:-}"; shift 2;;
    -k|--ssh-key-file) SSH_KEY_FILE="${2:-}"; shift 2;;
    -K|--ssh-key) SSH_KEY_TEXT="${2:-}"; shift 2;;
    --no-shutdown) ALLOW_SHUTDOWN=0; shift;;
    -h|--help) print_help;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root (sudo)." >&2
  exit 1
fi

# Resolve binaries (paths can differ by distro)
KOHA_RUN_BACKUPS="$(command -v koha-run-backups || true)"
CP_BIN="$(command -v cp || true)"
CHMOD_BIN="$(command -v chmod || true)"
SHUTDOWN_BIN="$(command -v shutdown || true)"

if [[ -z "$KOHA_RUN_BACKUPS" ]]; then
  # Common path on Debian/Ubuntu
  if [[ -x /usr/sbin/koha-run-backups ]]; then
    KOHA_RUN_BACKUPS="/usr/sbin/koha-run-backups"
  else
    echo "koha-run-backups not found. Ensure Koha is installed and koha-run-backups is in PATH." >&2
    exit 1
  fi
fi

for b in CP_BIN CHMOD_BIN; do
  if [[ -z "${!b}" ]]; then
    # Strip trailing _BIN from the variable name for a cleaner message
    name="${b%_BIN}"
    echo "Required command not found in PATH: ${!b:-$name}" >&2
    exit 1
  fi
done

if [[ $ALLOW_SHUTDOWN -eq 1 && -z "$SHUTDOWN_BIN" ]]; then
  # Common path
  if [[ -x /sbin/shutdown ]]; then
    SHUTDOWN_BIN="/sbin/shutdown"
  else
    echo "shutdown command not found. You can re-run with --no-shutdown to skip that permission." >&2
    exit 1
  fi
fi

# Create user if not exists
if id "$USER_NAME" &>/dev/null; then
  echo "User '$USER_NAME' already exists."
else
  useradd -m -s /bin/bash -c "Koha Backup User" "$USER_NAME"
  echo "Created user '$USER_NAME'."
fi

# Set password (generate if not provided)
if [[ -z "$USER_PASSWORD" ]]; then
  USER_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^_+=' </dev/urandom | head -c 16 || true)"
  if [[ -z "$USER_PASSWORD" ]]; then
    echo "Failed to generate password. Provide one via --password." >&2
    exit 1
  fi
  echo "Generated password for '$USER_NAME': $USER_PASSWORD"
fi

echo "${USER_NAME}:${USER_PASSWORD}" | chpasswd
chage -I -1 -m 0 -M 99999 -E -1 "$USER_NAME"

# Install SSH key if provided
if [[ -n "$SSH_KEY_FILE" || -n "$SSH_KEY_TEXT" ]]; then
  HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
  SSH_DIR="${HOME_DIR}/.ssh"
  AUTH_KEYS="${SSH_DIR}/authorized_keys"
  install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$SSH_DIR"

  if [[ -n "$SSH_KEY_FILE" ]]; then
    if [[ ! -f "$SSH_KEY_FILE" ]]; then
      echo "SSH key file not found: $SSH_KEY_FILE" >&2
      exit 1
    fi
    # Append key only if not already present
    while IFS= read -r keyline; do
      if ! grep -Fxq "$keyline" "$AUTH_KEYS" 2>/dev/null; then
        echo "$keyline" >> "$AUTH_KEYS"
      fi
    done < "$SSH_KEY_FILE"
  else
    if ! grep -Fxq "$SSH_KEY_TEXT" "$AUTH_KEYS" 2>/dev/null; then
      echo "$SSH_KEY_TEXT" >> "$AUTH_KEYS"
    fi
  fi

  chown "$USER_NAME:$USER_NAME" "$AUTH_KEYS"
  chmod 600 "$AUTH_KEYS"
  echo "Installed SSH public key for '$USER_NAME'."
fi
# Ensure authorized_keys file exists before checking/appending
if [[ -n "$SSH_KEY_FILE" || -n "$SSH_KEY_TEXT" ]]; then
  touch "$AUTH_KEYS" 2>/dev/null || true
  chown "$USER_NAME:$USER_NAME" "$AUTH_KEYS" 2>/dev/null || true
  chmod 600 "$AUTH_KEYS" 2>/dev/null || true
fi
# Build sudoers entry
SUDOERS_FILE="/etc/sudoers.d/koha-backup-${USER_NAME}"
TMP_SUDOERS="$(mktemp)"

trap 'rm -f "$TMP_SUDOERS"' EXIT

{
  echo "Defaults:${USER_NAME} !requiretty"
  echo ""
  echo "Cmnd_Alias KOHA_RUN = ${KOHA_RUN_BACKUPS} *"
  echo "Cmnd_Alias KOHA_CP  = ${CP_BIN} /var/spool/koha/*/* /tmp/*"
  echo "Cmnd_Alias KOHA_CHM = ${CHMOD_BIN} 644 /tmp/*"
  if [[ $ALLOW_SHUTDOWN -eq 1 ]]; then
    echo "Cmnd_Alias KOHA_POW = ${SHUTDOWN_BIN} now"
    echo "${USER_NAME} ALL=(root) NOPASSWD: KOHA_RUN, KOHA_CP, KOHA_CHM, KOHA_POW"
  else
    echo "${USER_NAME} ALL=(root) NOPASSWD: KOHA_RUN, KOHA_CP, KOHA_CHM"
  fi
} > "$TMP_SUDOERS"

# Validate and install sudoers (TMP_SUDOERS will be removed by trap)
if visudo -cf "$TMP_SUDOERS" >/dev/null; then
  install -m 440 -o root -g root "$TMP_SUDOERS" "$SUDOERS_FILE"
  echo "Installed sudoers at $SUDOERS_FILE"
else
  echo "visudo validation failed; sudoers file not installed." >&2
  cat "$TMP_SUDOERS" >&2
  exit 1
fi

# Ensure the user's shell is /bin/bash (we run as root so sudo isn't required)
usermod -s /bin/bash "$USER_NAME" || true

# Final summary
echo ""
echo "Backup user provisioned."
echo "  User:        $USER_NAME"
echo "  Password:    $USER_PASSWORD"
SHUT_TEXT=""
if [[ $ALLOW_SHUTDOWN -eq 1 ]]; then
  SHUT_TEXT=", shutdown now"
fi
echo "  Sudo rights: koha-run-backups, cp from /var/spool/koha/*/* to /tmp/*, chmod 644 /tmp/*${SHUT_TEXT}"
echo ""
echo "Next steps on your Windows machine:"
echo "  - Update your batch script variables:"
echo "      SET USERNAME=${USER_NAME}"
echo "      SET PASSWORD=${USER_PASSWORD}"
echo "  - (Optional) If using SSH key auth, remove -pw from plink/pscp and load your key."
echo ""
echo "Security note:"
echo "  - Permissions are scoped as tightly as possible via sudoers command aliases."
echo "  - Consider using --no-shutdown if automated shutdown is not required."