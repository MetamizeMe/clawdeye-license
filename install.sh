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

# Check Docker
if ! command -v docker &>/dev/null; then
  error "Docker is not installed."
  echo "  Install Docker: https://docs.docker.com/get-docker/"
  exit 1
fi

if ! docker info &>/dev/null 2>&1; then
  error "Docker is not running. Please start Docker and try again."
  exit 1
fi

# Check docker compose
if docker compose version &>/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE="docker-compose"
else
  error "Docker Compose is not installed."
  echo "  Install Docker Compose: https://docs.docker.com/compose/install/"
  exit 1
fi

success "Docker is running"

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

echo ""
echo -e "${BOLD}Network${NC} ${DIM}(press Enter to accept defaults)${NC}"
echo -e "${DIM}─────────────────────────────────────────${NC}"

GATEWAY_HOST=$(ask "Gateway host" "host.docker.internal")
GATEWAY_PORT=$(ask "Gateway port" "18789")
DASHBOARD_PORT=$(ask "Dashboard port" "3000")

# ── Verify paths ──────────────────────────────────────

echo ""
for p in "$CLAWD_HOME" "$CLAWDBOT_HOME" "$OPENCLAW_HOME"; do
  expanded=$(eval echo "$p")
  if [ -d "$expanded" ]; then
    success "Found $expanded"
  else
    warn "Directory not found: $expanded (will be created if needed)"
  fi
done

# ── Confirm ───────────────────────────────────────────

echo ""
echo -e "${BOLD}Summary${NC}"
echo -e "${DIM}─────────────────────────────────────────${NC}"
echo -e "  Install to:      ${BOLD}${INSTALL_DIR}${NC}"
echo -e "  Dashboard:       ${BOLD}http://localhost:${DASHBOARD_PORT}${NC}"
echo -e "  Clawd workspace: ${CLAWD_HOME}"
echo -e "  Gateway:         ${GATEWAY_HOST}:${GATEWAY_PORT}"
echo ""

CONFIRM=$(ask "Proceed with installation? (y/n)" "y")
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
  info "Installation cancelled."
  exit 0
fi

# ── Create files ──────────────────────────────────────

echo ""
info "Creating ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"

# .env
cat > "$INSTALL_DIR/.env" << EOF
CLAWDEYE_LICENSE=${LICENSE}
DASHBOARD_TOKEN=${PASSWORD}
CLAWD_HOME=${CLAWD_HOME}
CLAWDBOT_HOME=${CLAWDBOT_HOME}
OPENCLAW_HOME=${OPENCLAW_HOME}
GATEWAY_HOST=${GATEWAY_HOST}
GATEWAY_PORT=${GATEWAY_PORT}
DASHBOARD_PORT=${DASHBOARD_PORT}
EOF
success "Created .env"

# docker-compose.yml
cat > "$INSTALL_DIR/docker-compose.yml" << 'EOF'
# ClawdEye Monitor — Docker Compose
# Managed by install script. Edit .env to change settings.

services:
  clawdeye:
    image: metamize/clawdeye:latest
    container_name: clawdeye
    ports:
      - "${DASHBOARD_PORT:-3000}:3000"
    volumes:
      - clawdeye-data:/app/data
      - ${CLAWD_HOME:-~/clawd}:/clawd:ro
      - ${CLAWDBOT_HOME:-~/.clawdbot}:/clawdbot:ro
      - ${OPENCLAW_HOME:-~/.openclaw}:/openclaw:ro
    environment:
      - DATABASE_URL=file:/app/data/openclaw.db
      - CLAWDEYE_ROOT=/app
      - CLAWDEYE_DATA_DIR=/app/data
      - API_HOST=0.0.0.0
      - API_PORT=4010
      - API_INTERNAL_URL=http://127.0.0.1:4010
      - CLAWD_HOME=/clawd
      - CLAWDBOT_HOME=/clawdbot
      - OPENCLAW_HOME=/openclaw
      - GATEWAY_HOST=${GATEWAY_HOST:-host.docker.internal}
      - GATEWAY_PORT=${GATEWAY_PORT:-18789}
      - DASHBOARD_TOKEN=${DASHBOARD_TOKEN:-changeme}
      - CLAWDEYE_LICENSE=${CLAWDEYE_LICENSE}
    extra_hosts:
      - "host.docker.internal:host-gateway"
    restart: unless-stopped

volumes:
  clawdeye-data:
EOF
success "Created docker-compose.yml"

# ── Pull & Start ──────────────────────────────────────

info "Pulling ClawdEye image..."
cd "$INSTALL_DIR"
$COMPOSE pull

echo ""
info "Starting ClawdEye..."
$COMPOSE up -d

# ── Done ──────────────────────────────────────────────

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}  ${BOLD}ClawdEye is running!${NC}                     ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Dashboard:${NC}  http://localhost:${DASHBOARD_PORT}"
echo -e "  ${BOLD}Password:${NC}   (the one you just entered)"
echo -e "  ${BOLD}Files:${NC}      ${INSTALL_DIR}"
echo ""
echo -e "  ${DIM}Update:  cd ${INSTALL_DIR} && ${COMPOSE} pull && ${COMPOSE} up -d${NC}"
echo -e "  ${DIM}Stop:    cd ${INSTALL_DIR} && ${COMPOSE} down${NC}"
echo -e "  ${DIM}Logs:    cd ${INSTALL_DIR} && ${COMPOSE} logs -f${NC}"
echo ""
