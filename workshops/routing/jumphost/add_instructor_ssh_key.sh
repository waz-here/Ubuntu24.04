#!/usr/bin/env bash
set -Eeuo pipefail

CONTAINER="routing-instructor"
INSTRUCTOR_USER="instructor"
DISABLE_PASSWORD=0

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  sudo ./add_instructor_ssh_key.sh [--disable-password] KEY_FILE

KEY_FILE may contain one or more OpenSSH public keys, one per line.

Options:
  --disable-password   Disable instructor SSH password authentication after
                       adding the key(s).
  -h, --help           Show this help.
EOF
}

[[ $EUID -eq 0 ]] || die "Run this script with sudo."

KEY_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --disable-password)
            DISABLE_PASSWORD=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            [[ -z "$KEY_FILE" ]] || die "Only one key file may be supplied."
            KEY_FILE="$1"
            shift
            ;;
    esac
done

[[ -n "$KEY_FILE" ]] || die "A public-key file is required."
[[ -s "$KEY_FILE" ]] || die "Key file not found or empty: $KEY_FILE"
command -v lxc-info >/dev/null 2>&1 || die "LXC tools are not installed."
lxc-info -n "$CONTAINER" >/dev/null 2>&1 || die "Container not found: $CONTAINER"

if [[ "$(lxc-info -n "$CONTAINER" -sH)" != "RUNNING" ]]; then
    lxc-start -n "$CONTAINER" -d
fi

ROOTFS="/var/lib/lxc/${CONTAINER}/rootfs"
SSH_DIR="${ROOTFS}/home/${INSTRUCTOR_USER}/.ssh"
AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"

install -d -m 0700 "$SSH_DIR"
touch "$AUTHORIZED_KEYS"
chmod 0600 "$AUTHORIZED_KEYS"

while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    case "$line" in
        ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*\ *|sk-ssh-ed25519@openssh.com\ *|sk-ecdsa-sha2-nistp256@openssh.com\ *)
            grep -qxF "$line" "$AUTHORIZED_KEYS" || printf '%s\n' "$line" >>"$AUTHORIZED_KEYS"
            ;;
        *)
            die "Unsupported or invalid public-key line encountered."
            ;;
    esac
done <"$KEY_FILE"

uid="$(chroot "$ROOTFS" id -u "$INSTRUCTOR_USER")"
gid="$(chroot "$ROOTFS" id -g "$INSTRUCTOR_USER")"
chown -R "$uid:$gid" "$SSH_DIR"

CONF="${ROOTFS}/etc/ssh/sshd_config.d/90-routing-workshop-instructor.conf"
[[ -f "$CONF" ]] || die "Instructor SSH configuration not found: $CONF"

sed -i 's/^PubkeyAuthentication .*/PubkeyAuthentication yes/' "$CONF"

if [[ "$DISABLE_PASSWORD" -eq 1 ]]; then
    sed -i 's/^PasswordAuthentication .*/PasswordAuthentication no/' "$CONF"
fi

lxc-attach -n "$CONTAINER" -- sshd -t
lxc-attach -n "$CONTAINER" -- systemctl restart ssh

echo "Instructor SSH public key(s) added successfully."
if [[ "$DISABLE_PASSWORD" -eq 1 ]]; then
    echo "Instructor SSH password authentication is now disabled."
else
    echo "Instructor SSH password authentication remains enabled."
fi
