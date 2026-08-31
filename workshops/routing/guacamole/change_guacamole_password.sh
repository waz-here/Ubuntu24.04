#!/usr/bin/env bash
#
# Change the Apache Guacamole workshop user's password.
#
# This helper is intended for the Ubuntu 24.04 routing workshop installer.
# It updates the password hash in user-mapping.xml, updates the instructor
# credentials file, and restarts the Guacamole web container.
#
# Usage:
#   sudo ./change_guacamole_password.sh
#   sudo ./change_guacamole_password.sh --user student
#
set -Eeuo pipefail

GUAC_DIR="/opt/routing-workshop/guacamole"
USER_MAPPING="${GUAC_DIR}/config/user-mapping.xml"
CREDENTIALS_FILE=""
GUAC_USERNAME="student"

usage() {
    cat <<'EOF'
Usage:
  sudo ./change_guacamole_password.sh [options]

Options:
  --user USER     Guacamole username to update. Default: student
  -h, --help      Show this help.

The new password is requested interactively so that it is not stored in
your shell command history.

The password must contain at least 8 characters.
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            [[ $# -ge 2 ]] || die "--user requires a value"
            GUAC_USERNAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

[[ $EUID -eq 0 ]] || die "Run this script with sudo."
[[ -f "$USER_MAPPING" ]] || die "Guacamole user mapping not found: $USER_MAPPING"
command -v python3 >/dev/null 2>&1 || die "python3 is required."
command -v md5sum >/dev/null 2>&1 || die "md5sum is required."
command -v docker >/dev/null 2>&1 || die "docker is required."

# Determine the workshop owner's home directory from the credentials file,
# falling back to the first matching file under /home.
if [[ -f /root/virtual_labs/guacamole-credentials.txt ]]; then
    CREDENTIALS_FILE="/root/virtual_labs/guacamole-credentials.txt"
else
    CREDENTIALS_FILE="$(find /home -maxdepth 3 -type f \
        -path '*/virtual_labs/guacamole-credentials.txt' \
        -print -quit 2>/dev/null || true)"
fi

printf 'Changing Guacamole password for user: %s\n' "$GUAC_USERNAME"
printf 'Password entry will not be displayed.\n\n'

while true; do
    read -r -s -p "New password: " NEW_PASSWORD
    printf '\n'
    read -r -s -p "Confirm password: " CONFIRM_PASSWORD
    printf '\n'

    [[ "$NEW_PASSWORD" == "$CONFIRM_PASSWORD" ]] || {
        printf 'Passwords do not match. Try again.\n\n' >&2
        continue
    }

    [[ ${#NEW_PASSWORD} -ge 8 ]] || {
        printf 'Password must contain at least 12 characters. Try again.\n\n' >&2
        continue
    }

    break
done

PASSWORD_MD5="$(printf '%s' "$NEW_PASSWORD" | md5sum | awk '{print $1}')"

# Make a timestamped backup before changing the mapping.
BACKUP="${USER_MAPPING}.$(date '+%Y%m%d-%H%M%S').bak"
cp -a "$USER_MAPPING" "$BACKUP"

GUAC_USERNAME="$GUAC_USERNAME" PASSWORD_MD5="$PASSWORD_MD5" \
python3 <<'PY'
import os
import sys
import xml.etree.ElementTree as ET

path = "/opt/routing-workshop/guacamole/config/user-mapping.xml"
username = os.environ["GUAC_USERNAME"]
password_md5 = os.environ["PASSWORD_MD5"]

tree = ET.parse(path)
root = tree.getroot()

matches = [
    elem for elem in root.findall("authorize")
    if elem.get("username") == username
]

if not matches:
    print(f'ERROR: Guacamole user "{username}" was not found in {path}', file=sys.stderr)
    sys.exit(2)

if len(matches) > 1:
    print(f'ERROR: More than one Guacamole user named "{username}" was found.', file=sys.stderr)
    sys.exit(3)

authorize = matches[0]
authorize.set("password", password_md5)
authorize.set("encoding", "md5")

ET.indent(tree, space="  ")
tree.write(path, encoding="unicode", xml_declaration=False)
with open(path, "a", encoding="utf-8") as f:
    f.write("\n")
PY

chmod 0644 "$USER_MAPPING"

if [[ -n "$CREDENTIALS_FILE" && -f "$CREDENTIALS_FILE" ]]; then
    CREDENTIALS_BACKUP="${CREDENTIALS_FILE}.$(date '+%Y%m%d-%H%M%S').bak"
    cp -a "$CREDENTIALS_FILE" "$CREDENTIALS_BACKUP"

    GUAC_USERNAME="$GUAC_USERNAME" NEW_PASSWORD="$NEW_PASSWORD" \
    CREDENTIALS_FILE="$CREDENTIALS_FILE" python3 <<'PY'
import os
from pathlib import Path

path = Path(os.environ["CREDENTIALS_FILE"])
username = os.environ["GUAC_USERNAME"]
password = os.environ["NEW_PASSWORD"]

lines = path.read_text().splitlines()
out = []
for line in lines:
    if line.startswith("Username:"):
        out.append(f"Username: {username}")
    elif line.startswith("Password:"):
        out.append(f"Password: {password}")
    else:
        out.append(line)

path.write_text("\n".join(out) + "\n")
PY
    chmod 0600 "$CREDENTIALS_FILE"
else
    printf 'NOTE: guacamole-credentials.txt was not found, so only user-mapping.xml was updated.\n'
fi

cd "$GUAC_DIR"
docker compose restart guacamole >/dev/null

unset NEW_PASSWORD CONFIRM_PASSWORD PASSWORD_MD5

printf '\nGuacamole password changed successfully.\n'
printf 'Username: %s\n' "$GUAC_USERNAME"
printf 'Backup created: %s\n' "$BACKUP"
if [[ -n "$CREDENTIALS_FILE" && -f "$CREDENTIALS_FILE" ]]; then
    printf 'Credentials file updated: %s\n' "$CREDENTIALS_FILE"
fi
printf 'Guacamole web container restarted.\n'
