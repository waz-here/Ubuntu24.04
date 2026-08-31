#!/usr/bin/env bash
#
# setup_routing_workshop_ubuntu24.sh
#
# Ubuntu 24.04 LTS installer for the 14-router Dynamips/Dynagen routing workshop.
#
# Design:
#   - Dynamips 0.2.24 built natively from the upstream GNS3 source.
#   - Dynagen 0.11.0 isolated in a legacy Python 2 container.
#   - Existing ~/virtual_labs/routing and ~/virtual_labs/images layout retained.
#   - Apache Guacamole 1.6.0 + guacd in Docker for browser-based router consoles.
#   - Nginx reverse proxy with a self-signed TLS certificate by default.
#
# Run:
#   sudo ./setup_routing_workshop_ubuntu24.sh
#
# Useful options:
#   --without-guacamole     Skip Guacamole and Nginx web-console configuration.
#   --guac-user USER        Guacamole workshop username. Default: student
#   --guac-password PASS    Guacamole workshop password. Default: generated.
#   --enable-firewall       Configure a restrictive iptables/ip6tables ruleset.
#                           SSH remains allowed. HTTP/HTTPS are allowed when
#                           Guacamole is installed.
#   --no-upgrade            Skip apt-get dist-upgrade.
#   --workshop-user USER    Override the non-root workshop owner.
#
# Important:
#   This script DOES NOT download Cisco IOS images. You must provide a legally
#   obtained IOS image matching topology.net.
#
set -Eeuo pipefail

########################################
# Versions and upstream locations
########################################

DYNAMIPS_VERSION="0.2.24"
DYNAMIPS_REPO="https://github.com/GNS3/dynamips.git"

DYNAGEN_VERSION="0.11.0"
DYNAGEN_URL="https://downloads.sourceforge.net/project/dyna-gen/dynagen%20source%20_%20Linux/dynagen%200.11.0/dynagen-0.11.0.tar.gz"
DYNAGEN_SHA256="53523fe13e151c0476596315aa724d50c6523ab72bb64d0ffc8d3ea8ad4e9628"
DYNAGEN_IMAGE="routing-workshop-dynagen:${DYNAGEN_VERSION}"

GUACAMOLE_VERSION="1.6.0"

TOPOLOGY_URL="https://raw.githubusercontent.com/waz-here/Ubuntu18.04/master/workshops/routing/dynamips/topology.net"

########################################
# Defaults
########################################

INSTALL_GUACAMOLE=1
ENABLE_FIREWALL=0
DO_UPGRADE=1
GUAC_USERNAME="student"
GUAC_PASSWORD=""
WORKSHOP_USER_OVERRIDE=""

########################################
# Logging and error handling
########################################

LOG_FILE="/var/log/routing-workshop-install.log"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

die() {
    log "ERROR: $*"
    exit 1
}

on_error() {
    local exit_code=$?
    local line_no=$1
    log "ERROR: installer failed at line ${line_no}, exit code ${exit_code}."
    log "See ${LOG_FILE} for details."
    exit "$exit_code"
}
trap 'on_error $LINENO' ERR

usage() {
    cat <<'EOF'
Usage:
  sudo ./setup_routing_workshop_ubuntu24.sh [options]

Options:
  --without-guacamole     Do not install Guacamole/Nginx browser console access.
  --guac-user USER        Workshop web username. Default: student
  --guac-password PASS    Workshop web password. Default: generated randomly.
  --enable-firewall            Enable a restrictive iptables firewall ruleset.
  --no-upgrade            Skip apt-get dist-upgrade.
  --workshop-user USER    User who owns ~/virtual_labs.
  -h, --help              Show this help.
EOF
}

########################################
# Parse options
########################################

while [[ $# -gt 0 ]]; do
    case "$1" in
        --without-guacamole)
            INSTALL_GUACAMOLE=0
            shift
            ;;
        --guac-user)
            [[ $# -ge 2 ]] || die "--guac-user requires a value"
            GUAC_USERNAME="$2"
            shift 2
            ;;
        --guac-password)
            [[ $# -ge 2 ]] || die "--guac-password requires a value"
            GUAC_PASSWORD="$2"
            shift 2
            ;;
        --enable-firewall)
            ENABLE_FIREWALL=1
            shift
            ;;
        --no-upgrade)
            DO_UPGRADE=0
            shift
            ;;
        --workshop-user)
            [[ $# -ge 2 ]] || die "--workshop-user requires a value"
            WORKSHOP_USER_OVERRIDE="$2"
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

########################################
# Pre-flight
########################################

check_root() {
    [[ $EUID -eq 0 ]] || die "Run this installer with sudo or as root."
}

check_ubuntu() {
    [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release."
    # shellcheck disable=SC1091
    source /etc/os-release

    [[ "${ID:-}" == "ubuntu" ]] || die "This installer is for Ubuntu. Detected: ${ID:-unknown}"
    [[ "${VERSION_ID:-}" == "24.04" ]] || die "This installer is for Ubuntu 24.04 LTS. Detected: ${VERSION_ID:-unknown}"

    log "Ubuntu ${VERSION_ID} (${VERSION_CODENAME:-unknown}) detected."
}

find_workshop_user() {
    if [[ -n "$WORKSHOP_USER_OVERRIDE" ]]; then
        WORKSHOP_USER="$WORKSHOP_USER_OVERRIDE"
    elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        WORKSHOP_USER="$SUDO_USER"
    else
        WORKSHOP_USER="$(getent passwd 1000 | cut -d: -f1 || true)"
    fi

    [[ -n "${WORKSHOP_USER:-}" ]] || die "Could not determine workshop user. Use --workshop-user USER."
    id "$WORKSHOP_USER" >/dev/null 2>&1 || die "Workshop user '$WORKSHOP_USER' does not exist."

    WORKSHOP_HOME="$(getent passwd "$WORKSHOP_USER" | cut -d: -f6)"
    [[ -d "$WORKSHOP_HOME" ]] || die "Home directory not found for $WORKSHOP_USER: $WORKSHOP_HOME"

    WORKSHOP_ROOT="${WORKSHOP_HOME}/virtual_labs"
    ROUTING_DIR="${WORKSHOP_ROOT}/routing"
    IMAGE_DIR="${WORKSHOP_ROOT}/images"
    STATE_DIR="${WORKSHOP_HOME}/.local/state/routing-workshop"
    GUAC_DIR="/opt/routing-workshop/guacamole"
    DYNAGEN_BUILD_DIR="/opt/routing-workshop/dynagen"

    log "Workshop owner: ${WORKSHOP_USER}"
    log "Workshop home:  ${WORKSHOP_HOME}"
}

########################################
# Package management
########################################

update_packages() {
    export DEBIAN_FRONTEND=noninteractive

    log "Updating APT package lists."
    apt-get update >>"$LOG_FILE" 2>&1

    if [[ "$DO_UPGRADE" -eq 1 ]]; then
        log "Running apt-get dist-upgrade."
        apt-get dist-upgrade -y >>"$LOG_FILE" 2>&1
    else
        log "Skipping dist-upgrade (--no-upgrade specified)."
    fi
}

install_base_packages() {
    local packages=(
        build-essential
        ca-certificates
        cmake
        curl
        git
        gnupg
        libelf-dev
        libpcap0.8-dev
        lsb-release
        nginx
        openssh-server
        openssl
        screen
        telnet
        iptables
        iptables-persistent
        netfilter-persistent
    )

    if [[ "$INSTALL_GUACAMOLE" -eq 0 ]]; then
        # Nginx is not required if browser access is disabled.
        packages=(
            build-essential
            ca-certificates
            cmake
            curl
            git
            gnupg
            libelf-dev
            libpcap0.8-dev
            lsb-release
            openssh-server
            openssl
            screen
            telnet
            iptables
        )
    fi

    log "Installing base packages."
    apt-get install -y "${packages[@]}" >>"$LOG_FILE" 2>&1

    systemctl enable --now ssh >>"$LOG_FILE" 2>&1 || true
}

########################################
# Docker
########################################

install_docker() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        log "Docker Engine and Docker Compose plugin already installed."
    else
        log "Installing Docker Engine from Docker's official Ubuntu repository."

        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

        apt-get update >>"$LOG_FILE" 2>&1

        # Remove conflicting distro packages only if they are installed.
        local conflicts=(docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc)
        local installed_conflicts=()
        local pkg
        for pkg in "${conflicts[@]}"; do
            if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
                installed_conflicts+=("$pkg")
            fi
        done

        if [[ ${#installed_conflicts[@]} -gt 0 ]]; then
            log "Removing conflicting Docker packages: ${installed_conflicts[*]}"
            apt-get remove -y "${installed_conflicts[@]}" >>"$LOG_FILE" 2>&1
        fi

        apt-get install -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin \
            >>"$LOG_FILE" 2>&1
    fi

    systemctl enable --now docker >>"$LOG_FILE" 2>&1

    if ! id -nG "$WORKSHOP_USER" | grep -qw docker; then
        usermod -aG docker "$WORKSHOP_USER"
        log "Added ${WORKSHOP_USER} to the docker group."
        log "A logout/login is required before ${WORKSHOP_USER} receives Docker group membership."
    fi
}

########################################
# Dynamips
########################################

install_dynamips() {
    local src_dir="/usr/local/src/dynamips-${DYNAMIPS_VERSION}"

    if command -v dynamips >/dev/null 2>&1; then
        local existing
        existing="$(dynamips --version 2>&1 | head -n1 || true)"
        log "Existing Dynamips detected: ${existing:-version output unavailable}"
    fi

    log "Building Dynamips ${DYNAMIPS_VERSION} from upstream source."

    rm -rf "$src_dir"
    mkdir -p /usr/local/src

    git clone \
        --depth 1 \
        --branch "v${DYNAMIPS_VERSION}" \
        "$DYNAMIPS_REPO" \
        "$src_dir" \
        >>"$LOG_FILE" 2>&1

    cmake \
        -S "$src_dir" \
        -B "$src_dir/build" \
        -DDYNAMIPS_CODE=stable \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        >>"$LOG_FILE" 2>&1

    cmake --build "$src_dir/build" --parallel "$(nproc)" >>"$LOG_FILE" 2>&1
    cmake --install "$src_dir/build" >>"$LOG_FILE" 2>&1
    ldconfig

    command -v dynamips >/dev/null 2>&1 || die "Dynamips installation completed but 'dynamips' is not in PATH."
    log "Dynamips installed: $(dynamips --version 2>&1 | head -n1 || true)"
}

########################################
# Workshop files
########################################

setup_workshop_files() {
    log "Creating workshop directories."
    install -d -o "$WORKSHOP_USER" -g "$WORKSHOP_USER" "$WORKSHOP_ROOT"
    install -d -o "$WORKSHOP_USER" -g "$WORKSHOP_USER" "$ROUTING_DIR"
    install -d -o "$WORKSHOP_USER" -g "$WORKSHOP_USER" "$IMAGE_DIR"
    install -d -o "$WORKSHOP_USER" -g "$WORKSHOP_USER" "$STATE_DIR"

    # Preserve compatibility with the old repository layout if the installer
    # is executed from workshops/routing/ and dynamips/ is beside it.
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ -d "${script_dir}/dynamips" ]]; then
        log "Copying local dynamips workshop files from ${script_dir}/dynamips."
        cp -a "${script_dir}/dynamips/." "$ROUTING_DIR/"
    else
        log "Local dynamips/ directory not found. Downloading topology.net from the existing workshop repository."
        curl -fsSL "$TOPOLOGY_URL" -o "${ROUTING_DIR}/topology.net"
    fi

    # Normalise the two known tab-indented lines without changing topology semantics.
    if [[ -f "${ROUTING_DIR}/topology.net" ]]; then
        sed -i \
            -e 's/^[[:space:]]*idlepc[[:space:]]*=[[:space:]]*0x6318a8ac/      idlepc = 0x6318a8ac/' \
            -e 's/^[[:space:]]*slot1[[:space:]]*=[[:space:]]*PA-4T/      slot1 = PA-4T/' \
            "${ROUTING_DIR}/topology.net"
    fi

    find "$ROUTING_DIR" -maxdepth 1 -type f -name '*.sh' -exec chmod u+x {} + 2>/dev/null || true
    chown -R "$WORKSHOP_USER:$WORKSHOP_USER" "$WORKSHOP_ROOT"
}

########################################
# Legacy Dynagen container
########################################

install_dynagen_container() {
    log "Preparing isolated Dynagen ${DYNAGEN_VERSION} compatibility container."

    mkdir -p "$DYNAGEN_BUILD_DIR"

    local tarball="${DYNAGEN_BUILD_DIR}/dynagen-${DYNAGEN_VERSION}.tar.gz"

    curl -fL "$DYNAGEN_URL" -o "$tarball" >>"$LOG_FILE" 2>&1

    local actual_sha
    actual_sha="$(sha256sum "$tarball" | awk '{print $1}')"
    [[ "$actual_sha" == "$DYNAGEN_SHA256" ]] || \
        die "Dynagen SHA256 mismatch. Expected ${DYNAGEN_SHA256}, got ${actual_sha}."

    cat >"${DYNAGEN_BUILD_DIR}/Dockerfile" <<EOF
FROM python:2.7.18-slim-buster

COPY dynagen-${DYNAGEN_VERSION}.tar.gz /tmp/dynagen.tar.gz

RUN mkdir -p /opt/dynagen \
    && tar -xzf /tmp/dynagen.tar.gz -C /opt/dynagen \
    && rm -f /tmp/dynagen.tar.gz \
    && chmod +x /opt/dynagen/dynagen-${DYNAGEN_VERSION}/dynagen

WORKDIR /lab

ENTRYPOINT ["python", "/opt/dynagen/dynagen-${DYNAGEN_VERSION}/dynagen"]
EOF

    docker build \
        -t "$DYNAGEN_IMAGE" \
        "$DYNAGEN_BUILD_DIR" \
        >>"$LOG_FILE" 2>&1

    cat >/usr/local/bin/dynagen <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

DYNAGEN_IMAGE="routing-workshop-dynagen:0.11.0"

CURRENT_USER="$(id -un)"
CURRENT_HOME="$(getent passwd "$CURRENT_USER" | cut -d: -f6)"
LAB_ROOT="${DYNAGEN_LAB_ROOT:-${CURRENT_HOME}/virtual_labs}"

if [[ ! -d "$LAB_ROOT" ]]; then
    echo "Dynagen wrapper: lab root does not exist: $LAB_ROOT" >&2
    exit 1
fi

case "$PWD/" in
    "$LAB_ROOT"/*) ;;
    *)
        echo "Dynagen wrapper: run dynagen from within $LAB_ROOT" >&2
        echo "Example: cd ${LAB_ROOT}/routing && dynagen topology.net" >&2
        exit 1
        ;;
esac

if ! docker info >/dev/null 2>&1; then
    echo "Dynagen wrapper: cannot access Docker." >&2
    echo "If Docker was just installed, log out and back in to refresh group membership." >&2
    exit 1
fi

exec docker run --rm -it \
    --network host \
    -v "${LAB_ROOT}:${LAB_ROOT}" \
    -w "$PWD" \
    "$DYNAGEN_IMAGE" \
    "$@"
EOF

    chmod 0755 /usr/local/bin/dynagen
    log "Installed /usr/local/bin/dynagen wrapper."
}

########################################
# IP forwarding
########################################

enable_forwarding() {
    log "Enabling IPv4 and IPv6 forwarding."

    cat >/etc/sysctl.d/90-routing-workshop.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

    sysctl --system >>"$LOG_FILE" 2>&1
}

########################################
# Dynamips helper scripts
########################################

create_lab_helpers() {
    log "Creating Dynamips start/stop/status helper scripts."

    cat >"${ROUTING_DIR}/start_dynamips.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

ROUTING_DIR="${ROUTING_DIR}"
STATE_DIR="${STATE_DIR}"

mkdir -p "\$STATE_DIR"
cd "\$ROUTING_DIR"

start_one() {
    local port="\$1"
    local pidfile="\$STATE_DIR/dynamips-\${port}.pid"
    local logfile="\$STATE_DIR/dynamips-\${port}.log"

    if [[ -f "\$pidfile" ]] && kill -0 "\$(cat "\$pidfile")" 2>/dev/null; then
        echo "Dynamips hypervisor \$port already running as PID \$(cat "\$pidfile")."
        return 0
    fi

    nohup /usr/local/bin/dynamips -H "127.0.0.1:\${port}" >"\$logfile" 2>&1 &
    echo \$! >"\$pidfile"

    for _ in {1..20}; do
        if ss -ltn | awk '{print \$4}' | grep -qE "(127\\.0\\.0\\.1|\\[::1\\]):\${port}\$"; then
            echo "Dynamips hypervisor \$port started."
            return 0
        fi
        sleep 0.25
    done

    echo "Dynamips hypervisor \$port did not become ready. See \$logfile" >&2
    return 1
}

start_one 7200
start_one 7201

echo
echo "Next:"
echo "  cd \$ROUTING_DIR"
echo "  dynagen topology.net"
EOF

    cat >"${ROUTING_DIR}/stop_dynamips.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="${STATE_DIR}"

for port in 7200 7201; do
    pidfile="\$STATE_DIR/dynamips-\${port}.pid"

    if [[ -f "\$pidfile" ]]; then
        pid="\$(cat "\$pidfile")"
        if kill -0 "\$pid" 2>/dev/null; then
            kill "\$pid"
            echo "Stopped Dynamips hypervisor \$port (PID \$pid)."
        fi
        rm -f "\$pidfile"
    else
        echo "No PID file for Dynamips hypervisor \$port."
    fi
done
EOF

    cat >"${ROUTING_DIR}/status_lab.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${IMAGE_DIR}/c7200-advipservicesk9-mz.152-4.S3.image"

echo "Dynamips:"
/usr/local/bin/dynamips --version 2>&1 | head -n1 || true
echo

echo "Hypervisors:"
for port in 7200 7201; do
    if ss -ltn | awk '{print \$4}' | grep -qE "(127\\.0\\.0\\.1|\\[::1\\]):\${port}\$"; then
        echo "  \$port: listening"
    else
        echo "  \$port: stopped"
    fi
done
echo

echo "Expected IOS image:"
if [[ -f "\$IMAGE" ]]; then
    echo "  FOUND: \$IMAGE"
else
    echo "  MISSING: \$IMAGE"
fi
echo

echo "Router console ports currently listening:"
ss -ltn | awk 'NR == 1 || \$4 ~ /:(200[1-9]|201[0-4])$/' || true
EOF

    cat >"${ROUTING_DIR}/launch_lab.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

cd "${ROUTING_DIR}"

"${ROUTING_DIR}/start_dynamips.sh"

if [[ ! -f "${IMAGE_DIR}/c7200-advipservicesk9-mz.152-4.S3.image" ]]; then
    echo
    echo "WARNING: expected IOS image is missing:"
    echo "  ${IMAGE_DIR}/c7200-advipservicesk9-mz.152-4.S3.image"
    echo
fi

exec dynagen topology.net
EOF

    chmod 0755 \
        "${ROUTING_DIR}/start_dynamips.sh" \
        "${ROUTING_DIR}/stop_dynamips.sh" \
        "${ROUTING_DIR}/status_lab.sh" \
        "${ROUTING_DIR}/launch_lab.sh"

    chown "$WORKSHOP_USER:$WORKSHOP_USER" \
        "${ROUTING_DIR}/start_dynamips.sh" \
        "${ROUTING_DIR}/stop_dynamips.sh" \
        "${ROUTING_DIR}/status_lab.sh" \
        "${ROUTING_DIR}/launch_lab.sh"
}

########################################
# Guacamole
########################################

generate_guacamole_password() {
    if [[ -z "$GUAC_PASSWORD" ]]; then
        GUAC_PASSWORD="$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)"
    fi

    [[ ${#GUAC_PASSWORD} -ge 12 ]] || \
        die "Guacamole password must be at least 12 characters."

    GUAC_PASSWORD_MD5="$(printf '%s' "$GUAC_PASSWORD" | md5sum | awk '{print $1}')"
}

install_guacamole() {
    [[ "$INSTALL_GUACAMOLE" -eq 1 ]] || {
        log "Skipping Guacamole installation."
        return
    }

    generate_guacamole_password

    log "Installing Apache Guacamole ${GUACAMOLE_VERSION} browser console environment."

    mkdir -p "${GUAC_DIR}/config"

    {
        echo '<user-mapping>'
        printf '  <authorize username="%s" password="%s" encoding="md5">\n' \
            "$GUAC_USERNAME" "$GUAC_PASSWORD_MD5"

        for i in $(seq 1 14); do
            port=$((2000 + i))
            printf '    <connection name="Router r%d">\n' "$i"
            echo '      <protocol>telnet</protocol>'
            echo '      <param name="hostname">127.0.0.1</param>'
            printf '      <param name="port">%d</param>\n' "$port"
            echo '      <param name="font-name">monospace</param>'
            echo '      <param name="font-size">14</param>'
            echo '      <param name="disable-copy">true</param>'
            echo '      <param name="disable-paste">true</param>'
            echo '    </connection>'
        done

        echo '  </authorize>'
        echo '</user-mapping>'
    } >"${GUAC_DIR}/config/user-mapping.xml"

    chmod 0644 "${GUAC_DIR}/config/user-mapping.xml"

    cat >"${GUAC_DIR}/compose.yaml" <<EOF
services:
  guacd:
    image: guacamole/guacd:${GUACAMOLE_VERSION}
    restart: unless-stopped
    network_mode: host

  guacamole:
    image: guacamole/guacamole:${GUACAMOLE_VERSION}
    restart: unless-stopped
    depends_on:
      - guacd
    environment:
      GUACD_HOSTNAME: host.docker.internal
      GUACD_PORT: 4822
      GUACAMOLE_HOME: /etc/guacamole
      WEBAPP_CONTEXT: ROOT
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ./config:/etc/guacamole:ro
    ports:
      - "127.0.0.1:8080:8080"
EOF

    (
        cd "$GUAC_DIR"
        docker compose pull >>"$LOG_FILE" 2>&1
        docker compose up -d >>"$LOG_FILE" 2>&1
    )

    cat >"${WORKSHOP_ROOT}/guacamole-credentials.txt" <<EOF
Routing Workshop browser console

Username: ${GUAC_USERNAME}
Password: ${GUAC_PASSWORD}

The password is also stored as an MD5 hash in:
  ${GUAC_DIR}/config/user-mapping.xml

This user-mapping.xml deployment is intended for a controlled workshop
environment. Use database-backed Guacamole authentication before exposing
the service as a general Internet-facing production service.
EOF

    chmod 0600 "${WORKSHOP_ROOT}/guacamole-credentials.txt"
    chown "$WORKSHOP_USER:$WORKSHOP_USER" "${WORKSHOP_ROOT}/guacamole-credentials.txt"

    log "Guacamole containers started."
}

########################################
# Nginx + TLS
########################################

configure_nginx() {
    [[ "$INSTALL_GUACAMOLE" -eq 1 ]] || return

    local cert_dir="/etc/nginx/ssl"
    local cert="${cert_dir}/routing-workshop.crt"
    local key="${cert_dir}/routing-workshop.key"
    local cn
    cn="$(hostname -f 2>/dev/null || hostname)"

    log "Configuring Nginx reverse proxy and self-signed TLS."

    mkdir -p "$cert_dir"

    if [[ ! -f "$cert" || ! -f "$key" ]]; then
        openssl req -x509 -nodes -newkey rsa:3072 \
            -days 825 \
            -keyout "$key" \
            -out "$cert" \
            -subj "/CN=${cn}" \
            >>"$LOG_FILE" 2>&1
        chmod 0600 "$key"
        chmod 0644 "$cert"
    fi

    cat >/etc/nginx/sites-available/routing-workshop <<'EOF'
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;

    ssl_certificate     /etc/nginx/ssl/routing-workshop.crt;
    ssl_certificate_key /etc/nginx/ssl/routing-workshop.key;

    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:8080;

        proxy_http_version 1.1;
        proxy_buffering off;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
EOF

    rm -f /etc/nginx/sites-enabled/default
    ln -sfn /etc/nginx/sites-available/routing-workshop \
        /etc/nginx/sites-enabled/routing-workshop

    nginx -t >>"$LOG_FILE" 2>&1
    systemctl enable --now nginx >>"$LOG_FILE" 2>&1
    systemctl reload nginx

    log "Nginx configured for HTTPS browser access."
}

########################################
# Firewall
########################################

configure_iptables() {
    [[ "$ENABLE_FIREWALL" -eq 1 ]] || {
        log "iptables firewall was not enabled. Review host firewall rules before exposing this VM."
        return
    }

    log "Configuring iptables and ip6tables firewall."

    # Keep Docker's own chains intact. We only replace the host INPUT policy
    # and add an explicit DOCKER-USER policy for forwarded Docker traffic.
    iptables -F INPUT
    ip6tables -F INPUT

    iptables -P INPUT ACCEPT
    ip6tables -P INPUT ACCEPT

    iptables -A INPUT -i lo -j ACCEPT
    ip6tables -A INPUT -i lo -j ACCEPT

    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    iptables -A INPUT -p icmp -j ACCEPT
    ip6tables -A INPUT -p ipv6-icmp -j ACCEPT

    # Administrative SSH access.
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT

    if [[ "$INSTALL_GUACAMOLE" -eq 1 ]]; then
        # Nginx browser access.
        iptables -A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT
        ip6tables -A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT

        # guacd uses host networking and listens on TCP/4822. The Guacamole
        # web container reaches it through its Docker bridge. Permit 4822 only
        # when traffic arrives from a Docker bridge interface.
        iptables -A INPUT -i 'br+' -p tcp --dport 4822 -j ACCEPT
        iptables -A INPUT -i docker0 -p tcp --dport 4822 -j ACCEPT
    fi

    # Dynamips console ports 2001-2014 and hypervisors 7200/7201 remain bound
    # to 127.0.0.1, so no external INPUT rule is required for them.
    iptables -A INPUT -j DROP
    ip6tables -A INPUT -j DROP

    # Preserve Docker forwarding behaviour while allowing established flows.
    if iptables -nL DOCKER-USER >/dev/null 2>&1; then
        iptables -F DOCKER-USER
        iptables -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        iptables -A DOCKER-USER -j RETURN
    fi

    netfilter-persistent save >>"$LOG_FILE" 2>&1
    log "iptables/ip6tables firewall rules configured and saved."
}

########################################
# Validation
########################################

validate_installation() {
    log "Validating installation."

    command -v dynamips >/dev/null 2>&1 || die "Dynamips validation failed."
    command -v dynagen >/dev/null 2>&1 || die "Dynagen wrapper validation failed."
    command -v docker >/dev/null 2>&1 || die "Docker validation failed."

    [[ -f "${ROUTING_DIR}/topology.net" ]] || die "topology.net was not installed."

    if [[ "$INSTALL_GUACAMOLE" -eq 1 ]]; then
        (
            cd "$GUAC_DIR"
            docker compose ps >>"$LOG_FILE" 2>&1
        )

        nginx -t >>"$LOG_FILE" 2>&1
    fi
}

########################################
# Completion
########################################

display_summary() {
    local primary_ip
    primary_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"

    echo
    echo "================================================================"
    echo "Routing workshop installation completed"
    echo "================================================================"
    echo
    echo "Workshop owner:"
    echo "  ${WORKSHOP_USER}"
    echo
    echo "Routing files:"
    echo "  ${ROUTING_DIR}"
    echo
    echo "IOS image directory:"
    echo "  ${IMAGE_DIR}"
    echo
    echo "Expected IOS image:"
    echo "  ${IMAGE_DIR}/c7200-advipservicesk9-mz.152-4.S3.image"
    echo
    echo "Dynamips:"
    echo "  $(dynamips --version 2>&1 | head -n1 || true)"
    echo
    echo "Dynagen:"
    echo "  Legacy Dynagen ${DYNAGEN_VERSION} is isolated in Docker."
    echo "  Use the normal command: dynagen topology.net"
    echo
    echo "Start the lab:"
    echo "  cd ${ROUTING_DIR}"
    echo "  ./launch_lab.sh"
    echo
    echo "Or start only the two Dynamips hypervisors:"
    echo "  ./start_dynamips.sh"
    echo
    echo "Check status:"
    echo "  ./status_lab.sh"
    echo
    echo "Stop Dynamips:"
    echo "  ./stop_dynamips.sh"
    echo

    if [[ "$INSTALL_GUACAMOLE" -eq 1 ]]; then
        echo "Browser console:"
        if [[ -n "$primary_ip" ]]; then
            echo "  https://${primary_ip}/"
        else
            echo "  https://<server-ip>/"
        fi
        echo
        echo "Guacamole username:"
        echo "  ${GUAC_USERNAME}"
        echo
        echo "Guacamole password:"
        echo "  ${GUAC_PASSWORD}"
        echo
        echo "Credentials file:"
        echo "  ${WORKSHOP_ROOT}/guacamole-credentials.txt"
        echo
        echo "The generated certificate is self-signed, so browsers will warn"
        echo "until you replace it with a certificate trusted by your clients."
        echo
    fi

    if [[ "$ENABLE_FIREWALL" -eq 0 ]]; then
        echo "SECURITY NOTE:"
        echo "  The optional iptables firewall was NOT enabled."
        echo "  Dynamips console ports remain loopback-only, but guacd uses host networking"
        echo "  and listens on TCP/4822. Configure a host firewall before exposing this VM."
        echo "  Re-run with --enable-firewall, or apply equivalent existing firewall rules."
        echo
    fi

    if ! id -nG "$WORKSHOP_USER" | grep -qw docker; then
        echo "Docker group membership is not currently visible."
    fi
    echo "If Docker access fails for ${WORKSHOP_USER}, log out and back in."
    echo
    echo "Installation log:"
    echo "  ${LOG_FILE}"
    echo
    echo "================================================================"
}

########################################
# Main
########################################

main() {
    check_root
    touch "$LOG_FILE"
    chmod 0640 "$LOG_FILE"

    log "Starting Ubuntu 24.04 routing workshop installation."

    check_ubuntu
    find_workshop_user
    update_packages
    install_base_packages
    install_docker
    install_dynamips
    setup_workshop_files
    install_dynagen_container
    enable_forwarding
    create_lab_helpers
    install_guacamole
    configure_nginx
    configure_iptables
    validate_installation

    chown -R "$WORKSHOP_USER:$WORKSHOP_USER" "$WORKSHOP_ROOT"

    log "Installation completed successfully."
    display_summary
}

main "$@"
