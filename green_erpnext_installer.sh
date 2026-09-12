#!/usr/bin/env bash
set -Eeuo pipefail

# Green ERPNext Installer — Final
# Clean base ERPNext installation only; Green Compliance Hub and Green Expense are separate apps.
# Version-aware installer for ERPNext/Frappe v15-v16.
# Designed for fresh Ubuntu/Debian VMs and normal sudo users.
# Core repositories: official frappe/erpnext only.

APP_NAME="Green ERPNext Installer"
APP_VERSION="3.0.46"
FRAPPE_REPO="https://github.com/frappe/frappe.git"
ERPNEXT_REPO="https://github.com/frappe/erpnext.git"
PAYMENTS_REPO="https://github.com/frappe/payments.git"
LOG_DIR="${HOME}/green-erpnext-installer-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
LOCK_FILE="/tmp/green_erpnext_installer.lock"
# One process owns the installer lock for the entire bootstrap -> dedicated-user
# exec hand-off. The lock FD is inherited by the exec'ed process, so the child
# never re-opens the /tmp lock file under a different Linux user.
if [[ "${GREEN_LOCK_INHERITED:-0}" != "1" ]]; then
  exec 9>"$LOCK_FILE"
  flock -n 9 || {
    echo "Another Green ERPNext Installer process is already running." >&2
    echo "If you are sure no installer is running, remove: $LOCK_FILE" >&2
    exit 1
  }
fi
# Do not mirror stdout through /dev/tty. The installer is interactive, and a
# single stdout stream prevents duplicate prompts/output when SSH/TTY is used.
# The process substitution records output without writing a second terminal copy.
exec > >(tee -a "$LOG_FILE") 2>&1

cleanup_on_error() {
  rc=$?
  stop_install_redis 2>/dev/null || true
  echo
  echo "✖ Installation stopped (exit $rc)."
  echo "  Log: $LOG_FILE"
  exit $rc
}
trap cleanup_on_error ERR


# ---------- UI ----------
# Keep output portable across SSH terminals: ANSI colors are emitted with printf,
# while the logo/separators use plain ASCII so no \033 or Unicode replacement boxes appear.
RESET='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'
GREEN='\033[1;32m'; ORANGE='\033[38;5;208m'; CYAN='\033[38;5;45m'; BLUE='\033[38;5;75m'
YELLOW='\033[38;5;220m'; RED='\033[38;5;203m'; WHITE='\033[97m'

supports_color() {
  [[ -z "${NO_COLOR:-}" ]] || return 1
  [[ "${TERM:-}" != "dumb" ]] || return 1
  # Installer output is logged through tee, so stdout is a pipe even in a real SSH terminal.
  # Detect an attached terminal via /dev/tty as well as stdout.
  [[ -t 1 || -t 2 || -e /dev/tty ]]
}
color() { if supports_color; then printf '%b' "$1"; else printf '%s' "$2"; fi; }
line() { printf '%*s\n' "${1:-72}" '' | tr ' ' '-'; }

banner() {
  clear 2>/dev/null || true
  echo
  printf '                         '
  color "${GREEN}${BOLD}" ''; printf 'GREEN'; color "${RESET}" ''
  printf ' '
  color "${ORANGE}${BOLD}" ''; printf 'DIGITIZE'; color "${RESET}" ''
  printf '\n'
  color "${CYAN}" ''; printf '       +--------------------------------------------------------------+\n'; color "${RESET}" ''

  # Classic ANSI banner style from the original installer. The center E is
  # isolated and colored orange; the remaining GREEN artwork stays green.
  local -a art=(
    '  ██████╗ ██████╗ ███████╗███████╗███╗   ██╗'
    ' ██╔════╝ ██╔══██╗██╔════╝██╔════╝████╗  ██║'
    ' ██║  ███╗██████╔╝█████╗  █████╗  ██╔██╗ ██║'
    ' ██║   ██║██╔══██╗██╔══╝  ██╔══╝  ██║╚██╗██║'
    ' ╚██████╔╝██║  ██║███████╗███████╗██║ ╚████║'
    '  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝  ╚═══╝'
  )
  local a
  for a in "${art[@]}"; do
    printf '       |'
    color "${GREEN}${BOLD}" ''
    printf '%s' "${a:0:18}"
    color "${ORANGE}${BOLD}" ''
    printf '%s' "${a:18:8}"
    color "${GREEN}${BOLD}" ''
    printf '%s' "${a:26}"
    color "${RESET}" ''
    printf '       |\n'
  done

  color "${CYAN}" ''; printf '       +--------------------------------------------------------------+\n'; color "${RESET}" ''
  printf '                         '
  color "${WHITE}${BOLD}" ''; printf 'ERPNext Installer v%s' "$APP_VERSION"; color "${RESET}" ''; printf '\n'
  color "${DIM}" ''; printf '                  Clean Base  |  Version-aware  |  Production-ready\n'; color "${RESET}" ''
  printf '                         '
  color "${ORANGE}${BOLD}" ''; printf 'Made 💝 from Pakistan'; color "${RESET}" ''
  printf '\n\n'
}

section() { echo; color "${CYAN}${BOLD}" ''; printf '>> %s\n' "$*"; color "${RESET}" ''; line 72; }
ok() { color "${GREEN}" ''; printf '  [OK] %s\n' "$*"; color "${RESET}" ''; }
info() { color "${BLUE}" ''; printf '  [i] %s\n' "$*"; color "${RESET}" ''; }
warn() { color "${YELLOW}" ''; printf '  [!] %s\n' "$*"; color "${RESET}" ''; }
die() { color "${RED}" ''; printf '  [X] %s\n' "$*" >&2; color "${RESET}" ''; exit 1; }
step() { color "${WHITE}${BOLD}" ''; printf '  [%s] %s\n' "$1" "$2"; color "${RESET}" ''; }
# ---------- release profiles ----------
declare -A F_BRANCH PY_VER NODE_VER DB_VER
F_BRANCH[15]="version-15"; PY_VER[15]="3.10+"; NODE_VER[15]="18"; DB_VER[15]="OS-native 10.6.6+"
F_BRANCH[16]="version-16"; PY_VER[16]="3.14"; NODE_VER[16]="24"; DB_VER[16]="OS-native/official 11.8"

# The OS is the first compatibility layer. ERPNext/Frappe then selects the
# minimum runtime that is valid on that OS. We never replace the OS's system
# Python, MariaDB, or npm with an incompatible global alternative.
OS_ID=""
OS_VERSION=""
OS_CODENAME=""
MARIADB_REPO_VERSION=""

# Official app branch policy. Empty means "not offered by this installer".
declare -A APP_REPO
APP_REPO[hrms]="https://github.com/frappe/hrms.git"
APP_REPO[education]="https://github.com/frappe/education.git"
APP_REPO[healthcare]="https://github.com/frappe/health.git"
APP_REPO[payments]="$PAYMENTS_REPO"

declare -A APP_BRANCH_15 APP_BRANCH_16
APP_BRANCH_15[hrms]="version-15"; APP_BRANCH_15[education]="version-15.2"; APP_BRANCH_15[healthcare]="version-15"; APP_BRANCH_15[payments]="version-15"
APP_BRANCH_16[hrms]="version-16"; APP_BRANCH_16[education]="version-16"; APP_BRANCH_16[healthcare]="version-16"; APP_BRANCH_16[payments]=""

ERP_VERSION=""
BENCH_DIR=""
SITE_NAME=""
DB_ROOT_PASSWORD=""
ADMIN_PASSWORD=""
PRODUCTION="n"
FRAPPE_USER=""
FRAPPE_USER_PASSWORD=""
WEB_PORT=""
SOCKETIO_PORT=""
REDIS_QUEUE_PORT=""
REDIS_CACHE_PORT=""
FILE_WATCHER_PORT=""

TEMP_REDIS_QUEUE_STARTED=0
TEMP_REDIS_CACHE_STARTED=0

version_menu() {
  section "Choose ERPNext release"
  echo -e "  ${BOLD}1${RESET}  ERPNext v15  ${GREEN}(supported)${RESET}"
  echo -e "  ${BOLD}2${RESET}  ERPNext v16  ${GREEN}(supported)${RESET}"
  echo
  read -rp "  Select [1-2]: " choice
  case "$choice" in
    1) ERP_VERSION=15;; 2) ERP_VERSION=16;;
    *) die "Invalid selection.";;
  esac
  echo
  echo -e "  Selected: ${BOLD}ERPNext v${ERP_VERSION}${RESET}"
  echo "  Frappe : ${F_BRANCH[$ERP_VERSION]}"
  echo "  Python : ${PY_VER[$ERP_VERSION]}+"
  echo "  Node   : ${NODE_VER[$ERP_VERSION]}"
  echo "  MariaDB target: ${DB_VER[$ERP_VERSION]}"
}

check_os() {
  [[ -r /etc/os-release ]] || die "Cannot identify operating system."
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="$ID"
  OS_VERSION="$VERSION_ID"
  OS_CODENAME="${VERSION_CODENAME:-}"
  [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]] || die "Supported OS family: Ubuntu or Debian."

  info "Detected ${PRETTY_NAME:-$ID $VERSION_ID}"

  if [[ "$OS_ID" == "ubuntu" ]]; then
    [[ "$OS_VERSION" == "24.04" || "$OS_VERSION" == "25.04" || "$OS_VERSION" == "25.10" ]] || \
      die "For ERPNext v15/v16 use Ubuntu 24.04+ with a supported release."
  else
    [[ "${OS_VERSION%%.*}" -ge 13 ]] || die "For ERPNext v15/v16 use Debian 13+ according to current Frappe guidance."
  fi

  # OS-specific runtime selection. v15/v16 are the supported release profiles
  # of this installer. Python/Node/MariaDB are selected from the detected OS
  # release first, then checked against the selected Frappe/ERPNext branch.
  if [[ "$OS_ID" == "ubuntu" && "$OS_VERSION" == "24.04" ]]; then
    PY_VER[15]="3.10+ (isolated)"; PY_VER[16]="3.14"
    DB_VER[15]="10.11.x (Ubuntu 24.04 native)"; DB_VER[16]="11.8.x (official MariaDB repo)"
    NODE_VER[15]="18"; NODE_VER[16]="24"
  elif [[ "$OS_ID" == "debian" && "${OS_VERSION%%.*}" == "13" ]]; then
    PY_VER[15]="3.10+ (isolated)"; PY_VER[16]="3.14"
    DB_VER[15]="11.8.x (Debian 13 native)"; DB_VER[16]="11.8.x (Debian 13 native)"
    NODE_VER[15]="18"; NODE_VER[16]="24"
  else
    die "No supported OS runtime profile exists for $OS_ID $OS_VERSION + ERPNext v$ERP_VERSION."
  fi

  info "OS runtime profile: Python ${PY_VER[$ERP_VERSION]} | Node/npm ${NODE_VER[$ERP_VERSION]} | MariaDB ${DB_VER[$ERP_VERSION]}"
}


require_user() {
  [[ "${EUID}" -ne 0 ]] || die "Do not run the installer as root. Start it from a normal sudo-enabled account."
  command -v sudo >/dev/null 2>&1 || die "sudo is required."
  if [[ "${GREEN_DEDICATED_USER:-0}" == "1" ]]; then
    sudo -n true || die "Dedicated Frappe user does not have non-interactive sudo access."
  else
    sudo -v </dev/tty || die "Current login user cannot obtain sudo privileges."
  fi
}

validate_linux_username() {
  local u="$1"
  [[ "$u" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || die "Invalid Linux username: $u"
  [[ "${#u}" -le 32 ]] || die "Linux username must be 32 characters or fewer."
}

setup_frappe_user() {
  if [[ "${GREEN_DEDICATED_USER:-0}" == "1" ]]; then
    FRAPPE_USER="$(id -un)"
    # Dedicated user already has NOPASSWD sudo from bootstrap; never ask for its password.
    sudo -n true || die "Dedicated Frappe user does not have non-interactive sudo access."
    return 0
  fi

  section "Dedicated Frappe user"
  info "The installer will create/use a separate Linux user for Frappe/ERPNext."
  info "The current login user will only be used to bootstrap the installation."
  echo
  read -rp "  New Linux username: " FRAPPE_USER
  validate_linux_username "$FRAPPE_USER"
  [[ "$FRAPPE_USER" != "root" ]] || die "Do not use root as the Frappe user."
  [[ "$FRAPPE_USER" != "$(id -un)" ]] || die "Choose a new user name different from the current login user."

  if id "$FRAPPE_USER" >/dev/null 2>&1; then
    warn "User '$FRAPPE_USER' already exists."
    echo "  [1] Reuse existing user (KEEP current password + home files)"
    echo "  [2] Reuse existing user and CHANGE password"
    echo "  [3] Use a different username"
    echo "  [4] Cancel installation"
    read -rp "  Select an option [1-4]: " user_choice
    case "$user_choice" in
      1) info "Existing password will NOT be changed." ;;
      2)
        read -rsp "  New password for $FRAPPE_USER: " FRAPPE_USER_PASSWORD; echo
        read -rsp "  Confirm password: " FRAPPE_USER_PASSWORD_2; echo
        [[ -n "$FRAPPE_USER_PASSWORD" && "$FRAPPE_USER_PASSWORD" == "$FRAPPE_USER_PASSWORD_2" ]] || die "New user passwords do not match or are empty."
        printf '%s:%s\n' "$FRAPPE_USER" "$FRAPPE_USER_PASSWORD" | sudo chpasswd
        unset FRAPPE_USER_PASSWORD FRAPPE_USER_PASSWORD_2
        ok "Password updated for existing user: $FRAPPE_USER"
        ;;
      3) exec "$0" ;;
      4) echo "  Cancelled."; exit 0 ;;
      *) die "Invalid selection." ;;
    esac
    sudo usermod -aG sudo "$FRAPPE_USER"
  else
    read -rsp "  Password for $FRAPPE_USER: " FRAPPE_USER_PASSWORD; echo
    read -rsp "  Confirm password: " FRAPPE_USER_PASSWORD_2; echo
    [[ -n "$FRAPPE_USER_PASSWORD" && "$FRAPPE_USER_PASSWORD" == "$FRAPPE_USER_PASSWORD_2" ]] || die "New user passwords do not match or are empty."
    step "0/9" "Creating dedicated user $FRAPPE_USER"
    sudo useradd --create-home --shell /bin/bash "$FRAPPE_USER"
    printf '%s:%s\n' "$FRAPPE_USER" "$FRAPPE_USER_PASSWORD" | sudo chpasswd
    unset FRAPPE_USER_PASSWORD FRAPPE_USER_PASSWORD_2
    sudo usermod -aG sudo "$FRAPPE_USER"
  fi

  local sudoers_file="/etc/sudoers.d/green-erpnext-$FRAPPE_USER"
  printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$FRAPPE_USER" | sudo tee "$sudoers_file" >/dev/null
  sudo chmod 0440 "$sudoers_file"
  sudo visudo -cf "$sudoers_file" >/dev/null || die "Generated sudoers entry failed validation."

  # Required ERPNext home permissions. Keep exactly as requested.
  sudo chmod o+x "/home/$FRAPPE_USER"
  sudo chmod -R o+rx "/home/$FRAPPE_USER"
  sudo chown -R "$FRAPPE_USER:$FRAPPE_USER" "/home/$FRAPPE_USER"
  ok "Dedicated user permissions ready: chmod -R o+rx /home/$FRAPPE_USER"

  # Re-enter only once, explicitly attaching the dedicated process to the real TTY.
  # The child then owns the interactive prompts and installation; the parent never resumes main().
  local bootstrap="/tmp/green_erpnext_installer_reexec.sh"
  sudo cp -- "${BASH_SOURCE[0]}" "$bootstrap"
  sudo chown "$FRAPPE_USER:$FRAPPE_USER" "$bootstrap"
  sudo chmod 0755 "$bootstrap"
  info "Switching installer execution to $FRAPPE_USER for a clean Frappe installation."
  exec sudo -n -iu "$FRAPPE_USER" env GREEN_DEDICATED_USER=1 GREEN_LOCK_INHERITED=1 GREEN_UI_OWNER=1 bash "$bootstrap" </dev/tty
}

ask_settings() {
  section "Installation settings"
  read -rp "  Bench directory [${HOME}/frappe-bench-v${ERP_VERSION}]: " BENCH_DIR
  BENCH_DIR="${BENCH_DIR:-${HOME}/frappe-bench-v${ERP_VERSION}}"
  if [[ "$BENCH_DIR" != /* ]]; then
    BENCH_DIR="${HOME}/${BENCH_DIR#./}"
  fi

  read -rp "  Site name [erpnext-v${ERP_VERSION}.local]: " SITE_NAME
  SITE_NAME="${SITE_NAME:-erpnext-v${ERP_VERSION}.local}"
  [[ "$SITE_NAME" =~ ^[A-Za-z0-9.-]+$ ]] || die "Invalid site name."

  EXISTING_INSTALL=0
  REUSE_EXISTING_DB=0
  RESET_MARIADB=0
  EXISTING_SITE_CONFIG=""
  EXISTING_INSTALL_BACKUP=""

  if [[ -d "$BENCH_DIR" ]]; then
    EXISTING_INSTALL=1
    warn "Existing ERPNext/Frappe installation folder detected: $BENCH_DIR"
    if [[ -f "$BENCH_DIR/sites/$SITE_NAME/site_config.json" ]]; then
      EXISTING_SITE_CONFIG="$BENCH_DIR/sites/$SITE_NAME/site_config.json"
      info "Existing site configuration found for $SITE_NAME; it can be preserved when MariaDB is kept."
    fi
    echo
    echo "  [1] Fresh installation — overwrite all, KEEP existing MariaDB/data"
    echo "  [2] Fresh installation — overwrite all, INSTALL NEW MariaDB (DATA WILL BE ERASED)"
    echo "  [3] Keep existing installation — do nothing"
    echo "  [4] Cancel installation"
    read -rp "  Select an option [1-4]: " install_choice
    case "$install_choice" in
      1) REUSE_EXISTING_DB=1 ;;
      2)
        RESET_MARIADB=1
        warn "This will permanently erase the existing MariaDB databases."
        read -rp "  Type WIPE to confirm MariaDB reset: " wipe_confirm
        [[ "$wipe_confirm" == "WIPE" ]] || die "MariaDB reset cancelled; no destructive action performed."
        ;;
      3)
        info "Existing installation kept. Nothing will be changed."
        exit 0
        ;;
      4)
        echo "  Cancelled."; exit 0
        ;;
      *) die "Invalid installation option." ;;
    esac

    EXISTING_INSTALL_BACKUP="/tmp/green-erpnext-reinstall-$(date +%Y%m%d-%H%M%S)"
    sudo mkdir -p "$EXISTING_INSTALL_BACKUP"
    info "Moving the old Bench into a backup folder so site configuration and attachments remain recoverable."
    sudo mv "$BENCH_DIR" "$EXISTING_INSTALL_BACKUP/bench"
    if [[ -f "$EXISTING_INSTALL_BACKUP/bench/sites/common_site_config.json" ]]; then
      sudo cp "$EXISTING_INSTALL_BACKUP/bench/sites/common_site_config.json" "$EXISTING_INSTALL_BACKUP/common_site_config.json"
    fi
    info "Reinstall backup prepared at $EXISTING_INSTALL_BACKUP/bench"
    ok "Old ERPNext/Frappe installation moved aside; fresh Bench path is now available."
  fi

  if [[ "$RESET_MARIADB" -eq 1 ]]; then
    read -rsp "  New MariaDB root password: " DB_ROOT_PASSWORD; echo
    read -rsp "  Confirm new MariaDB root password: " DB_ROOT_PASSWORD_2; echo
  elif command -v mariadb >/dev/null 2>&1; then
    read -rsp "  Enter existing MariaDB root password: " DB_ROOT_PASSWORD; echo
    read -rsp "  Confirm MariaDB root password: " DB_ROOT_PASSWORD_2; echo
  else
    read -rsp "  New MariaDB root password: " DB_ROOT_PASSWORD; echo
    read -rsp "  Confirm new MariaDB root password: " DB_ROOT_PASSWORD_2; echo
  fi
  [[ "$DB_ROOT_PASSWORD" == "$DB_ROOT_PASSWORD_2" && -n "$DB_ROOT_PASSWORD" ]] \
    || die "MariaDB passwords do not match or are empty."
  unset DB_ROOT_PASSWORD_2

  read -rsp "  Enter ERPNext Administrator password: " ADMIN_PASSWORD; echo
  read -rsp "  Confirm ERPNext Administrator password: " ADMIN_PASSWORD_2; echo
  [[ "$ADMIN_PASSWORD" == "$ADMIN_PASSWORD_2" && -n "$ADMIN_PASSWORD" ]] \
    || die "Administrator passwords do not match or are empty."
  unset ADMIN_PASSWORD_2

  echo
  read -rp "  Configure production services (nginx + supervisor)? [y/N]: " PRODUCTION
  PRODUCTION="${PRODUCTION:-n}"
}

reset_mariadb() {
  [[ "$RESET_MARIADB" -eq 1 ]] || return 0
  section "MariaDB reset"
  step "1/9" "Removing existing MariaDB server and database files"
  sudo systemctl stop mariadb 2>/dev/null || true
  sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y mariadb-server mariadb-client mariadb-common libmariadb-dev libmariadb-dev-compat || true
  sudo rm -rf /var/lib/mysql /etc/mysql
  sudo apt-get autoremove -y || true
  ok "MariaDB reset complete. A fresh target MariaDB will be installed."
}

prepare_reinstall_site() {
  [[ "$REUSE_EXISTING_DB" -eq 1 ]] || return 0
  [[ -f "$EXISTING_INSTALL_BACKUP/bench/sites/$SITE_NAME/site_config.json" ]] || die "Cannot preserve the existing database: site_config.json was not found for $SITE_NAME."
  info "Existing MariaDB will be preserved; restoring $SITE_NAME configuration and site files after the fresh Bench is initialized."
}

install_packages() {
  section "System packages"
  step "1/9" "Updating package index"
  sudo apt-get update

  step "2/9" "Installing build/runtime dependencies"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git curl wget ca-certificates build-essential pkg-config \
    python3-dev python3-pip python3-setuptools python3-venv \
    redis-server \
    libffi-dev libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
    libsqlite3-dev libncursesw5-dev xz-utils tk-dev \
    libxml2-dev libxmlsec1-dev liblzma-dev \
    libjpeg-dev libpng-dev libfreetype6-dev libxslt1-dev \
    libldap2-dev libsasl2-dev cron xvfb fontconfig \
    libxrender1 xfonts-75dpi xfonts-base \
    nginx supervisor ansible fail2ban certbot

  # MariaDB is selected from the detected OS first. Use the OS package when
  # it satisfies the Frappe branch; only add the official MariaDB repository
  # when that OS release does not provide a compatible series. This prevents
  # the Ubuntu 24.04/v15 -> MariaDB 10.6 repository mismatch that caused the
  # earlier installer failure.
  if ! command -v mariadb >/dev/null 2>&1; then
    step "2b/9" "Installing OS-compatible MariaDB"
    local need_repo=0
    if [[ "$ERP_VERSION" -eq 16 ]]; then
      if [[ "$OS_ID" == "ubuntu" && "$OS_VERSION" == "24.04" ]]; then
        need_repo=1; MARIADB_REPO_VERSION="mariadb-11.8"
      fi
    fi

    if (( need_repo == 1 )); then
      curl -LsSf https://downloads.mariadb.com/MariaDB/mariadb_repo_setup -o /tmp/mariadb_repo_setup
      sudo bash /tmp/mariadb_repo_setup --mariadb-server-version="$MARIADB_REPO_VERSION"
      rm -f /tmp/mariadb_repo_setup
      sudo apt-get update
    fi
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server mariadb-client libmariadb-dev libmariadb-dev-compat
  else
    info "MariaDB is already installed; the existing server will be reused and validated."
  fi

  sudo systemctl enable --now mariadb redis-server
  # npm is intentionally NOT checked here. Node.js + its bundled npm are
  # installed and verified later by install_node() via the OS/runtime profile.
  # Checking npm before install_node() caused a clean Ubuntu 22.04 v15/v16
  # installation to stop before NVM had even been initialized.
  command -v ansible >/dev/null 2>&1 || die "Ansible is required and was not installed."
  install_wkhtmltopdf
  ok "System packages installed."
}

install_wkhtmltopdf() {
  section "PDF engine"
  if command -v wkhtmltopdf >/dev/null 2>&1 && wkhtmltopdf --version 2>/dev/null | grep -qi "patched qt"; then
    info "wkhtmltopdf with patched Qt is already installed."
    return 0
  fi

  step "2c/9" "Installing wkhtmltopdf 0.12.6.1 (patched Qt)"
  local arch deb url tmp
  case "$(uname -m)" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "Unsupported CPU architecture for wkhtmltopdf: $(uname -m)" ;;
  esac

  deb="wkhtmltox_0.12.6.1-2.jammy_${arch}.deb"
  url="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/${deb}"
  tmp="/tmp/${deb}"

  sudo rm -f "$tmp"
  curl -fL --retry 3 --retry-delay 2 "$url" -o "$tmp"
  sudo dpkg -i "$tmp" || true
  sudo apt-get -f install -y
  sudo dpkg -i "$tmp" || true
  sudo apt-get -f install -y
  sudo rm -f "$tmp"

  command -v wkhtmltopdf >/dev/null 2>&1 || die "wkhtmltopdf installation failed."
  wkhtmltopdf --version | grep -qi "patched qt" \
    || die "wkhtmltopdf was installed, but the required patched Qt build was not detected."
  ok "wkhtmltopdf ready: $(wkhtmltopdf --version)"
}

configure_mariadb() {
  section "MariaDB"
  step "3/9" "Applying utf8mb4 configuration"
  sudo tee /etc/mysql/mariadb.conf.d/99-green-erpnext.cnf >/dev/null <<'EOF'
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
bind-address = 127.0.0.1
EOF
  sudo systemctl restart mariadb

  step "4/9" "Configuring Frappe-compatible MariaDB authentication"
  local mariadb_version escaped

  # MariaDB 10.4+ commonly creates root@localhost with unix_socket as the
  # primary authentication method. A password supplied to the CLI while
  # running as OS root can therefore appear to work even though a non-root
  # Frappe process cannot authenticate as MariaDB root. We deliberately test
  # the same TCP path that Frappe will use.
  if ! sudo mariadb -N -e "SELECT VERSION();" >/tmp/green_mariadb_version 2>/dev/null; then
    rm -f /tmp/green_mariadb_version
    die "Cannot access MariaDB through the local administrative socket."
  fi
  mariadb_version="$(head -1 /tmp/green_mariadb_version)"
  rm -f /tmp/green_mariadb_version

  escaped="${DB_ROOT_PASSWORD//\\/\\\\}"
  escaped="${escaped//\'/\'\'}"

  # Keep local socket administration available for the OS root account while
  # also creating a password-authenticated root endpoint on loopback.
  sudo mariadb -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${escaped}') OR unix_socket; CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '${escaped}'; ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${escaped}'; GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION; FLUSH PRIVILEGES;"

  # This is the decisive validation: password + TCP + 127.0.0.1, not the
  # privileged OS-root socket path.
  sudo mariadb --protocol=tcp -h 127.0.0.1 -P 3306 -uroot --password="$DB_ROOT_PASSWORD" -N -e "SELECT VERSION();" >/tmp/green_mariadb_version 2>/dev/null \
    || die "MariaDB TCP root authentication failed. Frappe site creation cannot safely continue."
  mariadb_version="$(head -1 /tmp/green_mariadb_version)"
  rm -f /tmp/green_mariadb_version
  [[ -n "$mariadb_version" ]] || die "Unable to verify MariaDB version over TCP."
  ok "MariaDB ready: ${mariadb_version} (TCP root authentication verified)"

  local db_core="${mariadb_version%%-*}"
  db_core="${db_core#1:}"
  if [[ "$ERP_VERSION" -eq 16 ]]; then
    [[ "$db_core" == 11.8.* || "$db_core" == 11.8 ]] || \
      die "Frappe v16 requires MariaDB 11.8.x. Detected ${mariadb_version}. Existing MariaDB was not modified."
  elif [[ "$ERP_VERSION" -eq 15 ]]; then
    local minimum_db="10.6.6"
    local lowest
    lowest="$(printf '%s\n%s\n' "$minimum_db" "$db_core" | sort -V | head -n1)"
    [[ "$lowest" == "$minimum_db" ]] || \
      die "Frappe v15 requires MariaDB 10.6.6 or newer. Detected ${mariadb_version}. Existing MariaDB was not modified."
  fi
  ok "MariaDB compatibility verified for Frappe v${ERP_VERSION}: ${mariadb_version}"
}

install_uv() {
  section "Python runtime"
  local py_target=""
  case "$OS_ID:$OS_VERSION:$ERP_VERSION" in
    ubuntu:24.04:15) py_target="3.10" ;;
    ubuntu:24.04:16) py_target="3.14" ;;
    debian:13:15) py_target="3.10" ;;
    debian:13:16) py_target="3.14" ;;
    *) die "No Python runtime profile exists for $OS_ID $OS_VERSION + ERPNext v$ERP_VERSION." ;;
  esac
  PY_VER[$ERP_VERSION]="$py_target"
  step "5/9" "Installing isolated Python ${py_target} for ${OS_ID} ${OS_VERSION}"
  if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
  export PATH="$HOME/.local/bin:$PATH"
  command -v uv >/dev/null || die "uv was installed but is not on PATH."

  # Frappe v16 uses uv to install/manage the Python runtime. The Python
  # interpreter installed by `uv python install` is intentionally
  # externally-managed; do NOT mutate it with `uv pip install`. Bench creates
  # its own environment/tooling and will manage its packages there.
  uv python install "${py_target}" --default
  uv python pin "${py_target}" 2>/dev/null || true

  PYTHON_BIN="$(uv python find "${py_target}")"
  "$PYTHON_BIN" --version
  command -v python3 >/dev/null 2>&1 || die "python3 is not available after uv installation."
  [[ "$(python3 --version 2>&1)" == "Python ${py_target}"* ]] || \
    die "python3 is not the selected Python ${py_target} runtime: $(python3 --version 2>&1)"
  uv --version
  ok "Python runtime ready: $PYTHON_BIN"
}

install_node() {
  section "Node.js runtime"
  step "6/9" "Installing Node.js ${NODE_VER[$ERP_VERSION]} + npm + Yarn"
  export NVM_DIR="$HOME/.nvm"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  fi
  [[ -s "$NVM_DIR/nvm.sh" ]] || die "NVM installation failed: $NVM_DIR/nvm.sh was not created."
  # shellcheck disable=SC1090
  source "$NVM_DIR/nvm.sh"

  # The shared v16 guide explicitly installs npm after Node. Keep that
  # prerequisite installed system-wide, while the active npm used by Bench is
  # the npm bundled with the verified nvm Node runtime.
  nvm install "${NODE_VER[$ERP_VERSION]}"
  nvm alias "erpnext-v${ERP_VERSION}" "${NODE_VER[$ERP_VERSION]}"
  nvm alias default "${NODE_VER[$ERP_VERSION]}"
  nvm use "erpnext-v${ERP_VERSION}"
  hash -r

  local node_bin node_root
  node_bin="$(nvm which "${NODE_VER[$ERP_VERSION]}")"
  [[ -x "$node_bin" ]] || die "Node.js ${NODE_VER[$ERP_VERSION]} was downloaded but the executable was not installed: $node_bin"
  node_root="$(dirname "$node_bin")"
  export PATH="$node_root:$HOME/.local/bin:$PATH"

  command -v node >/dev/null 2>&1 || die "Node.js command is not available after installation."
  command -v npm >/dev/null 2>&1 || die "npm command is not available after Node.js installation."
  [[ "$(node --version)" == v${NODE_VER[$ERP_VERSION]}.* ]] \
    || die "Wrong Node.js version detected: $(node --version 2>/dev/null || echo unavailable). Expected v${NODE_VER[$ERP_VERSION]}.*"
  npm --version >/dev/null 2>&1 || die "npm is not executable."

  npm install -g yarn@1.22.22
  command -v yarn >/dev/null 2>&1 || die "Yarn installation failed."
  [[ "$(yarn --version)" == 1.22.* ]] || die "Wrong Yarn version detected: $(yarn --version). Expected 1.22.x"

  # Supervisor starts outside the user's login shell, so nvm's shell PATH is
  # not available there. Expose the verified nvm-managed binaries through the
  # normal system PATH without installing a second Node.js copy.
  sudo ln -sfn "$node_root/node" /usr/local/bin/node
  sudo ln -sfn "$node_root/npm" /usr/local/bin/npm
  [[ -x "$node_root/npx" ]] && sudo ln -sfn "$node_root/npx" /usr/local/bin/npx
  sudo ln -sfn "$node_root/yarn" /usr/local/bin/yarn
  [[ -x "$node_root/yarnpkg" ]] && sudo ln -sfn "$node_root/yarnpkg" /usr/local/bin/yarnpkg

  # Verify both the current installer shell and the system PATH used by
  # Supervisor. This is the check v3.0.29 was missing.
  [[ "$(/usr/local/bin/node --version)" == v${NODE_VER[$ERP_VERSION]}.* ]] \
    || die "System Node.js verification failed after linking /usr/local/bin/node."
  /usr/local/bin/npm --version >/dev/null 2>&1 \
    || die "System npm verification failed after linking /usr/local/bin/npm."
  /usr/local/bin/yarn --version >/dev/null 2>&1 \
    || die "System Yarn verification failed after linking /usr/local/bin/yarn."

  ok "Node $(node --version), npm $(npm --version), Yarn $(yarn --version)"
}

verify_v16_prerequisites() {
  [[ "$ERP_VERSION" -eq 16 ]] || return 0
  section "v16 prerequisite verification"
  step "6b/9" "Verifying Frappe v16 runtime requirements"
  [[ "$(python3 --version 2>&1)" == "Python 3.14"* ]] || die "Frappe v16 requires Python 3.14; detected $(python3 --version 2>&1)."
  [[ "$(node --version 2>&1)" == v24.* ]] || die "Frappe v16 requires Node 24; detected $(node --version 2>&1)."
  command -v npm >/dev/null 2>&1 || die "npm is missing from the active PATH."
  [[ "$(yarn --version 2>&1)" == 1.22.* ]] || die "Frappe v16 requires Yarn 1.22+; detected $(yarn --version 2>&1)."
  command -v redis-server >/dev/null 2>&1 || die "Redis is missing."
  command -v wkhtmltopdf >/dev/null 2>&1 || die "wkhtmltopdf is missing."
  wkhtmltopdf --version 2>&1 | grep -qi "patched qt" || die "wkhtmltopdf must be the patched Qt build."
  command -v cron >/dev/null 2>&1 || die "cron is missing."
  ok "v16 prerequisites verified: Python 3.14 | Node 24 | npm | Yarn 1.22+ | Redis | patched wkhtmltopdf | cron"
}

install_bench() {
  section "Bench CLI"
  step "7/9" "Installing frappe-bench"
  export PATH="$HOME/.local/bin:$PATH"
  if ! command -v bench >/dev/null 2>&1; then
    # Current Frappe guidance recommends uv tool for Bench.
    uv tool install frappe-bench
  fi
  command -v bench >/dev/null || die "Bench CLI is not available on PATH."
  bench --version
  ok "Bench CLI ready."
}

choose_bench_ports() {
  section "Bench service ports"
  # Separate Linux users may host separate benches on the same VM.  Nginx can
  # share port 80 by hostname, but each bench needs unique internal web,
  # Socket.IO, Redis and file-watcher ports.
  local candidate
  for candidate in 8000 8010 8020 8030 8040 8050 8060 8070 8080 8090; do
    local -a ports=("$candidate" "$((candidate+1000))" "$((candidate+3000))" "$((candidate+5000))" "$((candidate-1213))")
    local occupied=0 port
    for port in "${ports[@]}"; do
      if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\])${port}$"; then
        occupied=1
        break
      fi
    done
    (( occupied == 0 )) || continue
    WEB_PORT="$candidate"
    SOCKETIO_PORT="$((candidate+1000))"
    REDIS_QUEUE_PORT="$((candidate+3000))"
    REDIS_CACHE_PORT="$((candidate+5000))"
    FILE_WATCHER_PORT="$((candidate-1213))"
    break
  done
  [[ -n "$WEB_PORT" ]] || die "Could not find a free internal port set for this bench."

  cd "$BENCH_DIR"
  bench config set-common-config -c webserver_port "$WEB_PORT"
  bench config set-common-config -c socketio_port "$SOCKETIO_PORT"
  bench config set-common-config -c redis_queue "'redis://127.0.0.1:${REDIS_QUEUE_PORT}'"
  bench config set-common-config -c redis_cache "'redis://127.0.0.1:${REDIS_CACHE_PORT}'"
  bench config set-common-config -c redis_socketio "'redis://127.0.0.1:${REDIS_CACHE_PORT}'"
  bench config set-common-config -c file_watcher_port "$FILE_WATCHER_PORT"
  ok "Bench internal ports: web=${WEB_PORT}, socketio=${SOCKETIO_PORT}, redis-queue=${REDIS_QUEUE_PORT}, redis-cache=${REDIS_CACHE_PORT}"
}

init_bench() {
  section "Frappe + ERPNext"
  step "8/9" "Creating isolated bench from ${F_BRANCH[$ERP_VERSION]}"
  export PATH="$HOME/.local/bin:$PATH"
  # Load Node runtime for this shell.
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1090
  source "$NVM_DIR/nvm.sh"
  nvm use "erpnext-v${ERP_VERSION}" >/dev/null

  bench init --frappe-branch "${F_BRANCH[$ERP_VERSION]}" --python "$PYTHON_BIN" "$BENCH_DIR"
  cd "$BENCH_DIR"

  ok "Frappe bench + ERPNext source prepared."
}

start_install_redis() {
  section "Installation services"
  cd "$BENCH_DIR"
  step "8b/9" "Starting bench Redis services for ERPNext installation"

  # The OS redis-server service normally listens on 6379, so it does not satisfy
  # the bench queue/cache connections used by a production Bench. Each bench
  # gets its own ports so multiple Linux users/benches can coexist safely.
  # Do not start Bench-generated redis_*.conf here.  bench init may contain
  # template ports that differ from our dynamically selected ports.  The
  # installer must start the temporary services explicitly on the exact ports
  # written to common_site_config.json above. Production setup later runs
  # `bench setup redis` and generates the permanent configs.
  if redis-cli -p "$REDIS_QUEUE_PORT" ping >/dev/null 2>&1; then
    info "Redis queue already running on ${REDIS_QUEUE_PORT}."
  else
    redis-server --bind 127.0.0.1 --port "$REDIS_QUEUE_PORT" --daemonize yes \
      --save '' --appendonly no --dir "$BENCH_DIR" \
      --logfile "$BENCH_DIR/logs/redis-queue-install.log"
    TEMP_REDIS_QUEUE_STARTED=1
  fi

  if redis-cli -p "$REDIS_CACHE_PORT" ping >/dev/null 2>&1; then
    info "Redis cache already running on ${REDIS_CACHE_PORT}."
  else
    redis-server --bind 127.0.0.1 --port "$REDIS_CACHE_PORT" --daemonize yes \
      --save '' --appendonly no --dir "$BENCH_DIR" \
      --logfile "$BENCH_DIR/logs/redis-cache-install.log"
    TEMP_REDIS_CACHE_STARTED=1
  fi

  for port in "$REDIS_QUEUE_PORT" "$REDIS_CACHE_PORT"; do
    local ready=0
    for _ in {1..20}; do
      if redis-cli -p "$port" ping >/dev/null 2>&1; then ready=1; break; fi
      sleep 0.25
    done
    [[ "$ready" -eq 1 ]] || die "Redis did not become ready on port ${port}."
  done
  ok "Bench Redis queue/cache ready on ${REDIS_QUEUE_PORT}/${REDIS_CACHE_PORT}."
}

stop_install_redis() {
  # Stop only the temporary daemons started by this installer. Production setup
  # or bench start will manage them afterward.
  if [[ "$TEMP_REDIS_QUEUE_STARTED" -eq 1 ]]; then
    redis-cli -p "$REDIS_QUEUE_PORT" shutdown nosave >/dev/null 2>&1 || true
    TEMP_REDIS_QUEUE_STARTED=0
  fi
  if [[ "$TEMP_REDIS_CACHE_STARTED" -eq 1 ]]; then
    redis-cli -p "$REDIS_CACHE_PORT" shutdown nosave >/dev/null 2>&1 || true
    TEMP_REDIS_CACHE_STARTED=0
  fi
}

create_site() {
  section "Site"
  cd "$BENCH_DIR"
  if [[ "$REUSE_EXISTING_DB" -eq 1 ]]; then
    step "9/9" "Reconnecting existing MariaDB data for $SITE_NAME"
    sudo mkdir -p "$BENCH_DIR/sites/$SITE_NAME"
    sudo cp -a "$EXISTING_INSTALL_BACKUP/bench/sites/$SITE_NAME/." "$BENCH_DIR/sites/$SITE_NAME/"
    if [[ -f "$EXISTING_INSTALL_BACKUP/common_site_config.json" ]]; then
      sudo cp "$EXISTING_INSTALL_BACKUP/common_site_config.json" "$BENCH_DIR/sites/common_site_config.json"
    fi
    sudo chown -R "$FRAPPE_USER:$FRAPPE_USER" "$BENCH_DIR/sites/$SITE_NAME"
    bench use "$SITE_NAME"
    bench --site "$SITE_NAME" migrate
    ok "Existing MariaDB data reconnected; ERPNext schema migrated."
  else
    step "9/9" "Creating ${SITE_NAME} and installing Frappe Framework"
    # A failed Frappe site bootstrap can leave its generated random database behind
    # even when the site directory is rolled back.  Frappe's --force is specifically
    # intended to recreate a site when the database name already exists.  Because
    # new-site generates a fresh random DB name when --db-name is omitted, this is
    # safe for this clean-install path and prevents a stale orphan DB from blocking
    # the next run with "Database _<hash> already exists".
    bench new-site "$SITE_NAME" \
      --db-root-username root \
      --db-root-password "$DB_ROOT_PASSWORD" \
      --db-host 127.0.0.1 \
      --db-port 3306 \
      --admin-password "$ADMIN_PASSWORD" \
      --force
    bench use "$SITE_NAME"
    bench --site "$SITE_NAME" set-maintenance-mode off || true
    ok "Frappe site created. ERPNext will be installed after production services are configured."
  fi
}

install_erpnext_and_optional_apps() {
  section "ERPNext + official apps"
  cd "$BENCH_DIR"
  if [[ "$ERP_VERSION" -eq 15 ]]; then
    step "8/9" "Fetching Payments ${APP_BRANCH_15[payments]}"
    bench get-app --branch "${APP_BRANCH_15[payments]}" "$PAYMENTS_REPO"
    bench --site "$SITE_NAME" install-app payments
    ok "Payments installed for ERPNext v15."
  fi
  step "8/9" "Fetching ERPNext ${F_BRANCH[$ERP_VERSION]}"
  bench get-app --branch "${F_BRANCH[$ERP_VERSION]}" --resolve-deps "$ERPNEXT_REPO"
  step "8/9" "Installing ERPNext on $SITE_NAME"
  bench --site "$SITE_NAME" install-app erpnext
  bench --site "$SITE_NAME" migrate
  ok "ERPNext installed."
  optional_apps
  # Regenerate Supervisor/Nginx configuration after optional apps are present,
  # then reload Supervisor so the production stack reflects the final bench.
  if [[ "$PRODUCTION" =~ ^[Yy]$ ]]; then
    bench setup supervisor
    bench setup nginx
    ensure_nginx_log_format
    local supervisor_dir="/etc/supervisor/conf.d"
    [[ -d "$supervisor_dir" ]] || supervisor_dir="/etc/supervisord.d"
    sudo mkdir -p "$supervisor_dir"
    sudo ln -sfn "$BENCH_DIR/config/supervisor.conf" "$supervisor_dir/$(basename "$BENCH_DIR").conf"
    sudo supervisorctl reread
    sudo supervisorctl update
    sudo nginx -t
    sudo systemctl reload nginx
    sudo supervisorctl restart all || warn "Supervisor could not restart every program after app installation."
  fi
}

app_branch() {
  local app="$1"
  case "$ERP_VERSION" in
    15) echo "${APP_BRANCH_15[$app]}" ;;
    16) echo "${APP_BRANCH_16[$app]}" ;;
  esac
}

official_app_available() {
  local app="$1" branch
  branch="$(app_branch "$app")"
  [[ -n "$branch" ]] || return 1
  git ls-remote --exit-code --heads "${APP_REPO[$app]}" "$branch" >/dev/null 2>&1
}

optional_apps() {
  section "Optional official Frappe apps"
  local app branch answer
  local -a apps=(hrms education healthcare)
  local -A labels=([hrms]="Frappe HR" [education]="Education" [healthcare]="Healthcare")

  for app in "${apps[@]}"; do
    branch="$(app_branch "$app")"
    [[ -n "$branch" ]] || continue

    if ! official_app_available "$app"; then
      warn "${labels[$app]} is not available on a verified branch for v${ERP_VERSION}; skipped."
      continue
    fi

    echo
    read -rp "  Install ${labels[$app]} (${app})? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      info "Installing ${labels[$app]} (${branch})"
      bench get-app --branch "$branch" "${APP_REPO[$app]}"
      bench --site "$SITE_NAME" install-app "$app"
      ok "${labels[$app]} installed."
    else
      info "${labels[$app]} not selected."
    fi
  done
}

ensure_nginx_log_format() {
  # Bench's generated nginx.conf uses the access-log format named "main".
  # Some Ubuntu nginx.conf variants do not define it, which makes `nginx -t`
  # fail before nginx can start. Add a small, idempotent http-context drop-in.
  local format_file="/etc/nginx/conf.d/00-green-erpnext-log-format.conf"
  if ! sudo grep -RqsE '^[[:space:]]*log_format[[:space:]]+main[[:space:]]' \
      /etc/nginx/nginx.conf /etc/nginx/conf.d 2>/dev/null; then
    sudo tee "$format_file" >/dev/null <<'EOF'
# Green ERPNext Installer: Bench nginx.conf uses the "main" access-log format.
log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                '$status $body_bytes_sent "$http_referer" '
                '"$http_user_agent" "$http_x_forwarded_for"';
EOF
  fi
}

production_setup() {
  [[ "$PRODUCTION" =~ ^[Yy]$ ]] || return 0
  section "Production services"
  cd "$BENCH_DIR"

  # Do not call `bench setup production` here.  Current Bench invokes
  # `sudo <uv-managed-python> -m pip install ansible` when Ansible is missing,
  # which fails on a uv-managed Bench Python even when Ubuntu already provides
  # Ansible.  We install the OS prerequisites up front and perform the documented
  # manual Supervisor + Nginx setup instead.
  step "P1/4" "Verifying production prerequisites"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible fail2ban nginx supervisor
  command -v ansible >/dev/null || die "Ansible is not available after installation."
  command -v supervisord >/dev/null || die "Supervisor is not available after installation."
  command -v nginx >/dev/null || die "Nginx is not available after installation."
  command -v certbot >/dev/null || die "Certbot is required by Bench sudoers setup and was not installed."

  step "P2/4" "Generating Redis, Socket.IO and Supervisor configuration"
  command -v node >/dev/null 2>&1 || die "Node.js is missing before production setup."
  command -v npm >/dev/null 2>&1 || die "npm is missing before production setup."
  command -v yarn >/dev/null 2>&1 || die "Yarn is missing before production setup."
  [[ "$(node --version)" == v${NODE_VER[$ERP_VERSION]}.* ]] || die "Wrong Node.js version before production setup: $(node --version)"
  bench setup redis
  bench setup socketio
  bench setup supervisor
  # bench setup sudoers requires superuser privileges; invoke it explicitly as root
  # while preserving the dedicated user's Bench PATH.
  sudo env "PATH=$PATH:/home/$FRAPPE_USER/.local/bin:/usr/local/bin" \
    "$HOME/.local/bin/bench" setup sudoers "$FRAPPE_USER" || \
    die "Bench sudoers generation failed."

  local supervisor_dir="/etc/supervisor/conf.d"
  [[ -d "$supervisor_dir" ]] || supervisor_dir="/etc/supervisord.d"
  sudo mkdir -p "$supervisor_dir"
  sudo ln -sfn "$BENCH_DIR/config/supervisor.conf" "$supervisor_dir/$(basename "$BENCH_DIR").conf"

  step "P3/4" "Generating Nginx configuration"
  bench setup nginx
  sudo mkdir -p /etc/nginx/conf.d
  ensure_nginx_log_format
  sudo ln -sfn "$BENCH_DIR/config/nginx.conf" "/etc/nginx/conf.d/$(basename "$BENCH_DIR").conf"

  # Remove Ubuntu's default welcome server so it cannot win the port-80 match.
  sudo rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default

  # Final production permission pass: required ERPNext home traversal/read/execute access.
  sudo chmod o+x "/home/$FRAPPE_USER"
  sudo chmod -R o+rx "/home/$FRAPPE_USER"

  step "P4/4" "Enabling and starting production services"
  sudo systemctl enable nginx supervisor mariadb
  sudo systemctl restart supervisor

  # Supervisor creates its Unix RPC socket asynchronously. Do not call
  # supervisorctl immediately after restart; that race caused the
  # FileNotFoundError in supervisor/xmlrpc.py:557 on a clean install.
  local supervisor_ready=0
  for _ in $(seq 1 30); do
    if sudo supervisorctl status >/dev/null 2>&1; then
      supervisor_ready=1
      break
    fi
    sleep 1
  done
  (( supervisor_ready == 1 )) || die "Supervisor RPC socket did not become ready within 30 seconds."

  sudo supervisorctl reread
  sudo supervisorctl update
  sudo nginx -t
  sudo systemctl restart nginx

  bench --site "$SITE_NAME" scheduler enable || true
  bench --site "$SITE_NAME" scheduler resume || true
  # Restart all only after the generated configuration is loaded and Node has
  # already been verified. A single missing/failed program must not abort the
  # installer while the remaining production services are healthy.
  sudo supervisorctl restart all
  sudo supervisorctl status
  if redis-cli -p "$REDIS_QUEUE_PORT" ping >/dev/null 2>&1 && redis-cli -p "$REDIS_CACHE_PORT" ping >/dev/null 2>&1; then
    ok "Bench Redis queue/cache are responding on ${REDIS_QUEUE_PORT}/${REDIS_CACHE_PORT}."
  else
    warn "Bench Redis ports ${REDIS_QUEUE_PORT}/${REDIS_CACHE_PORT} are not responding yet; Supervisor may need a restart after boot."
  fi
  ok "Production services configured: Nginx + Supervisor."
}
final_checks() {
  section "Final health check"
  cd "$BENCH_DIR"
  bench --site "$SITE_NAME" list-apps
  bench --site "$SITE_NAME" doctor || true
  bench --site "$SITE_NAME" show-config || true

  if [[ "$PRODUCTION" =~ ^[Yy]$ ]]; then
    local svc_status
    svc_status="$(sudo supervisorctl status 2>&1)"
    echo "$svc_status"
    if grep -Eq '\b(FATAL|STOPPED|EXITED|UNKNOWN)\b' <<<"$svc_status"; then
      die "One or more production Supervisor programs are not healthy."
    fi
    sudo nginx -t >/dev/null || die "Final Nginx configuration test failed."
    curl -fsSI -H "Host: ${SITE_NAME}" "http://127.0.0.1:${WEB_PORT}/" >/dev/null \
      || die "Frappe web endpoint did not respond on ${WEB_PORT} for Host ${SITE_NAME}."
  fi

  echo
  echo -e "${GREEN}${BOLD}"
  echo "  ┌──────────────────────────────────────────────────────────┐"
  echo "  │                 INSTALLATION COMPLETE                    │"
  echo "  └──────────────────────────────────────────────────────────┘"
  echo -e "${RESET}"
  echo "  ERPNext : v${ERP_VERSION}"
  echo "  Frappe  : ${F_BRANCH[$ERP_VERSION]}"
  echo "  Bench   : $BENCH_DIR"
  echo "  Site    : $SITE_NAME"
  echo "  User permissions: chmod -R o+rx /home/$FRAPPE_USER"
  echo "  Log     : $LOG_FILE"
  echo
  if [[ "$PRODUCTION" =~ ^[Yy]$ ]]; then
    echo "  Mode    : Production"
    echo "  URL     : http://${SITE_NAME}"
    echo "  Note    : Add ${SITE_NAME} to /etc/hosts or your DNS if needed."
  else
    echo "  Mode    : Development"
    echo "  Start   : cd $BENCH_DIR && bench start"
    echo "  URL     : http://127.0.0.1:8000"
  fi
  echo
  echo "  Useful commands:"
  echo "    cd $BENCH_DIR"
  echo "    bench --site $SITE_NAME list-apps"
  echo "    bench --site $SITE_NAME doctor"
  echo "    bench --site $SITE_NAME migrate"
}

main() {
  case "${1:-}" in
    --version|-v) echo "$APP_NAME $APP_VERSION"; exit 0 ;;
    --help|-h)
      echo "$APP_NAME $APP_VERSION"
      echo "Usage: ./green_erpnext_installer.sh"
      echo "       ./green_erpnext_installer.sh --version"
      echo "       ./green_erpnext_installer.sh --help"
      exit 0
      ;;
  esac
  require_user
  setup_frappe_user
  # The parent bootstrap process is replaced by the dedicated-user process.
  # Only that final process may enter the interactive installer UI.
  if [[ "${GREEN_UI_OWNER:-0}" != "1" ]]; then
    die "Installer UI hand-off was not completed safely."
  fi
  banner
  version_menu
  check_os
  ask_settings
  prepare_reinstall_site
  reset_mariadb

  section "Review"
  echo "  Version : v${ERP_VERSION}"
  echo "  Frappe  : ${F_BRANCH[$ERP_VERSION]}"
  echo "  Python  : ${PY_VER[$ERP_VERSION]}+"
  echo "  Node    : ${NODE_VER[$ERP_VERSION]}"
  echo "  Bench   : ${BENCH_DIR}"
  echo "  Site    : ${SITE_NAME}"
  echo "  Mode    : $([[ "$PRODUCTION" =~ ^[Yy]$ ]] && echo Production || echo Development)"
  echo
  read -rp "  Start installation? [y/N]: " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "  Cancelled."; exit 0; }

  install_packages
  configure_mariadb
  install_uv
  install_node
  verify_v16_prerequisites
  install_bench
  init_bench
  choose_bench_ports
  start_install_redis
  create_site
  stop_install_redis
  production_setup
  start_install_redis
  install_erpnext_and_optional_apps
  stop_install_redis
  final_checks
}

main "$@"
