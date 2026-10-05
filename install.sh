#!/usr/bin/env bash
# ==============================================================================
# elastic-airgap-installer — Interactive Elastic Stack Air-Gapped Installer
#
# Installs Elasticsearch · Kibana · Fleet Server (Elastic Agent) from
# pre-downloaded packages — no internet connection required.
#
# Topology:  Single-node only
# Platforms: RHEL / CentOS / Rocky / AlmaLinux  |  Ubuntu / Debian
# ==============================================================================
set -euo pipefail
IFS=$'\n\t'

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Globals ───────────────────────────────────────────────────────────────────
ELASTIC_VERSION=""          # detected from package filenames
ELASTIC_MAJOR=""

PKG_DIR=""                  # directory containing pre-downloaded packages
ES_PKG=""                   # full path to elasticsearch .rpm or .deb
KIBANA_PKG=""               # full path to kibana .rpm or .deb
AGENT_TARBALL=""            # full path to elastic-agent .tar.gz
AGENT_TARBALL_DIR=""        # path to extracted tarball directory

CLUSTER_NAME="elastic-poc"
NODE_NAME=""
NETWORK_HOST="0.0.0.0"
KIBANA_HOST="0.0.0.0"
FLEET_HOST="0.0.0.0"

ES_DATA_DIR="/var/lib/elasticsearch"
ES_LOG_DIR="/var/log/elasticsearch"

ES_LOCAL_URL=""
KIBANA_LOCAL_URL=""

ES_PASSWORD=""
KIBANA_SYSTEM_PASSWORD=""
FLEET_SERVICE_TOKEN=""

CUSTOM_ELASTIC_PASSWORD=""
CUSTOM_KIBANA_PASSWORD=""

KIBANA_ENROLLMENT_TOKEN=""
KIBANA_ENC_KEY=""

EPR_URL=""                  # local Elastic Package Registry URL (optional)

CCS_ENABLED=false           # true if CCS access from ECH will be configured
CCS_PUBLIC_HOST=""          # public IP/hostname ECH will connect to on port 9200
CCS_API_KEY=""              # cross-cluster API key (encoded) for ECH
CA_FINGERPRINT=""           # SHA-256 fingerprint of the ES HTTP CA cert

OS_FAMILY=""
PKG_MANAGER=""
ARCH=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/elastic-install-$(date +%Y%m%d-%H%M%S).log"
SUMMARY_FILE="${SCRIPT_DIR}/elastic-install-summary.txt"

# ── Output helpers ────────────────────────────────────────────────────────────
_ts()     { date +"%Y-%m-%d %H:%M:%S"; }
log()     { echo "[$(_ts)] $*" >> "$LOG_FILE"; }
die()     { echo -e "\n${RED}✗  ERROR: $*${NC}\n" >&2; log "ERROR: $*"; exit 1; }
warn()    { echo -e "${YELLOW}⚠  $*${NC}"; log "WARN:    $*"; }
success() { echo -e "${GREEN}✔  $*${NC}";  log "OK:      $*"; }
info()    { echo -e "${CYAN}→  $*${NC}";   log "INFO:    $*"; }
step()    { echo -e "\n${BOLD}${BLUE}▸ $*${NC}"; log ""; log "▸▸ STEP: $*"; }
hr()      { echo -e "${DIM}$(printf '─%.0s' {1..72})${NC}"; }

run_with_spinner() {
  local label="$1"; shift
  local spin='-\|/'
  local i=0
  printf "  ${CYAN}→${NC}  %s" "$label"
  "$@" >> "$LOG_FILE" 2>&1 &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${CYAN}[%s]${NC} %s" "${spin:$((i % 4)):1}" "$label"
    sleep 0.2
    (( i++ )) || true
  done
  wait "$pid"
  local rc=$?
  printf "\r%-80s\r" ""
  return $rc
}

banner() {
  printf "\033[0m\n"
  printf "\033[97m                   _____\n"
  printf "\033[97m               _gP\"\033[38;5;220m_ggg_\033[97m\"4g_\n"
  printf "\033[97m       _mD=B__@\033[38;5;220m_@@@@@@@@@@@_\033[97m@,\n"
  printf "\033[97m     ,P\033[38;5;205mo@@@@|\033[97m@\033[38;5;220m[@@@@@@@@@@@@@g\033[97mT\\\\\n"
  printf "\033[97m     @\033[38;5;205m{@@@@@\033[97m;/\033[38;5;220m@@@@@@@@@@@@@@@g\033[97m@\n"
  printf "\033[97m     \$_\033[38;5;205m\"=B@W\033[97m@\033[38;5;220m;@@@@@@@@@@@@@@@@\033[97m[\n"
  printf "\033[97m  _D\033[38;5;39m_@@g_\033[97m\"\"=@\033[38;5;220mf@@@@@@@@@@@@@@@\"\033[97m@L\n"
  printf "\033[97m J/\033[38;5;39m@@@@@@@@@\033[97m'g\033[38;5;220m9@@@@@@@@@@@B\033[97m_B\033[38;5;32m_@@_\033[97mQ,\n"
  printf "\033[97m @\033[38;5;39m@@@@@@@@@B\033[97m_B+q_\033[38;5;220m<@@@@@@P\033[97m_P\033[38;5;32m_@@@@@@\033[97mV,\n"
  printf "\033[97m @\033[38;5;39m[@@@@@@P\033[97m_P\033[38;5;37m_@@@g_\033[97m<B_\033[38;5;220m\"\"\033[97mg\"\033[38;5;32mg@@@@@@@@,\033[97m@\n"
  printf "\033[97m \`q\033[38;5;39m\\\\@@@F\033[97maF\033[38;5;37mg@@@@@@@@@@p\033[97m%%\033[38;5;32m'@@@@@@@@@@\033[97m//\n"
  printf "\033[97m   \"%%_@\"\033[38;5;37m@@@@@@@@@@@@@@g\033[97mt_\033[38;5;32m4B@@@@@P\033[97m/F\n"
  printf "\033[97m     @\033[38;5;37m|@@@@@@@@@@@@@@@@\033[97m;F\033[38;5;112m_\033[97m\"\"4DgD\"\n"
  printf "\033[97m     9\033[38;5;37m'@@@@@@@@@@@@@@@W\033[97m@\033[38;5;112m!@@@@@\033[97m|,\n"
  printf "\033[97m      g\033[38;5;37m0@@@@@@@@@@@@@@'\033[97mN\033[38;5;112m@@@@@P\033[97m@\n"
  printf "\033[97m      '@\033[38;5;37m\"@@@@@@@@@@@@P\033[97mgq\033[38;5;112m\"<*\"\033[97m~P\n"
  printf "\033[97m        \"q_\033[38;5;37m4@@@@@@P\"\033[97md\"\n"
  printf "\033[97m           '<=BB=>\"\n"
  printf "\033[0m\n"
  echo ""
}

# Prompt with optional default. Sets $REPLY.
prompt() {
  local msg="$1" default="${2:-}"
  if [[ -n "$default" ]]; then
    echo -en "${BOLD}${msg}${NC} ${DIM}[${default}]${NC}: "
  else
    echo -en "${BOLD}${msg}${NC}: "
  fi
  read -r REPLY
  if [[ -z "$REPLY" && -n "$default" ]]; then REPLY="$default"; fi
}

# Yes/no confirm. Returns 0 for yes, 1 for no.
confirm() {
  local msg="$1" default="${2:-Y}"
  local hint
  [[ "$default" == "Y" ]] && hint="[Y/n]" || hint="[y/N]"
  echo -en "${BOLD}${msg}${NC} ${DIM}${hint}${NC}: "
  read -r REPLY
  if [[ -z "$REPLY" ]]; then REPLY="$default"; fi
  [[ "$REPLY" =~ ^[Yy]$ ]]
}

# Read a password silently, confirm it, enforce min length. Sets named variable.
prompt_password() {
  local msg="$1" varname="$2"
  local pw pw2
  while true; do
    echo -en "${BOLD}${msg}${NC}: "
    read -rs pw
    echo ""
    if [[ ${#pw} -lt 6 ]]; then
      warn "Password must be at least 6 characters. Try again."
      continue
    fi
    echo -en "${BOLD}Confirm password${NC}: "
    read -rs pw2
    echo ""
    if [[ "$pw" == "$pw2" ]]; then
      printf -v "$varname" '%s' "$pw"
      return 0
    fi
    warn "Passwords do not match. Try again."
  done
}

# Return non-loopback IPv4 addresses, one per line.
_detect_ips() {
  ip -4 addr show 2>/dev/null \
    | awk '/inet / && !/127\.0\.0\.1/ { gsub(/\/[0-9]+/, "", $2); print $2 }' \
    || true
}

# Present a numbered list of local IPs and let the user pick one.
# Sets the named variable to the chosen address.
pick_bind_ip() {
  local service="$1" varname="$2"
  local -a ips
  mapfile -t ips < <(_detect_ips)

  local i=1
  for ip in "${ips[@]}"; do
    echo -e "    ${BOLD}${i})${NC} ${ip}"
    (( i++ )) || true
  done
  local all_idx=$i
  echo -e "    ${BOLD}${i})${NC} 0.0.0.0  ${DIM}(all interfaces)${NC}"
  (( i++ )) || true
  local manual_idx=$i
  echo -e "    ${BOLD}${i})${NC} Enter manually"
  echo ""

  local default_choice=1
  if [[ ${#ips[@]} -eq 0 ]]; then default_choice=$all_idx; fi

  prompt "Bind address for ${service}" "$default_choice"
  local choice="$REPLY"

  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    local idx=$(( choice - 1 ))
    if [[ $idx -lt ${#ips[@]} ]]; then
      printf -v "$varname" '%s' "${ips[$idx]}"
    elif [[ $choice -eq $all_idx ]]; then
      printf -v "$varname" '%s' "0.0.0.0"
    else
      prompt "Enter IP address" ""
      printf -v "$varname" '%s' "$REPLY"
    fi
  else
    printf -v "$varname" '%s' "$choice"
  fi
}

# ── OS Detection ──────────────────────────────────────────────────────────────
detect_os() {
  step "Detecting operating system"

  [[ -f /etc/os-release ]] || die "Cannot detect OS — /etc/os-release not found."
  # shellcheck disable=SC1091
  source /etc/os-release

  local os_id="${ID:-unknown}"
  local os_id_like="${ID_LIKE:-}"
  local os_version="${VERSION_ID:-}"

  case "$os_id" in
    rhel|centos|rocky|almalinux|ol|fedora)
      OS_FAMILY="rhel" ;;
    ubuntu|debian|linuxmint|pop)
      OS_FAMILY="debian" ;;
    *)
      if [[ "$os_id_like" =~ rhel|fedora ]]; then
        OS_FAMILY="rhel"
      elif [[ "$os_id_like" =~ debian ]]; then
        OS_FAMILY="debian"
      else
        die "Unsupported OS: ${os_id}. Supported: RHEL/CentOS/Rocky/AlmaLinux, Ubuntu/Debian."
      fi
      ;;
  esac

  if [[ "$OS_FAMILY" == "rhel" ]]; then
    command -v dnf &>/dev/null && PKG_MANAGER="dnf" || PKG_MANAGER="yum"
  else
    PKG_MANAGER="apt-get"
  fi

  success "Detected: ${os_id} ${os_version} (${OS_FAMILY} family)"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64)        ARCH="x86_64" ;;
    aarch64|arm64) ARCH="arm64"  ;;
    *)             die "Unsupported architecture: $(uname -m). Only x86_64 and arm64 are supported." ;;
  esac
  success "Architecture: ${ARCH}"
}

# ── Prerequisite Checks ───────────────────────────────────────────────────────
check_prerequisites() {
  step "Checking prerequisites"

  [[ $EUID -eq 0 ]] || die "This script must be run as root (or via sudo)."
  command -v systemctl &>/dev/null || die "systemd is required."
  command -v curl     &>/dev/null || die "curl is required but not installed. Install it from your local package repository."
  command -v python3  &>/dev/null || die "python3 is required but not installed. Install it from your local package repository."

  local checks_passed=true

  local cpu_cores
  cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 0)
  if [[ $cpu_cores -lt 8 ]]; then
    warn "CPU: ${cpu_cores} core(s) detected — minimum recommended is 8 cores."
    checks_passed=false
  else
    success "CPU: ${cpu_cores} cores — OK"
  fi

  local ram_gb
  ram_gb=$(awk '/MemTotal/ { printf "%d", $2/1024/1024 }' /proc/meminfo)
  if [[ $ram_gb -lt 32 ]]; then
    warn "RAM: ${ram_gb}GB detected — minimum recommended is 32GB."
    checks_passed=false
  else
    success "RAM: ${ram_gb}GB — OK"
  fi

  local free_gb
  free_gb=$(df -BG /var/lib 2>/dev/null | awk 'NR==2 { gsub(/G/,"",$4); print $4 }') || true
  if [[ -n "$free_gb" && $free_gb -lt 200 ]]; then
    warn "Disk: ${free_gb}GB free on /var/lib — minimum recommended is 200GB."
    checks_passed=false
  else
    success "Disk: ${free_gb}GB free on /var/lib — OK"
  fi

  # ── fontconfig (required by Kibana headless PDF/PNG reporting) ───────────────
  if [[ "$OS_FAMILY" == "rhel" ]]; then
    if rpm -q fontconfig &>/dev/null; then
      success "fontconfig — OK"
    else
      warn "fontconfig not installed — Kibana PDF/PNG reporting may fail."
      warn "Install from your internal package mirror before or after this run."
      checks_passed=false
    fi
  else
    if dpkg -s fontconfig &>/dev/null 2>&1; then
      success "fontconfig — OK"
    else
      warn "fontconfig not installed — Kibana PDF/PNG reporting may fail."
      warn "Install from your internal package mirror before or after this run."
      checks_passed=false
    fi
  fi

  if [[ "$checks_passed" == "false" ]]; then
    echo ""
    confirm "  System does not meet all recommended specifications. Continue anyway?" "N" \
      || die "Aborted by user."
  else
    success "All prerequisite checks passed"
  fi
}

# ── Package directory and validation ─────────────────────────────────────────
menu_pkg_dir() {
  step "Package directory"
  echo ""
  info "Specify the directory containing your pre-downloaded Elastic packages."
  info "Required files:"
  if [[ "$OS_FAMILY" == "rhel" ]]; then
    info "  elasticsearch-<version>-<release>.x86_64.rpm  (or aarch64)"
    info "  kibana-<version>-<release>.x86_64.rpm  (or aarch64)"
  else
    info "  elasticsearch-<version>-amd64.deb  (or arm64)"
    info "  kibana-<version>-amd64.deb  (or arm64)"
  fi
  info "  elastic-agent-<version>-linux-${ARCH}.tar.gz"
  echo ""

  while true; do
    prompt "Package directory" "${SCRIPT_DIR}"
    local dir="$REPLY"
    if [[ -d "$dir" ]]; then
      PKG_DIR="$dir"
      break
    else
      warn "Directory '${dir}' does not exist. Please try again."
    fi
  done
}

validate_packages() {
  step "Validating packages"
  echo ""

  local pkg_ext
  [[ "$OS_FAMILY" == "rhel" ]] && pkg_ext="rpm" || pkg_ext="deb"

  # Find packages (search up to 2 levels deep)
  ES_PKG=$(find "$PKG_DIR" -maxdepth 2 -name "elasticsearch-*.${pkg_ext}" 2>/dev/null \
    | sort | head -1 || true)
  KIBANA_PKG=$(find "$PKG_DIR" -maxdepth 2 -name "kibana-*.${pkg_ext}" 2>/dev/null \
    | sort | head -1 || true)
  AGENT_TARBALL=$(find "$PKG_DIR" -maxdepth 2 \
    -name "elastic-agent-*-linux-${ARCH}.tar.gz" 2>/dev/null \
    | sort | head -1 || true)

  # Report what was found / missing
  local missing=()
  if [[ -n "$ES_PKG" ]]; then
    echo -e "  ${GREEN}✔${NC} Elasticsearch:  $(basename "$ES_PKG")"
  else
    echo -e "  ${RED}✗${NC} Elasticsearch:  no elasticsearch-*.${pkg_ext} found"
    missing+=("elasticsearch")
  fi

  if [[ -n "$KIBANA_PKG" ]]; then
    echo -e "  ${GREEN}✔${NC} Kibana:         $(basename "$KIBANA_PKG")"
  else
    echo -e "  ${RED}✗${NC} Kibana:         no kibana-*.${pkg_ext} found"
    missing+=("kibana")
  fi

  if [[ -n "$AGENT_TARBALL" ]]; then
    echo -e "  ${GREEN}✔${NC} Elastic Agent:  $(basename "$AGENT_TARBALL")"
  else
    echo -e "  ${RED}✗${NC} Elastic Agent:  no elastic-agent-*-linux-${ARCH}.tar.gz found"
    missing+=("elastic-agent")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo ""
    die "Missing packages: $(IFS=', '; echo "${missing[*]}"). Place all three packages in ${PKG_DIR} and try again."
  fi

  # Extract and compare versions
  local es_ver kibana_ver agent_ver
  es_ver=$(basename    "$ES_PKG"      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
  kibana_ver=$(basename "$KIBANA_PKG" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
  agent_ver=$(basename  "$AGENT_TARBALL" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)

  if [[ -z "$es_ver" || -z "$kibana_ver" || -z "$agent_ver" ]]; then
    die "Could not extract version from one or more package filenames. Ensure files follow the standard Elastic naming convention."
  fi

  if [[ "$es_ver" != "$kibana_ver" || "$es_ver" != "$agent_ver" ]]; then
    echo ""
    warn "Version mismatch detected:"
    echo -e "  Elasticsearch: ${BOLD}${es_ver}${NC}"
    echo -e "  Kibana:        ${BOLD}${kibana_ver}${NC}"
    echo -e "  Elastic Agent: ${BOLD}${agent_ver}${NC}"
    echo ""
    die "All packages must be the same version. Download matching packages and try again."
  fi

  ELASTIC_VERSION="$es_ver"
  ELASTIC_MAJOR="${ELASTIC_VERSION%%.*}"

  echo ""
  success "All packages validated — Elastic Stack ${ELASTIC_VERSION}"
}

# ── Interactive Menus ─────────────────────────────────────────────────────────
menu_server_name() {
  step "Server name"
  echo ""
  prompt "Cluster name" "$CLUSTER_NAME"
  CLUSTER_NAME="$REPLY"
  prompt "Node name" "$(hostname -s)"
  NODE_NAME="$REPLY"
  success "Cluster: ${CLUSTER_NAME}  /  Node: ${NODE_NAME}"
}

menu_network() {
  step "Network binding"
  echo ""
  info "Select the IP address each service should bind to."
  info "Choose a specific IP so Fleet agents can reach each service."
  echo ""

  echo -e "  ${BOLD}Elasticsearch${NC}  (port 9200)"
  pick_bind_ip "Elasticsearch" NETWORK_HOST
  echo ""

  echo -e "  ${BOLD}Kibana${NC}  (port 5601)"
  pick_bind_ip "Kibana" KIBANA_HOST
  echo ""

  echo -e "  ${BOLD}Fleet Server${NC}  (port 8220)"
  pick_bind_ip "Fleet Server" FLEET_HOST
  echo ""
}

menu_data_dirs() {
  step "Elasticsearch data and log directories"
  echo ""
  info "Where should Elasticsearch store its data and write its logs?"
  echo ""
  prompt "Data directory" "$ES_DATA_DIR"
  ES_DATA_DIR="$REPLY"
  prompt "Log directory" "$ES_LOG_DIR"
  ES_LOG_DIR="$REPLY"
  success "Data: ${ES_DATA_DIR}   /   Logs: ${ES_LOG_DIR}"
}

menu_epr() {
  step "Elastic Package Registry (EPR)"
  echo ""
  info "Fleet integrations are fetched from the Elastic Package Registry (EPR)."
  info "Without a local EPR, you will not be able to install integrations from"
  info "the Kibana Fleet UI after install."
  info ""
  info "EPR runs as a Docker container:"
  info "  docker run -p 8080:8080 docker.elastic.co/package-registry/distribution:latest"
  echo ""

  EPR_URL=""
  if confirm "  Do you have a local EPR running?" "N"; then
    local detected_ip
    detected_ip=$(hostname -I | awk '{print $1}')
    prompt "EPR URL" "http://${detected_ip}:8080"
    EPR_URL="$REPLY"
    success "Fleet will use local EPR: ${EPR_URL}"
  else
    warn "No local EPR configured — Fleet integrations will not be installable from Kibana."
    warn "You can add it later: set xpack.fleet.registryUrl in /etc/kibana/kibana.yml"
  fi
}

menu_ccs() {
  step "Cross-Cluster Search from Elastic Cloud Hosted (ECH)"
  echo ""
  info "If an ECH deployment will query this cluster via Cross-Cluster Search,"
  info "the installer can generate a cross-cluster API key and print the steps"
  info "needed in the ECH console to complete the connection."
  info ""
  info "CCS uses standard HTTPS on port 9200 (already opened in the firewall)."
  info "Ensure any upstream router or security group also allows inbound 9200"
  info "from ECH's egress IPs."
  echo ""

  CCS_ENABLED=false
  CCS_PUBLIC_HOST=""
  if confirm "  Set up CCS access from ECH?" "N"; then
    CCS_ENABLED=true
    local detected_ip
    detected_ip=$(hostname -I | awk '{print $1}')
    info "  Enter the IP address or hostname that ECH will use to reach port 9200."
    info "  Must be publicly routable — not 0.0.0.0 or 127.0.0.1."
    echo ""
    prompt "Public host / IP for this Elasticsearch cluster" "$detected_ip"
    CCS_PUBLIC_HOST="$REPLY"
    success "CCS enabled — cross-cluster API key will be created after install."
  fi
}

menu_passwords() {
  step "User passwords"
  echo ""
  info "You can set custom passwords now, or let the installer auto-generate them."
  echo ""

  if confirm "  Set a custom password for the 'elastic' superuser?" "N"; then
    echo ""
    prompt_password "Password for 'elastic'" CUSTOM_ELASTIC_PASSWORD
    success "Password for 'elastic' noted"
  fi
  echo ""

  if confirm "  Set a custom password for the 'kibana_system' user?" "N"; then
    echo ""
    prompt_password "Password for 'kibana_system'" CUSTOM_KIBANA_PASSWORD
    success "Password for 'kibana_system' noted"
  fi
}

menu_confirm() {
  step "Configuration summary"
  echo ""
  hr
  echo -e "  ${BOLD}Elastic Stack:${NC}  ${ELASTIC_VERSION}"
  echo -e "  ${BOLD}Topology:${NC}       Single-node (air-gapped)"
  echo ""
  echo -e "  ${BOLD}Packages:${NC}"
  echo -e "    $(basename "$ES_PKG")"
  echo -e "    $(basename "$KIBANA_PKG")"
  echo -e "    $(basename "$AGENT_TARBALL")"
  echo ""
  echo -e "  ${BOLD}Cluster:${NC}    ${CLUSTER_NAME}"
  echo -e "  ${BOLD}Node name:${NC}  ${NODE_NAME}"
  echo ""
  echo -e "  ${BOLD}ES paths:${NC}"
  echo -e "    Data:  ${ES_DATA_DIR}"
  echo -e "    Logs:  ${ES_LOG_DIR}"
  echo ""
  echo -e "  ${BOLD}Bind addresses:${NC}"
  echo -e "    Elasticsearch:  ${NETWORK_HOST}:9200"
  echo -e "    Kibana:         ${KIBANA_HOST}:5601"
  echo -e "    Fleet Server:   ${FLEET_HOST}:8220"
  echo ""
  echo -e "  ${BOLD}Passwords:${NC}"
  if [[ -n "$CUSTOM_ELASTIC_PASSWORD" ]]; then
    echo -e "    elastic:        ${GREEN}custom${NC}"
  else
    echo -e "    elastic:        ${DIM}auto-generated${NC}"
  fi
  if [[ -n "$CUSTOM_KIBANA_PASSWORD" ]]; then
    echo -e "    kibana_system:  ${GREEN}custom${NC}"
  else
    echo -e "    kibana_system:  ${DIM}auto-generated${NC}"
  fi
  echo ""
  echo -e "  ${BOLD}Fleet EPR:${NC}"
  if [[ -n "$EPR_URL" ]]; then
    echo -e "    ${GREEN}${EPR_URL}${NC}"
  else
    echo -e "    ${YELLOW}not configured — integrations will not be installable from Kibana${NC}"
  fi
  echo ""
  echo -e "  ${BOLD}CCS from ECH:${NC}"
  if [[ "$CCS_ENABLED" == true ]]; then
    echo -e "    ${GREEN}${CCS_PUBLIC_HOST}:9200${NC}"
  else
    echo -e "    ${DIM}not configured${NC}"
  fi
  echo ""
  hr
  echo ""
  confirm "Proceed with installation?" "Y" || die "Installation cancelled."
}

# ── Idempotency helpers ───────────────────────────────────────────────────────
is_pkg_installed() {
  local pkg="$1"
  if [[ "$OS_FAMILY" == "debian" ]]; then
    dpkg -s "$pkg" &>/dev/null
  else
    rpm -q "$pkg" &>/dev/null
  fi
}

is_configured() {
  local conf="$1"
  [[ -f "${conf}.bak" ]]
}

recover_es_password() {
  local prev_log recovered=""
  while IFS= read -r prev_log; do
    recovered=$(grep "CREDENTIAL: elastic_password" "$prev_log" 2>/dev/null \
      | tail -1 | sed 's/.*=//' || true)
    if [[ -n "$recovered" ]]; then break; fi
  done < <(ls -t "${SCRIPT_DIR}"/elastic-install-*.log 2>/dev/null \
    | grep -v "$(basename "$LOG_FILE")" || true)

  if [[ -z "$recovered" ]]; then
    # No credential found in any previous log — nothing to recover; caller will auto-reset
    return 1
  fi

  if curl -skf "${ES_LOCAL_URL}/_cluster/health" \
      -u "elastic:${recovered}" -o /dev/null 2>/dev/null; then
    ES_PASSWORD="$recovered"
    info "Recovered elastic password from previous install log"
    return 0
  fi

  info "Found previous password in log but it no longer works — prompting"
  echo ""
  echo -en "${BOLD}  Enter existing 'elastic' password${NC}: "
  read -rs ES_PASSWORD
  echo ""
  if curl -skf "${ES_LOCAL_URL}/_cluster/health" \
      -u "elastic:${ES_PASSWORD}" -o /dev/null 2>/dev/null; then
    success "Authenticated with provided password"
    log "CREDENTIAL: elastic_password (recovered manually)=${ES_PASSWORD}"
    return 0
  fi
  warn "Could not authenticate with provided password — will reset it"
  ES_PASSWORD=""
  return 1
}

# ── Install helpers ───────────────────────────────────────────────────────────
install_elasticsearch() {
  if is_pkg_installed "elasticsearch"; then
    info "Elasticsearch already installed — skipping package install"
    return
  fi
  step "Installing Elasticsearch ${ELASTIC_VERSION}"

  if [[ "$OS_FAMILY" == "rhel" ]]; then
    run_with_spinner "Installing elasticsearch" \
      rpm --nosignature -ivh "$ES_PKG" \
      || die "Failed to install Elasticsearch — check ${LOG_FILE}"
  else
    run_with_spinner "Installing elasticsearch" \
      dpkg -i "$ES_PKG" \
      || die "Failed to install Elasticsearch — check ${LOG_FILE}"
  fi
  success "Elasticsearch installed"
}

install_kibana() {
  if is_pkg_installed "kibana"; then
    info "Kibana already installed — skipping package install"
    return
  fi
  step "Installing Kibana ${ELASTIC_VERSION}"

  if [[ "$OS_FAMILY" == "rhel" ]]; then
    run_with_spinner "Installing kibana" \
      rpm --nosignature -ivh "$KIBANA_PKG" \
      || die "Failed to install Kibana — check ${LOG_FILE}"
  else
    run_with_spinner "Installing kibana" \
      dpkg -i "$KIBANA_PKG" \
      || die "Failed to install Kibana — check ${LOG_FILE}"
  fi
  success "Kibana installed"
}

prepare_fleet() {
  step "Preparing Elastic Agent ${ELASTIC_VERSION}"

  local extract_dir="${SCRIPT_DIR}/elastic-agent-${ELASTIC_VERSION}-linux-${ARCH}"
  AGENT_TARBALL_DIR="$extract_dir"

  if [[ -f "${extract_dir}/elastic-agent" ]]; then
    info "Elastic Agent already extracted at ${extract_dir} — skipping"
    success "Elastic Agent ready at ${AGENT_TARBALL_DIR}"
    return
  fi

  run_with_spinner "Extracting elastic-agent" \
    tar xzf "$AGENT_TARBALL" -C "$SCRIPT_DIR" \
    || die "Failed to extract Elastic Agent — check ${LOG_FILE}"

  success "Elastic Agent ready at ${AGENT_TARBALL_DIR}"
}

# ── Configuration ─────────────────────────────────────────────────────────────
configure_elasticsearch() {
  local conf="/etc/elasticsearch/elasticsearch.yml"
  if is_configured "$conf"; then
    info "Elasticsearch already configured — skipping"
    return
  fi
  step "Configuring Elasticsearch"

  local jvm_dir="/etc/elasticsearch/jvm.options.d"
  cp "$conf" "${conf}.bak"

  local ram_mb heap_mb
  ram_mb=$(awk '/MemTotal/ { printf "%d", $2/1024 }' /proc/meminfo)
  heap_mb=$(( ram_mb / 2 ))
  if [[ $heap_mb -gt 31744 ]]; then heap_mb=31744; fi
  if [[ $heap_mb -lt 512 ]];   then heap_mb=512;   fi

  mkdir -p "$jvm_dir"
  cat > "${jvm_dir}/heap.options" <<EOF
-Xms${heap_mb}m
-Xmx${heap_mb}m
EOF

  # When binding to a specific IP, also bind to loopback so Fleet Server's
  # internal monitoring components (which default to 127.0.0.1) can reach ES.
  # http.publish_host ensures ES advertises only the user-selected IP externally.
  local net_host_yaml="$NETWORK_HOST"
  local publish_host_yaml=""
  if [[ "$NETWORK_HOST" != "0.0.0.0" && "$NETWORK_HOST" != "127.0.0.1" ]]; then
    net_host_yaml="[\"${NETWORK_HOST}\", \"_local_\"]"
    publish_host_yaml="http.publish_host: ${NETWORK_HOST}"
  fi

  cat > "$conf" <<EOF
# ── Elastic Stack — Single-node (Air-Gapped) ─────────────────────────────────
cluster.name: ${CLUSTER_NAME}
node.name: ${NODE_NAME}

# Paths
path.data: ${ES_DATA_DIR}
path.logs: ${ES_LOG_DIR}

# Network — bound to selected IP plus loopback for internal Fleet monitoring
network.host: ${net_host_yaml}
${publish_host_yaml}
http.port: 9200

# Single-node discovery (no cluster formation)
discovery.type: single-node

# Air-gapped: disable GeoIP database auto-updates (requires internet)
ingest.geoip.downloader.enabled: false

# Security (enabled by default in 8.x / 9.x)
xpack.security.enabled: true
xpack.security.enrollment.enabled: true

xpack.security.http.ssl:
  enabled: true
  keystore.path: certs/http.p12

xpack.security.transport.ssl:
  enabled: true
  verification_mode: certificate
  keystore.path: certs/transport.p12
  truststore.path: certs/transport.p12
EOF

  mkdir -p "$ES_DATA_DIR" "$ES_LOG_DIR"
  chown elasticsearch:elasticsearch "$ES_DATA_DIR" "$ES_LOG_DIR"
  log "Directories: data=${ES_DATA_DIR} logs=${ES_LOG_DIR}"

  open_firewall_port 9200
  success "Elasticsearch configured (JVM heap: ${heap_mb}MB)"
}

configure_kibana() {
  local conf="/etc/kibana/kibana.yml"
  if is_configured "$conf"; then
    info "Kibana already configured — skipping"
    KIBANA_ENC_KEY=$(grep "encryptedSavedObjects.encryptionKey" "$conf" 2>/dev/null \
      | sed "s/.*: *['\"]//; s/['\"]$//" || true)
    return
  fi
  step "Configuring Kibana"

  cp "$conf" "${conf}.bak"

  KIBANA_ENC_KEY=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 || true)

  local es_conn_host="$NETWORK_HOST"
  if [[ "$es_conn_host" == "0.0.0.0" ]]; then es_conn_host="127.0.0.1"; fi

  local kibana_pub_host="$KIBANA_HOST"
  if [[ "$kibana_pub_host" == "0.0.0.0" ]]; then
    kibana_pub_host=$(hostname -I | awk '{print $1}')
  fi

  cat > "$conf" <<EOF
# ── Kibana Configuration ──────────────────────────────────────────────────────
server.port: 5601
server.host: "${KIBANA_HOST}"
server.name: "$(hostname -s)"
server.publicBaseUrl: "http://${kibana_pub_host}:5601"

# Elasticsearch connection
elasticsearch.hosts: ["https://${es_conn_host}:9200"]

# Required for Fleet
xpack.encryptedSavedObjects.encryptionKey: "${KIBANA_ENC_KEY}"

# Air-gapped: disable Elastic Maps Service tiles (requires internet)
map.includeElasticMapsService: false

# Air-gapped: disable usage telemetry
telemetry.enabled: false
telemetry.optIn: false

# Air-gapped: disable AI Assistant knowledge-base artifact downloads
# Remove this line (and configure an LLM connector) to re-enable the AI Assistant
xpack.observabilityAIAssistant.enabled: false

# Logging
logging.appenders.file.type: file
logging.appenders.file.fileName: /var/log/kibana/kibana.log
logging.appenders.file.layout.type: json
logging.root.appenders: [default, file]
EOF

  # Append local EPR URL if configured
  if [[ -n "$EPR_URL" ]]; then
    {
      echo ""
      echo "# Air-gapped: local Elastic Package Registry"
      echo "xpack.fleet.registryUrl: \"${EPR_URL}\""
    } >> "$conf"
    info "Fleet configured to use local EPR: ${EPR_URL}"
  fi

  open_firewall_port 5601
  success "Kibana configured"
}

# ── Firewall helpers ──────────────────────────────────────────────────────────
open_firewall_port() {
  local port="$1"
  if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
    firewall-cmd --permanent --add-port="${port}/tcp" >> "$LOG_FILE" 2>&1
    firewall-cmd --reload >> "$LOG_FILE" 2>&1
    log "firewalld: opened port ${port}/tcp"
  elif command -v ufw &>/dev/null; then
    if ufw status 2>/dev/null | grep -q "Status: active"; then
      ufw allow "${port}/tcp" >> "$LOG_FILE" 2>&1
      log "ufw: opened port ${port}/tcp"
    fi
  fi
}

# ── Service management ────────────────────────────────────────────────────────
start_service() {
  local svc="$1"
  systemctl daemon-reload >> "$LOG_FILE" 2>&1
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    info "${svc} is already running"
    return 0
  fi
  step "Starting ${svc}"
  systemctl enable "$svc" >> "$LOG_FILE" 2>&1
  systemctl start  "$svc" >> "$LOG_FILE" 2>&1 || true

  local retries=12 elapsed=0
  while [[ $retries -gt 0 ]]; do
    if systemctl is-active --quiet "$svc"; then
      printf "\r%-80s\r" ""
      success "${svc} is running"
      return 0
    fi
    printf "\r  ${CYAN}[●]${NC} Waiting for ${svc} to start... ${DIM}%ds${NC}" "$elapsed"
    sleep 5
    (( retries-- )) || true
    (( elapsed += 5 )) || true
  done
  printf "\r%-80s\r" ""
  warn "${svc} did not become active within 60s"
  warn "Check: journalctl -u ${svc} -n 50 --no-pager"
}

wait_for_es() {
  info "Waiting for Elasticsearch to accept connections on :9200..."
  local retries=24 elapsed=0
  while [[ $retries -gt 0 ]]; do
    if curl -sk "${ES_LOCAL_URL}" -o /dev/null 2>/dev/null; then
      printf "\r%-80s\r" ""
      return 0
    fi
    printf "\r  ${CYAN}[●]${NC} Elasticsearch not yet up... ${DIM}%ds${NC}" "$elapsed"
    sleep 5
    (( retries-- )) || true
    (( elapsed += 5 )) || true
  done
  printf "\r%-80s\r" ""
  warn "Elasticsearch not responding after 120s — subsequent steps may fail."
  return 1
}

wait_for_kibana() {
  info "Waiting for Kibana to become ready on :5601..."
  local retries=36 elapsed=0
  while [[ $retries -gt 0 ]]; do
    local status
    status=$(curl -sk "${KIBANA_LOCAL_URL}/api/status" 2>/dev/null \
      | grep -o '"level":"[^"]*"' | head -1 | grep -o '[^"]*"$' | tr -d '"') || true
    if [[ "$status" == "available" || "$status" == "degraded" ]]; then
      printf "\r%-80s\r" ""
      success "Kibana is ready"
      return 0
    fi
    printf "\r  ${CYAN}[●]${NC} Kibana not yet ready... ${DIM}%ds${NC}" "$elapsed"
    sleep 5
    (( retries-- )) || true
    (( elapsed += 5 )) || true
  done
  printf "\r%-80s\r" ""
  warn "Kibana not ready after 180s — Fleet Server setup may fail."
  return 1
}

wait_for_fleet_server() {
  local fleet_host="$1"
  info "Waiting for Fleet Server to become healthy on :8220..."
  local retries=36 elapsed=0
  while [[ $retries -gt 0 ]]; do
    if curl -sk "https://${fleet_host}:8220/api/status" -o /dev/null 2>/dev/null; then
      printf "\r%-80s\r" ""
      success "Fleet Server is healthy"
      return 0
    fi
    printf "\r  ${CYAN}[●]${NC} Fleet Server not yet ready... ${DIM}%ds${NC}" "$elapsed"
    sleep 5
    (( retries-- )) || true
    (( elapsed += 5 )) || true
  done
  printf "\r%-80s\r" ""
  warn "Fleet Server not responding after 180s."
  return 1
}

# ── Post-install security setup ───────────────────────────────────────────────
setup_es_security() {
  step "Setting Elasticsearch credentials"
  wait_for_es || return 0

  if [[ -z "$ES_PASSWORD" ]]; then
    local has_prev_log=false
    if ls "${SCRIPT_DIR}"/elastic-install-*.log 2>/dev/null \
        | grep -qv "$(basename "$LOG_FILE")"; then
      has_prev_log=true
    fi

    if [[ "$has_prev_log" == true ]] && recover_es_password; then
      if [[ -n "$CUSTOM_ELASTIC_PASSWORD" ]] && \
         [[ "$ES_PASSWORD" != "$CUSTOM_ELASTIC_PASSWORD" ]]; then
        : # fall through to apply custom password
      else
        return 0
      fi
    fi
  fi

  if [[ -z "$ES_PASSWORD" ]]; then
    info "Auto-generating elastic user password..."
    local pw_output
    pw_output=$(/usr/share/elasticsearch/bin/elasticsearch-reset-password \
      -u elastic -a -b 2>>"$LOG_FILE") || true

    ES_PASSWORD=$(echo "$pw_output" | awk '/New value:/ { print $NF }' || true)

    if [[ -n "$ES_PASSWORD" ]]; then
      log "CREDENTIAL: elastic_password (auto)=${ES_PASSWORD}"
      success "elastic auto-password set"
    else
      warn "Could not auto-extract password from reset output."
      warn "Run manually: /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic"
      ES_PASSWORD="(not captured — see above)"
      return
    fi
  fi

  if [[ -n "$CUSTOM_ELASTIC_PASSWORD" ]]; then
    info "Applying custom password for 'elastic'..."
    local escaped_pw result
    escaped_pw=$(printf '%s' "$CUSTOM_ELASTIC_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')
    result=$(curl -sk -X POST \
      "${ES_LOCAL_URL}/_security/user/elastic/_password" \
      -u "elastic:${ES_PASSWORD}" \
      -H "Content-Type: application/json" \
      -d "{\"password\": \"${escaped_pw}\"}" 2>>"$LOG_FILE") || true
    if echo "$result" | grep -qE '^[[:space:]]*\{\}[[:space:]]*$'; then
      ES_PASSWORD="$CUSTOM_ELASTIC_PASSWORD"
      log "CREDENTIAL: elastic_password (custom applied)=${ES_PASSWORD}"
      success "Custom password applied for 'elastic'"
    else
      warn "Could not apply custom password for 'elastic' — auto-generated password remains active."
      log "WARN: elastic custom password API response: ${result}"
    fi
  fi
}

setup_kibana_password() {
  if [[ -z "$CUSTOM_KIBANA_PASSWORD" ]]; then return; fi

  step "Setting kibana_system password"
  info "Applying custom password for 'kibana_system'..."
  local escaped_pw result
  escaped_pw=$(printf '%s' "$CUSTOM_KIBANA_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')
  result=$(curl -sk -X POST \
    "${ES_LOCAL_URL}/_security/user/kibana_system/_password" \
    -u "elastic:${ES_PASSWORD}" \
    -H "Content-Type: application/json" \
    -d "{\"password\": \"${escaped_pw}\"}" 2>>"$LOG_FILE") || true
  if echo "$result" | grep -qE '^[[:space:]]*\{\}[[:space:]]*$'; then
    KIBANA_SYSTEM_PASSWORD="$CUSTOM_KIBANA_PASSWORD"
    log "CREDENTIAL: kibana_system_password (custom applied)=${KIBANA_SYSTEM_PASSWORD}"
    success "Custom password applied for 'kibana_system'"
  else
    warn "Could not apply custom password for 'kibana_system'."
    log "WARN: kibana_system custom password API response: ${result}"
  fi
}

setup_kibana_enrollment() {
  if /usr/share/kibana/bin/kibana-keystore list 2>/dev/null \
      | grep -q "elasticsearch.serviceAccountToken"; then
    info "Kibana already enrolled with Elasticsearch — skipping"
    return
  fi

  step "Enrolling Kibana with Elasticsearch"

  info "Generating Kibana enrollment token..."
  local token
  token=$(/usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token \
    -s kibana 2>>"$LOG_FILE") || true

  if [[ -z "$token" ]]; then
    warn "Could not generate enrollment token automatically."
    warn "After Kibana starts, visit http://<host>:5601 and follow the setup wizard."
    return
  fi

  KIBANA_ENROLLMENT_TOKEN="$token"
  log "CREDENTIAL: kibana_enrollment_token=${token}"
  success "Enrollment token generated"

  if run_with_spinner "Enrolling Kibana with Elasticsearch" \
      /usr/share/kibana/bin/kibana-setup --enrollment-token "$token"; then
    success "Kibana enrolled"
  else
    warn "kibana-setup encountered an issue — check ${LOG_FILE}"
  fi

  local conf="/etc/kibana/kibana.yml"
  if [[ -n "$KIBANA_ENC_KEY" ]] && ! grep -q "encryptedSavedObjects" "$conf" 2>/dev/null; then
    echo "" >> "$conf"
    echo "# Required for Fleet" >> "$conf"
    echo "xpack.encryptedSavedObjects.encryptionKey: \"${KIBANA_ENC_KEY}\"" >> "$conf"
    info "Re-applied encryptedSavedObjects.encryptionKey to kibana.yml"
  fi
}

setup_fleet_server() {
  local agent_already_enrolled=false
  local host_ip_check
  host_ip_check=$(hostname -I | awk '{print $1}')
  local fleet_host_check="$FLEET_HOST"
  if [[ "$fleet_host_check" == "0.0.0.0" ]]; then fleet_host_check="$host_ip_check"; fi
  if curl -sk "https://${fleet_host_check}:8220/api/status" -o /dev/null 2>/dev/null; then
    info "Fleet Server already responding on :8220 — skipping enrollment"
    agent_already_enrolled=true
  fi

  step "Configuring Fleet Server"

  local kibana_url="${KIBANA_LOCAL_URL}"
  local ca_cert="/etc/elasticsearch/certs/http_ca.crt"

  local host_ip
  host_ip=$(hostname -I | awk '{print $1}')

  local es_host="$NETWORK_HOST"
  if [[ "$es_host" == "0.0.0.0" ]]; then es_host="$host_ip"; fi
  local fleet_host="$FLEET_HOST"
  if [[ "$fleet_host" == "0.0.0.0" ]]; then fleet_host="$host_ip"; fi

  local es_url_internal="${ES_LOCAL_URL}"
  local es_url_agents="https://${es_host}:9200"
  local fleet_url="https://${fleet_host}:8220"

  # ── Step 1: Initialize Fleet in Kibana ──────────────────────────────────────
  info "Initializing Fleet in Kibana (waiting for isInitialized)..."
  local setup_resp setup_ok=false
  local fleet_retries=24 fleet_elapsed=0
  while [[ $fleet_retries -gt 0 ]]; do
    setup_resp=$(curl -sk -X POST "${kibana_url}/api/fleet/setup" \
      -u "elastic:${ES_PASSWORD}" \
      -H "kbn-xsrf: true" \
      -H "Content-Type: application/json" 2>>"$LOG_FILE") || true
    log "Fleet setup response: ${setup_resp}"
    if echo "$setup_resp" | grep -q '"isInitialized":true'; then
      setup_ok=true
      break
    fi
    printf "\r  ${CYAN}[●]${NC} Fleet not yet initialized... ${DIM}%ds${NC}" "$fleet_elapsed"
    sleep 5
    (( fleet_retries-- )) || true
    (( fleet_elapsed += 5 )) || true
  done
  printf "\r%-80s\r" ""
  if [[ "$setup_ok" == true ]]; then
    success "Fleet initialized in Kibana"
  else
    warn "Fleet initialization did not confirm isInitialized — check ${LOG_FILE}"
  fi

  # ── Step 1.5: Ensure Fleet Server policy exists with integration ────────────
  local fleet_policy_id=""

  local policy_list_resp
  policy_list_resp=$(curl -sk \
    "${kibana_url}/api/fleet/agent_policies?kuery=is_default_fleet_server%3Atrue" \
    -u "elastic:${ES_PASSWORD}" \
    -H "kbn-xsrf: true" 2>>"$LOG_FILE") || true
  fleet_policy_id=$(echo "$policy_list_resp" | python3 -c \
    "import sys,json; items=json.load(sys.stdin).get('items',[]); print(items[0]['id'] if items else '')" \
    2>/dev/null || true)

  if [[ -z "$fleet_policy_id" ]]; then
    info "No default Fleet Server policy found — creating one..."
    local create_policy_resp
    create_policy_resp=$(curl -sk -X POST "${kibana_url}/api/fleet/agent_policies" \
      -u "elastic:${ES_PASSWORD}" \
      -H "kbn-xsrf: true" \
      -H "Content-Type: application/json" \
      -d '{"name":"Fleet Server policy","namespace":"default","is_default_fleet_server":true,"monitoring_enabled":["logs","metrics"]}' \
      2>>"$LOG_FILE") || true
    fleet_policy_id=$(echo "$create_policy_resp" | python3 -c \
      "import sys,json; print(json.load(sys.stdin).get('item',{}).get('id',''))" \
      2>/dev/null || true)
    log "Created Fleet Server policy ID: ${fleet_policy_id}"
  else
    log "Fleet Server policy ID: ${fleet_policy_id}"
    curl -sk -X PUT "${kibana_url}/api/fleet/agent_policies/${fleet_policy_id}" \
      -u "elastic:${ES_PASSWORD}" \
      -H "kbn-xsrf: true" \
      -H "Content-Type: application/json" \
      -d "{\"monitoring_enabled\":[\"logs\",\"metrics\"]}" \
      >> "$LOG_FILE" 2>&1 || true
  fi

  if [[ -n "$fleet_policy_id" ]]; then
    local pkg_policies_resp has_fleet_server_pkg
    pkg_policies_resp=$(curl -sk \
      "${kibana_url}/api/fleet/package_policies?kuery=policy_id:${fleet_policy_id}" \
      -u "elastic:${ES_PASSWORD}" \
      -H "kbn-xsrf: true" 2>>"$LOG_FILE") || true
    has_fleet_server_pkg=$(echo "$pkg_policies_resp" | python3 -c \
      "import sys,json
items=json.load(sys.stdin).get('items',[])
print('yes' if any(x.get('package',{}).get('name')=='fleet_server' for x in items) else '')" \
      2>/dev/null || true)

    if [[ -z "$has_fleet_server_pkg" ]]; then
      info "Installing Fleet Server integration into policy..."
      local fs_pkg_version
      fs_pkg_version=$(curl -sk "${kibana_url}/api/fleet/epm/packages/fleet_server" \
        -u "elastic:${ES_PASSWORD}" \
        -H "kbn-xsrf: true" 2>>"$LOG_FILE" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('item',d).get('version',''))" \
        2>/dev/null || true)
      : "${fs_pkg_version:=${ELASTIC_VERSION}}"

      local pkg_policy_body pkg_install_resp
      pkg_policy_body=$(python3 -c "
import json
print(json.dumps({
  'name': 'fleet_server-1',
  'namespace': 'default',
  'policy_id': '${fleet_policy_id}',
  'enabled': True,
  'inputs': [{'type': 'fleet-server', 'enabled': True, 'streams': [], 'vars': {}}],
  'package': {'name': 'fleet_server', 'version': '${fs_pkg_version}'}
}))")
      pkg_install_resp=$(curl -sk -X POST "${kibana_url}/api/fleet/package_policies" \
        -u "elastic:${ES_PASSWORD}" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "$pkg_policy_body" 2>>"$LOG_FILE") || true
      log "Fleet Server integration install response: ${pkg_install_resp}"
      success "Fleet Server integration installed in policy"
    else
      info "Fleet Server integration already present in policy"
    fi

    local has_elastic_agent_pkg
    has_elastic_agent_pkg=$(echo "$pkg_policies_resp" | python3 -c \
      "import sys,json
items=json.load(sys.stdin).get('items',[])
print('yes' if any(x.get('package',{}).get('name')=='elastic_agent' for x in items) else '')" \
      2>/dev/null || true)

    if [[ -z "$has_elastic_agent_pkg" ]]; then
      info "Installing Elastic Agent integration into policy..."
      local ea_pkg_version ea_pkg_body ea_pkg_resp
      ea_pkg_version=$(curl -sk "${kibana_url}/api/fleet/epm/packages/elastic_agent" \
        -u "elastic:${ES_PASSWORD}" \
        -H "kbn-xsrf: true" 2>>"$LOG_FILE" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('item',d).get('version',''))" \
        2>/dev/null || true)
      : "${ea_pkg_version:=${ELASTIC_VERSION}}"

      ea_pkg_body=$(python3 -c "
import json
print(json.dumps({
  'name': 'elastic_agent-1',
  'namespace': 'default',
  'policy_id': '${fleet_policy_id}',
  'enabled': True,
  'inputs': [],
  'package': {'name': 'elastic_agent', 'version': '${ea_pkg_version}'}
}))")
      ea_pkg_resp=$(curl -sk -X POST "${kibana_url}/api/fleet/package_policies" \
        -u "elastic:${ES_PASSWORD}" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "$ea_pkg_body" 2>>"$LOG_FILE") || true
      log "Elastic Agent integration install response: ${ea_pkg_resp}"
      success "Elastic Agent integration installed in policy"
    else
      info "Elastic Agent integration already present in policy"
    fi
  fi

  # ── Step 2: Register Fleet Server host ──────────────────────────────────────
  info "Registering Fleet Server host: ${fleet_url}..."
  local fsh_list_resp default_fsh_id
  fsh_list_resp=$(curl -sk "${kibana_url}/api/fleet/fleet_server_hosts" \
    -u "elastic:${ES_PASSWORD}" \
    -H "kbn-xsrf: true" 2>>"$LOG_FILE") || true
  default_fsh_id=$(echo "$fsh_list_resp" | python3 -c \
    "import sys,json; items=json.load(sys.stdin).get('items',[]); d=[x for x in items if x.get('is_default')]; print(d[0]['id'] if d else '')" \
    2>/dev/null || true)

  local fsh_body="{\"name\":\"Default Fleet Server\",\"host_urls\":[\"${fleet_url}\"],\"is_default\":true}"
  local fsh_resp
  if [[ -n "$default_fsh_id" ]]; then
    fsh_resp=$(curl -sk -X PUT "${kibana_url}/api/fleet/fleet_server_hosts/${default_fsh_id}" \
      -u "elastic:${ES_PASSWORD}" \
      -H "kbn-xsrf: true" \
      -H "Content-Type: application/json" \
      -d "$fsh_body" 2>>"$LOG_FILE") || true
  else
    fsh_resp=$(curl -sk -X POST "${kibana_url}/api/fleet/fleet_server_hosts" \
      -u "elastic:${ES_PASSWORD}" \
      -H "kbn-xsrf: true" \
      -H "Content-Type: application/json" \
      -d "$fsh_body" 2>>"$LOG_FILE") || true
  fi
  log "Fleet Server host response: ${fsh_resp}"

  # ── Step 3: Configure Elasticsearch output with CA fingerprint ──────────────
  if [[ -f "$ca_cert" ]]; then
    local fingerprint
    fingerprint=$(openssl x509 -fingerprint -sha256 -noout -in "$ca_cert" 2>/dev/null \
      | sed 's/.*=//; s/://g; y/ABCDEF/abcdef/') || true
    CA_FINGERPRINT="$fingerprint"
    if [[ -n "$fingerprint" ]]; then
      info "Configuring Elasticsearch output with CA fingerprint..."

      local outputs_resp default_output_id
      outputs_resp=$(curl -sk "${kibana_url}/api/fleet/outputs" \
        -u "elastic:${ES_PASSWORD}" \
        -H "kbn-xsrf: true" 2>>"$LOG_FILE") || true
      default_output_id=$(echo "$outputs_resp" | python3 -c \
        "import sys,json
items=json.load(sys.stdin).get('items',[])
d=[x for x in items if x.get('is_default')]
print(d[0]['id'] if d else 'fleet-default-output')" 2>/dev/null || true)
      : "${default_output_id:=fleet-default-output}"

      local output_resp
      output_resp=$(curl -sk -X PUT "${kibana_url}/api/fleet/outputs/${default_output_id}" \
        -u "elastic:${ES_PASSWORD}" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"default\",\"type\":\"elasticsearch\",\"hosts\":[\"${es_url_agents}\"],\"is_default\":true,\"is_default_monitoring\":true,\"ca_trusted_fingerprint\":\"${fingerprint}\"}" \
        2>>"$LOG_FILE") || true
      log "Fleet output response: ${output_resp}"
    fi
  fi

  if [[ "$agent_already_enrolled" == false ]]; then
    # ── Step 4: Generate Fleet Server service token ────────────────────────────
    info "Generating Fleet Server service token..."
    local token_json token token_name
    token_name="fleet-server-token-$(date +%s)"
    token_json=$(curl -sk -X POST \
      "${es_url_internal}/_security/service/elastic/fleet-server/credential/token/${token_name}" \
      -u "elastic:${ES_PASSWORD}" \
      -H "Content-Type: application/json" 2>>"$LOG_FILE") || true

    token=$(echo "$token_json" | python3 -c \
      "import sys,json; d=json.load(sys.stdin); print(d.get('token',{}).get('value',''))" \
      2>/dev/null || true)

    if [[ -z "$token" ]]; then
      warn "Could not generate Fleet Server service token."
      warn "Complete Fleet Server setup manually via Kibana → Fleet → Settings."
      return 0
    fi

    FLEET_SERVICE_TOKEN="$token"
    log "CREDENTIAL: fleet_service_token=${token}"
    success "Service token generated"

    # ── Step 5: Install elastic-agent as Fleet Server ─────────────────────────
    if [[ -z "$AGENT_TARBALL_DIR" || ! -f "${AGENT_TARBALL_DIR}/elastic-agent" ]]; then
      warn "Elastic Agent binary not found at ${AGENT_TARBALL_DIR}/elastic-agent"
      return 0
    fi

    info "Stopping any existing elastic-agent service..."
    systemctl stop elastic-agent >> "$LOG_FILE" 2>&1 || true
    sleep 2

    local ca_flag=""
    if [[ -f "$ca_cert" ]]; then ca_flag="--fleet-server-es-ca=${ca_cert}"; fi

    : "${fleet_policy_id:=fleet-server-policy}"

    # shellcheck disable=SC2086
    if run_with_spinner "Installing elastic-agent as Fleet Server" \
        "${AGENT_TARBALL_DIR}/elastic-agent" install \
          --fleet-server-es="${es_url_internal}" \
          --fleet-server-service-token="${token}" \
          --fleet-server-policy="${fleet_policy_id}" \
          --fleet-server-host="${fleet_host}" \
          --fleet-server-port=8220 \
          --install-servers \
          --insecure \
          --force \
          $ca_flag; then
      success "Fleet Server installed"
    else
      warn "Fleet Server installation had issues — check: journalctl -u elastic-agent -n 50"
    fi
  fi

  open_firewall_port 8220
  start_service "elastic-agent"
}

setup_ccs() {
  if [[ "$CCS_ENABLED" == false ]]; then return; fi
  step "Creating cross-cluster API key for ECH"

  wait_for_es || return 0

  info "Creating cross-cluster API key (requires Elasticsearch 8.9+)..."
  local ccs_key_json
  ccs_key_json=$(curl -sk -X POST \
    "${ES_LOCAL_URL}/_security/cross_cluster/api_key" \
    -u "elastic:${ES_PASSWORD}" \
    -H "Content-Type: application/json" \
    -d '{"name":"ech-ccs-key","access":{"search":[{"names":["*"]}]}}' \
    2>>"$LOG_FILE") || true

  CCS_API_KEY=$(echo "$ccs_key_json" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('encoded',''))" 2>/dev/null || true)

  if [[ -n "$CCS_API_KEY" ]]; then
    log "CREDENTIAL: ccs_api_key_encoded=${CCS_API_KEY}"
    success "Cross-cluster API key created"
  else
    warn "Could not create cross-cluster API key."
    warn "Create it manually after install:"
    warn "  POST /_security/cross_cluster/api_key"
    warn '  {"name":"ech-ccs-key","access":{"search":[{"names":["*"]}]}}'
    warn "Use the 'encoded' field value in the ECH remote cluster configuration."
    CCS_API_KEY="(create manually — see instructions above)"
  fi
}

# ── Summary ───────────────────────────────────────────────────────────────────
write_summary() {
  local host_ip
  host_ip=$(hostname -I | awk '{print $1}')

  local es_display_host="$NETWORK_HOST"
  if [[ "$es_display_host" == "0.0.0.0" ]]; then es_display_host="$host_ip"; fi
  local kibana_display_host="$KIBANA_HOST"
  if [[ "$kibana_display_host" == "0.0.0.0" ]]; then kibana_display_host="$host_ip"; fi
  local fleet_display_host="$FLEET_HOST"
  if [[ "$fleet_display_host" == "0.0.0.0" ]]; then fleet_display_host="$host_ip"; fi

  local ca_cert="/etc/elasticsearch/certs/http_ca.crt"

  {
    echo "════════════════════════════════════════════════════════════════════════"
    echo "  Elastic Stack Installation Summary (Air-Gapped)"
    echo "  $(date)"
    echo "════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Version:   ${ELASTIC_VERSION}"
    echo "  Topology:  Single-node"
    echo "  Cluster:   ${CLUSTER_NAME}"
    echo "  Node:      ${NODE_NAME}"
    echo "  ES Data:   ${ES_DATA_DIR}"
    echo "  ES Logs:   ${ES_LOG_DIR}"
    echo "  Log file:  ${LOG_FILE}"
    echo ""
    if [[ -n "$EPR_URL" ]]; then
      echo "  EPR URL:   ${EPR_URL}"
    else
      echo "  EPR URL:   not configured (Fleet integrations unavailable until set)"
    fi
    if [[ "$CCS_ENABLED" == true ]]; then
      echo "  CCS host:  ${CCS_PUBLIC_HOST}:9200"
    fi
    echo ""
    echo "── Packages installed ────────────────────────────────────────────────────"
    echo "  $(basename "$ES_PKG")"
    echo "  $(basename "$KIBANA_PKG")"
    echo "  $(basename "$AGENT_TARBALL")"
    echo ""
    echo "── Access URLs ──────────────────────────────────────────────────────────"
    echo "  Elasticsearch:  https://${es_display_host}:9200"
    echo "  Kibana:         http://${kibana_display_host}:5601"
    echo "  Fleet Server:   https://${fleet_display_host}:8220"
    echo ""
    echo "── Credentials ──────────────────────────────────────────────────────────"
    echo "  Elasticsearch superuser"
    echo "    Username:          elastic"
    echo "    Password:          ${ES_PASSWORD}"
    if [[ -f "$ca_cert" ]]; then echo "    CA certificate:    ${ca_cert}"; fi
    echo ""
    echo "  Kibana system user"
    echo "    Username:          kibana_system"
    if [[ -n "$KIBANA_SYSTEM_PASSWORD" ]]; then
      echo "    Password:          ${KIBANA_SYSTEM_PASSWORD}"
    else
      echo "    Password:          (managed via enrollment token)"
    fi
    echo ""
    if [[ -n "$KIBANA_ENROLLMENT_TOKEN" ]]; then
      echo "  Kibana enrollment token (single-use)"
      echo "    ${KIBANA_ENROLLMENT_TOKEN}"
      echo ""
    fi
    if [[ -n "$FLEET_SERVICE_TOKEN" ]]; then
      echo "  Fleet Server service token"
      echo "    ${FLEET_SERVICE_TOKEN}"
      echo ""
    fi
    if [[ "$CCS_ENABLED" == true ]]; then
      echo "── Cross-Cluster Search (ECH → on-prem) ──────────────────────────────────"
      echo "  On-prem Elasticsearch:  https://${CCS_PUBLIC_HOST}:9200"
      if [[ -n "$CA_FINGERPRINT" ]]; then
        echo "  CA fingerprint (SHA-256, no colons):"
        echo "    ${CA_FINGERPRINT}"
        echo "  CA certificate file:    /etc/elasticsearch/certs/http_ca.crt"
      fi
      echo "  Cross-cluster API key (encoded):"
      echo "    ${CCS_API_KEY}"
      echo ""
      echo "  Steps to complete in the ECH console:"
      echo "  1. Copy /etc/elasticsearch/certs/http_ca.crt to your workstation."
      echo "  2. ECH deployment → Security → Trusted CA → upload http_ca.crt"
      echo "  3. ECH deployment → Security → Remote clusters → Add remote cluster:"
      echo "       Name:    on-prem  (any label)"
      echo "       Mode:    Proxy"
      echo "       URL:     https://${CCS_PUBLIC_HOST}:9200"
      echo "       API key: <paste the encoded key above>"
      echo "  4. Verify in ECH Dev Console: GET /_remote/info"
      echo "  5. Run a CCS query:  GET /on-prem:<index-name>/_search"
      echo ""
      echo "  NOTE: Agent auto-upgrades from Fleet UI require internet access to"
      echo "  artifacts.elastic.co — upgrade agents manually or via the Elastic"
      echo "  Artifact Registry if you set one up locally."
      echo ""
    fi
    echo "── Service management ────────────────────────────────────────────────────"
    echo "  Start:   systemctl start  elasticsearch kibana elastic-agent"
    echo "  Stop:    systemctl stop   elasticsearch kibana elastic-agent"
    echo "  Status:  systemctl status elasticsearch kibana elastic-agent"
    echo "  Logs:    journalctl -u elasticsearch -f"
    echo ""
    echo "════════════════════════════════════════════════════════════════════════"
  } | tee "$SUMMARY_FILE"

  {
    echo ""
    echo "════════════════════════════════════════════════════════════════════════"
    echo "  CREDENTIALS — recorded at $(date)"
    echo "════════════════════════════════════════════════════════════════════════"
    echo "  elastic username:          elastic"
    echo "  elastic password:          ${ES_PASSWORD}"
    if [[ -f "$ca_cert" ]]; then echo "  CA certificate:            ${ca_cert}"; fi
    if [[ -n "$KIBANA_SYSTEM_PASSWORD" ]];  then echo "  kibana_system password:    ${KIBANA_SYSTEM_PASSWORD}"; fi
    if [[ -n "$KIBANA_ENROLLMENT_TOKEN" ]]; then echo "  kibana enrollment token:   ${KIBANA_ENROLLMENT_TOKEN}"; fi
    if [[ -n "$FLEET_SERVICE_TOKEN" ]];     then echo "  fleet service token:       ${FLEET_SERVICE_TOKEN}"; fi
    echo "════════════════════════════════════════════════════════════════════════"
  } >> "$LOG_FILE"

  echo ""
  success "Summary saved to:  ${SUMMARY_FILE}"
  success "Full install log:  ${LOG_FILE}"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  echo "Elastic air-gapped installer started at $(date)" > "$LOG_FILE"
  echo "Script location: ${SCRIPT_DIR}" >> "$LOG_FILE"
  echo "" >> "$LOG_FILE"

  clear
  banner
  echo -e "  ${BOLD}Air-Gapped Installer${NC} — installs from pre-downloaded packages"
  echo -e "  ${DIM}Install log: ${LOG_FILE}${NC}"
  echo ""
  hr
  echo ""

  detect_os
  detect_arch
  check_prerequisites

  echo ""
  hr
  echo -e "  ${BOLD}Configuration${NC}"
  hr
  echo ""

  menu_pkg_dir
  validate_packages
  menu_server_name
  menu_network
  menu_data_dirs
  menu_epr
  menu_ccs
  menu_passwords
  menu_confirm

  # Resolve connection URLs
  local es_conn_host="$NETWORK_HOST"
  if [[ "$es_conn_host" == "0.0.0.0" ]]; then es_conn_host="127.0.0.1"; fi
  ES_LOCAL_URL="https://${es_conn_host}:9200"

  local kibana_conn_host="$KIBANA_HOST"
  if [[ "$kibana_conn_host" == "0.0.0.0" ]]; then kibana_conn_host="127.0.0.1"; fi
  KIBANA_LOCAL_URL="http://${kibana_conn_host}:5601"

  echo ""
  hr
  echo -e "  ${BOLD}Installation${NC}"
  hr
  echo ""

  install_elasticsearch
  install_kibana
  prepare_fleet

  configure_elasticsearch
  configure_kibana

  start_service "elasticsearch"
  setup_es_security
  setup_kibana_password

  setup_kibana_enrollment
  start_service "kibana"

  wait_for_kibana
  setup_fleet_server

  # Restart Kibana after Fleet Server is healthy so it enables secrets storage
  local fleet_host_ip="$FLEET_HOST"
  if [[ "$fleet_host_ip" == "0.0.0.0" ]]; then
    fleet_host_ip=$(hostname -I | awk '{print $1}')
  fi
  if wait_for_fleet_server "$fleet_host_ip"; then
    step "Restarting Kibana to enable Fleet secrets storage"
    systemctl restart kibana >> "$LOG_FILE" 2>&1 || true
    wait_for_kibana || true
  fi
  setup_ccs

  echo ""
  hr
  echo -e "  ${BOLD}${GREEN}Installation complete!${NC}"
  hr
  echo ""
  write_summary
}

main "$@"
