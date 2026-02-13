#!/usr/bin/env bash
set -euo pipefail

# ══════════════════════════════════════════════════════
# ClawdEye Monitor — Installer
# ══════════════════════════════════════════════════════
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/MetamizeMe/clawdeye-license/main/install.sh | bash
#
# Or download first:
#   curl -sLO https://raw.githubusercontent.com/MetamizeMe/clawdeye-license/main/install.sh
#   chmod +x install.sh && ./install.sh

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="$HOME/clawdeye"
REPO="MetamizeMe/clawdeye-releases"

banner() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}ClawdEye Monitor${NC} — Installer            ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${DIM}by Metamize${NC}                              ${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
  echo ""
}

info()    { echo -e "${CYAN}▸${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn()    { echo -e "${YELLOW}!${NC} $1"; }
error()   { echo -e "${RED}✗${NC} $1"; }

ask() {
  local prompt="$1" default="${2:-}" var=""
  if [ -n "$default" ]; then
    echo -ne "${CYAN}?${NC} ${prompt} ${DIM}[${default}]${NC}: "
  else
    echo -ne "${CYAN}?${NC} ${prompt}: "
  fi
  read -r var
  echo "${var:-$default}"
}

ask_secret() {
  local prompt="$1" var=""
  echo -ne "${CYAN}?${NC} ${prompt}: "
  read -rs var
  echo ""
  echo "$var"
}

# ── Pre-flight checks ─────────────────────────────────

banner

# Check Node.js
if ! command -v node &>/dev/null; then
  error "Node.js is not installed."
  echo "  Install Node.js 20+: https://nodejs.org/"
  exit 1
fi

NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VERSION" -lt 20 ]; then
  error "Node.js 20+ required (found: $(node -v))"
  exit 1
fi
success "Node.js $(node -v) found"

# Check curl
if ! command -v curl &>/dev/null; then
  error "curl is not installed."
  exit 1
fi

# ── Gather configuration ──────────────────────────────

echo ""
echo -e "${BOLD}Configuration${NC}"
echo -e "${DIM}─────────────────────────────────────────${NC}"

LICENSE=$(ask "License key (provided by Metamize)")
if [ -z "$LICENSE" ]; then
  error "License key is required."
  exit 1
fi

PASSWORD=$(ask_secret "Dashboard password")
if [ -z "$PASSWORD" ]; then
  error "Dashboard password is required."
  exit 1
fi

echo ""
echo -e "${BOLD}Paths${NC} ${DIM}(press Enter to accept defaults)${NC}"
echo -e "${DIM}─────────────────────────────────────────${NC}"

CLAWD_HOME=$(ask "Clawd workspace path" "$HOME/clawd")
CLAWDBOT_HOME=$(ask "Clawdbot home path" "$HOME/.clawdbot")
OPENCLAW_HOME=$(ask "OpenClaw home path" "$HOME/.openclaw")
GATEWAY_PORT=$(ask "Gateway port" "18789")
DASHBOARD_PORT=$(ask "Dashboard port" "3000")

# ── Confirm ───────────────────────────────────────────

echo ""
echo -e "${BOLD}Summary${NC}"
echo -e "${DIM}─────────────────────────────────────────${NC}"
echo -e "  Install to:      ${BOLD}${INSTALL_DIR}${NC}"
echo -e "  Dashboard:       ${BOLD}http://localhost:${DASHBOARD_PORT}${NC}"
echo -e "  Clawd workspace: ${CLAWD_HOME}"
echo -e "  Gateway port:    ${GATEWAY_PORT}"
echo ""

CONFIRM=$(ask "Proceed with installation? (y/n)" "y")
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
  info "Installation cancelled."
  exit 0
fi

# ── Download latest release ───────────────────────────

echo ""
info "Fetching latest release..."

# Get latest release tag from GitHub API
LATEST_TAG=$(curl -sL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')

if [ -z "$LATEST_TAG" ]; then
  error "Could not determine latest version. Check https://github.com/${REPO}/releases"
  exit 1
fi

success "Latest version: ${LATEST_TAG}"

ASSET_NAME="clawdeye-${LATEST_TAG}.tgz"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}/${ASSET_NAME}"

info "Downloading ${ASSET_NAME}..."
mkdir -p "$INSTALL_DIR"

if ! curl -sL "$DOWNLOAD_URL" -o "/tmp/${ASSET_NAME}"; then
  error "Download failed: ${DOWNLOAD_URL}"
  exit 1
fi
success "Downloaded ${ASSET_NAME}"

# ── Extract ───────────────────────────────────────────

info "Extracting to ${INSTALL_DIR}..."
tar -xzf "/tmp/${ASSET_NAME}" -C "$INSTALL_DIR"
rm -f "/tmp/${ASSET_NAME}"
success "Extracted to ${INSTALL_DIR}"

# ── Create .env ───────────────────────────────────────

info "Creating .env..."
cat > "$INSTALL_DIR/.env" << EOF
DATABASE_URL=file:${INSTALL_DIR}/data/openclaw.db
CLAWDEYE_ROOT=${INSTALL_DIR}
CLAWDEYE_DATA_DIR=${INSTALL_DIR}/data
CLAWDEYE_LICENSE=${LICENSE}
DASHBOARD_TOKEN=${PASSWORD}
CLAWD_HOME=${CLAWD_HOME}
CLAWDBOT_HOME=${CLAWDBOT_HOME}
OPENCLAW_HOME=${OPENCLAW_HOME}
GATEWAY_HOST=127.0.0.1
GATEWAY_PORT=${GATEWAY_PORT}
API_PORT=4010
EOF
success "Created .env"

# ── Initialize database ──────────────────────────────

info "Initializing database..."
mkdir -p "$INSTALL_DIR/data"

cd "$INSTALL_DIR"
npx prisma db push --schema=prisma/schema.prisma 2>/dev/null
success "Database initialized"

# ── Create start script ──────────────────────────────

cat > "$INSTALL_DIR/start.sh" << 'STARTEOF'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

# Load .env
set -a
source "$DIR/.env"
set +a

echo "Starting ClawdEye Monitor..."

# Start API
node "$DIR/api/server.mjs" &
API_PID=$!

# Start Collector
node "$DIR/collector/index.mjs" &
COLLECTOR_PID=$!

echo "  API server:  PID $API_PID (port ${API_PORT:-4010})"
echo "  Collector:   PID $COLLECTOR_PID"
echo ""
echo "  Dashboard:   http://localhost:${DASHBOARD_PORT:-3000}"
echo ""
echo "  Press Ctrl+C to stop"

cleanup() {
  echo ""
  echo "Shutting down..."
  kill $API_PID $COLLECTOR_PID 2>/dev/null || true
  wait $API_PID $COLLECTOR_PID 2>/dev/null || true
  echo "Stopped."
}
trap cleanup SIGINT SIGTERM

wait
STARTEOF
chmod +x "$INSTALL_DIR/start.sh"
success "Created start.sh"

# ── Create stop script ───────────────────────────────

cat > "$INSTALL_DIR/stop.sh" << 'STOPEOF'
#!/usr/bin/env bash
pkill -f "clawdeye.*server.mjs" 2>/dev/null && echo "API stopped" || echo "API not running"
pkill -f "clawdeye.*index.mjs" 2>/dev/null && echo "Collector stopped" || echo "Collector not running"
STOPEOF
chmod +x "$INSTALL_DIR/stop.sh"
success "Created stop.sh"

# ── Done ──────────────────────────────────────────────

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}  ${BOLD}ClawdEye is installed!${NC}                   ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Start:${NC}     ${INSTALL_DIR}/start.sh"
echo -e "  ${BOLD}Stop:${NC}      ${INSTALL_DIR}/stop.sh"
echo -e "  ${BOLD}Dashboard:${NC} http://localhost:${DASHBOARD_PORT}"
echo -e "  ${BOLD}Files:${NC}     ${INSTALL_DIR}"
echo ""
echo -e "  ${DIM}To update: re-run this installer${NC}"
echo ""
