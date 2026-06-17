#!/usr/bin/env bash
# Jarvis Setup Script
# Sets up and launches the Jarvis AI assistant backend.

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
step()    { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }

# ---------------------------------------------------------------------------
# Script root = parent of scripts/ directory
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo -e ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║          JARVIS SETUP SCRIPT             ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo -e ""

# ---------------------------------------------------------------------------
# Step 1: Check Docker
# ---------------------------------------------------------------------------
step "Checking Docker..."

if ! command -v docker &>/dev/null; then
    error "Docker is not installed."
    echo "  Install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi
success "Docker found: $(docker --version)"

if ! docker info &>/dev/null 2>&1; then
    error "Docker daemon is not running. Please start Docker and try again."
    exit 1
fi
success "Docker daemon is running"

if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null 2>&1; then
    error "docker-compose (or docker compose plugin) is not available."
    echo "  Install Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi

# Prefer 'docker compose' (v2 plugin) over standalone 'docker-compose'
if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi
success "Docker Compose found: $($COMPOSE_CMD version --short 2>/dev/null || echo 'v1')"

# ---------------------------------------------------------------------------
# Step 2: Check Ollama
# ---------------------------------------------------------------------------
step "Checking Ollama..."

if ! command -v ollama &>/dev/null; then
    warn "Ollama is not installed."
    echo ""
    echo "  To install Ollama (recommended for local AI):"
    echo "    Linux/macOS: curl -fsSL https://ollama.com/install.sh | sh"
    echo "    Windows:     https://ollama.com/download"
    echo ""
    echo "  Jarvis will fall back to Groq API (set GROQ_API_KEY in .env)"
    OLLAMA_AVAILABLE=false
else
    success "Ollama found: $(ollama --version 2>/dev/null || echo 'installed')"
    OLLAMA_AVAILABLE=true
fi

# ---------------------------------------------------------------------------
# Step 3: Pull Ollama model
# ---------------------------------------------------------------------------
step "Setting up Ollama model..."

OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.1:8b}"

if [ "$OLLAMA_AVAILABLE" = true ]; then
    # Check if model already exists
    if ollama list 2>/dev/null | grep -q "${OLLAMA_MODEL%%:*}"; then
        success "Ollama model '$OLLAMA_MODEL' is already available"
    else
        info "Pulling Ollama model '$OLLAMA_MODEL' (this may take a few minutes)..."
        if ollama pull "$OLLAMA_MODEL"; then
            success "Ollama model '$OLLAMA_MODEL' pulled successfully"
        else
            warn "Failed to pull Ollama model. You can pull it manually: ollama pull $OLLAMA_MODEL"
        fi
    fi
else
    info "Skipping Ollama model pull (Ollama not installed)"
fi

# ---------------------------------------------------------------------------
# Step 4: Set up .env
# ---------------------------------------------------------------------------
step "Setting up environment file..."

if [ -f "$PROJECT_ROOT/.env" ]; then
    success ".env already exists, keeping it"
else
    if [ -f "$PROJECT_ROOT/.env.example" ]; then
        cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
        success "Created .env from .env.example"
        warn "Please review and update $PROJECT_ROOT/.env with your settings"
        echo ""
        echo "  Key settings to configure:"
        echo "    SECRET_KEY   - Change to a random secure string"
        echo "    USER_PASSWORD - Your Jarvis login password"
        echo "    GROQ_API_KEY  - Optional: Get free key at https://console.groq.com"
        echo ""
    else
        warn ".env.example not found, creating minimal .env"
        cat > "$PROJECT_ROOT/.env" << 'EOF'
SECRET_KEY=jarvis-secret-2024-change-me
USER_PASSWORD=jarvis2024
OLLAMA_URL=http://host.docker.internal:11434
OLLAMA_MODEL=llama3.1:8b
GROQ_API_KEY=
WHISPER_MODEL=base
EOF
        success "Created minimal .env"
    fi
fi

# ---------------------------------------------------------------------------
# Step 5: Create models directory
# ---------------------------------------------------------------------------
step "Creating models directory..."
mkdir -p "$PROJECT_ROOT/models/piper"
success "Models directory ready at $PROJECT_ROOT/models/"

# ---------------------------------------------------------------------------
# Step 6: Build and start Docker Compose
# ---------------------------------------------------------------------------
step "Building Docker images..."
info "This may take several minutes on first run..."

if ! $COMPOSE_CMD build; then
    error "Docker build failed. Check the output above for details."
    exit 1
fi
success "All images built successfully"

step "Starting Jarvis services..."

if ! $COMPOSE_CMD up -d; then
    error "Failed to start services. Check the output above."
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 7: Wait for services to be healthy
# ---------------------------------------------------------------------------
step "Waiting for services to start..."

MAX_WAIT=60
WAITED=0
SERVICES_UP=false

while [ $WAITED -lt $MAX_WAIT ]; do
    sleep 3
    WAITED=$((WAITED + 3))

    GATEWAY_OK=false
    if curl -sf http://localhost:8000/health >/dev/null 2>&1; then
        GATEWAY_OK=true
    fi

    if [ "$GATEWAY_OK" = true ]; then
        SERVICES_UP=true
        break
    fi

    echo -n "."
done
echo ""

if [ "$SERVICES_UP" = true ]; then
    success "All services are up!"
else
    warn "Services may still be starting. Check status with: $COMPOSE_CMD ps"
fi

# ---------------------------------------------------------------------------
# Step 8: Show container status
# ---------------------------------------------------------------------------
step "Container status:"
$COMPOSE_CMD ps

# ---------------------------------------------------------------------------
# Success banner
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║         JARVIS IS READY!                         ║${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║                                                  ║${NC}"
echo -e "${BOLD}${GREEN}║  API Gateway:    http://localhost:8000            ║${NC}"
echo -e "${BOLD}${GREEN}║  AI Engine:      http://localhost:8001            ║${NC}"
echo -e "${BOLD}${GREEN}║  Memory Engine:  http://localhost:8002            ║${NC}"
echo -e "${BOLD}${GREEN}║  Notes Service:  http://localhost:8003            ║${NC}"
echo -e "${BOLD}${GREEN}║                                                  ║${NC}"
echo -e "${BOLD}${GREEN}║  API Docs:       http://localhost:8000/docs       ║${NC}"
echo -e "${BOLD}${GREEN}║  Health Check:   http://localhost:8000/health     ║${NC}"
echo -e "${BOLD}${GREEN}║                                                  ║${NC}"
echo -e "${BOLD}${GREEN}║  Username: jarvis                                ║${NC}"
echo -e "${BOLD}${GREEN}║  Password: (see USER_PASSWORD in .env)           ║${NC}"
echo -e "${BOLD}${GREEN}║                                                  ║${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║  Useful commands:                                ║${NC}"
echo -e "${BOLD}${GREEN}║  Logs:   $COMPOSE_CMD logs -f            ║${NC}"
echo -e "${BOLD}${GREEN}║  Stop:   $COMPOSE_CMD down               ║${NC}"
echo -e "${BOLD}${GREEN}║  Restart: $COMPOSE_CMD restart           ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
