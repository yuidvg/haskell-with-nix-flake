#!/usr/bin/env bash

# enter-nix-flake-env.sh - Enter Nix flake environment in one shot
# Idempotent and reentrant script with optional cleanup functionality

set -euo pipefail

# === Constants (immutable) ===
readonly SCRIPT_NAME="$(basename "$0")"
readonly USER_HOME="$HOME"
readonly GOINFRE_DIR="$USER_HOME/goinfre"
readonly DOCKER_DATA_DIR="$GOINFRE_DIR/docker"
readonly DOCKER_TMP_DIR="$GOINFRE_DIR/tmp"
readonly SYSTEMD_USER_DIR="$USER_HOME/.config/systemd/user"
readonly DOCKER_SERVICE_FILE="$SYSTEMD_USER_DIR/docker.service"
readonly DOCKERFILE_PATH="./Dockerfile"
readonly IMAGE_NAME="nix-flake-env"
readonly LOG_LEVEL=${LOG_LEVEL:-INFO}

# === Utility Functions ===
log_info() {
    [[ "$LOG_LEVEL" != "QUIET" ]] && echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_success() {
    echo "[SUCCESS] $*" >&2
}

log_warning() {
    echo "[WARNING] $*" >&2
}

show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Enter Nix flake environment in one shot with rootless Docker.

OPTIONS:
    --cleanup     Clean up all side effects and exit
    --help        Show this help message

SIDE EFFECTS:
This script creates the following persistent changes:
  • ~/.config/systemd/user/docker.service (systemd service file)
  • Docker systemd service enabled for user
  • ~/goinfre/docker/ (Docker data directory)
  • ~/goinfre/tmp/ (Docker temporary directory)
  • Docker images built from Dockerfile

All Docker data is stored in ~/goinfre/ to avoid home directory quota issues.
Use --cleanup to remove all side effects.

EOF
}

# === Cleanup Functions ===

cleanup_docker_service() {
    log_info "Cleaning up Docker service..."

    # Stop and disable Docker service
    if systemctl --user is-active --quiet docker 2>/dev/null; then
        log_info "Stopping Docker service..."
        systemctl --user stop docker || true
    fi

    if systemctl --user is-enabled --quiet docker 2>/dev/null; then
        log_info "Disabling Docker service..."
        systemctl --user disable docker || true
    fi

    # Remove service file
    if [[ -f "$DOCKER_SERVICE_FILE" ]]; then
        log_info "Removing Docker service file..."
        rm -f "$DOCKER_SERVICE_FILE"
    fi

    # Reload systemd
    systemctl --user daemon-reload || true

    log_success "Docker service cleaned up"
}

cleanup_docker_data() {
    log_info "Cleaning up Docker data..."

    # Remove Docker images
    if command -v docker >/dev/null 2>&1; then
        # Set environment variables for cleanup
        export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"
        export TMPDIR="$DOCKER_TMP_DIR"
        export XDG_DATA_HOME="$GOINFRE_DIR"

        # Remove specific image
        if docker images -q "$IMAGE_NAME" 2>/dev/null | grep -q .; then
            log_info "Removing Docker image: $IMAGE_NAME"
            docker rmi "$IMAGE_NAME" 2>/dev/null || true
        fi

        # Clean up all unused images, containers, networks, and volumes
        log_info "Cleaning up unused Docker resources..."
        docker system prune -af 2>/dev/null || true
    fi

    # Remove Docker data directory with proper permission handling
    if [[ -d "$DOCKER_DATA_DIR" ]]; then
        log_info "Removing Docker data directory: $DOCKER_DATA_DIR"

        # First try to change permissions to make files deletable
        if command -v find >/dev/null 2>&1; then
            log_info "Fixing permissions for Docker data cleanup..."
            find "$DOCKER_DATA_DIR" -type d -exec chmod 755 {} + 2>/dev/null || true
            find "$DOCKER_DATA_DIR" -type f -exec chmod 644 {} + 2>/dev/null || true
        fi

        # Remove the directory
        rm -rf "$DOCKER_DATA_DIR" 2>/dev/null || {
            log_warning "Some files could not be removed due to permissions"
            log_info "Attempting to remove what we can..."

            # Try to remove individual directories that might work
            for subdir in "$DOCKER_DATA_DIR"/*; do
                [[ -d "$subdir" ]] && rm -rf "$subdir" 2>/dev/null || true
            done

            # If directory is now empty, remove it
            if [[ -d "$DOCKER_DATA_DIR" ]] && [[ -z "$(ls -A "$DOCKER_DATA_DIR" 2>/dev/null)" ]]; then
                rmdir "$DOCKER_DATA_DIR" 2>/dev/null || true
            fi
        }
    fi

    # Remove Docker temp directory
    if [[ -d "$DOCKER_TMP_DIR" ]]; then
        log_info "Removing Docker temp directory: $DOCKER_TMP_DIR"
        rm -rf "$DOCKER_TMP_DIR" 2>/dev/null || true
    fi

    log_success "Docker data cleanup completed"
}

cleanup_goinfre_directories() {
    log_info "Cleaning up goinfre directories..."

    # Remove empty goinfre directory if it exists and is empty
    if [[ -d "$GOINFRE_DIR" ]]; then
        if [[ -z "$(ls -A "$GOINFRE_DIR" 2>/dev/null)" ]]; then
            log_info "Removing empty goinfre directory: $GOINFRE_DIR"
            rmdir "$GOINFRE_DIR" 2>/dev/null || true
        else
            log_warning "Goinfre directory not empty, keeping: $GOINFRE_DIR"
            log_info "Remaining contents:"
            ls -la "$GOINFRE_DIR" 2>/dev/null || true
        fi
    fi

    log_success "Goinfre directories cleaned up"
}

perform_complete_cleanup() {
    log_info "🧹 Performing complete cleanup of all side effects..."
    echo ""

    cleanup_docker_service
    cleanup_docker_data
    cleanup_goinfre_directories

    echo ""
    log_success "✅ Complete cleanup finished!"
    log_info "All side effects have been removed from the system."
}

# === Core Functions ===

ensure_goinfre_directories() {
    log_info "Ensuring goinfre directories exist..."

    local directories=(
        "$DOCKER_DATA_DIR"
        "$DOCKER_TMP_DIR"
        "$SYSTEMD_USER_DIR"
    )

    for dir in "${directories[@]}"; do
        [[ -d "$dir" ]] || mkdir -p "$dir"
    done

    log_success "Goinfre directories ready"
}

setup_docker_environment() {
    log_info "Setting up Docker environment..."

    # Set environment variables for this session
    export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"
    export TMPDIR="$DOCKER_TMP_DIR"
    export XDG_DATA_HOME="$GOINFRE_DIR"

    log_success "Docker environment variables set"
}

is_docker_dir_goinfre() {
    docker system info --format '{{.DockerRootDir}}' 2>/dev/null | grep -q "goinfre"
    return $?
}

ensure_rootless_docker() {
    log_info "Ensuring rootless Docker is configured..."

    # Check if Docker is already using goinfre
    if is_docker_dir_goinfre; then
        log_success "Docker is already using goinfre storage"
        return 0
    fi

    # Check prerequisites
    if [[ "$EUID" -eq 0 ]]; then
        log_error "This script should not be run as root"
        return 1
    fi

    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed"
        return 1
    fi

    if ! command -v dockerd-rootless-setuptool.sh >/dev/null 2>&1; then
        log_error "dockerd-rootless-setuptool.sh not found"
        return 1
    fi

    # Stop existing Docker services
    systemctl --user stop docker 2>/dev/null || true

    # Install rootless Docker if not already installed
    if ! systemctl --user is-enabled docker >/dev/null 2>&1; then
        log_info "Installing rootless Docker..."
        dockerd-rootless-setuptool.sh install >/dev/null 2>&1 || {
            log_error "Failed to install rootless Docker"
            return 1
        }
    fi

    # Configure Docker service for goinfre storage
    log_info "Configuring Docker service for goinfre storage..."

    cat > "$DOCKER_SERVICE_FILE" << EOF
[Unit]
Description=Docker Application Container Engine (Rootless)
Documentation=https://docs.docker.com/go/rootless/

[Service]
Environment=PATH=/usr/bin:/sbin:/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin
Environment=XDG_DATA_HOME=$GOINFRE_DIR
Environment=TMPDIR=$DOCKER_TMP_DIR
ExecStart=/usr/bin/dockerd-rootless.sh
ExecReload=/bin/kill -s HUP \$MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
Type=notify
NotifyAccess=all
KillMode=mixed

[Install]
WantedBy=default.target
EOF

    # Reload and start Docker
    systemctl --user daemon-reload
    systemctl --user enable docker
    systemctl --user start docker

    # Wait for Docker to be ready
    local max_attempts=30
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        if docker version >/dev/null 2>&1; then
            break
        fi
        ((attempt++))
        sleep 1
    done

    if [[ $attempt -eq $max_attempts ]]; then
        log_error "Docker failed to start"
        return 1
    fi

    log_success "Rootless Docker configured successfully"
}

verify_docker_goinfre() {
    log_info "Verifying Docker is using goinfre storage..."

    local docker_root_dir
    docker_root_dir=$(docker system info --format '{{.DockerRootDir}}' 2>/dev/null) || {
        log_error "Failed to get Docker system info"
        return 1
    }

    if [[ "$docker_root_dir" == *"goinfre"* ]]; then
        log_success "✓ Docker root directory: $docker_root_dir"
        return 0
    else
        log_error "✗ Docker is not using goinfre storage: $docker_root_dir"
        return 1
    fi
}

build_and_enter_nix_container() {
    log_info "Building and entering Nix container..."

    # Check if Dockerfile exists
    if [[ ! -f "$DOCKERFILE_PATH" ]]; then
        log_error "Dockerfile not found at $DOCKERFILE_PATH"
        return 1
    fi

    # Build the image (idempotent - uses cache if unchanged)
    log_info "Building Docker image from $DOCKERFILE_PATH..."
    docker build -t "$IMAGE_NAME" . || {
        log_error "Failed to build Docker image"
        return 1
    }

    log_success "Docker image built successfully"

    # Enter the container with current directory mounted
    log_info "Entering Nix flake environment..."
    log_success "🚀 Entering Nix container with flake support!"

    # Execute the container interactively
    exec docker run -it --rm \
        -v "$(pwd)":/workspace \
        -w /workspace \
        "$IMAGE_NAME" \
        bash
}

show_side_effects() {
    log_info "=== Current Side Effects ==="
    echo ""

    # Check systemd service
    if [[ -f "$DOCKER_SERVICE_FILE" ]]; then
        echo "✓ Docker systemd service: $DOCKER_SERVICE_FILE"
        if systemctl --user is-enabled docker >/dev/null 2>&1; then
            echo "  Status: enabled"
        else
            echo "  Status: disabled"
        fi
    else
        echo "✗ Docker systemd service: not found"
    fi

    # Check Docker data directory
    if [[ -d "$DOCKER_DATA_DIR" ]]; then
        local size=$(du -sh "$DOCKER_DATA_DIR" 2>/dev/null | cut -f1)
        echo "✓ Docker data directory: $DOCKER_DATA_DIR ($size)"
    else
        echo "✗ Docker data directory: not found"
    fi

    # Check Docker temp directory
    if [[ -d "$DOCKER_TMP_DIR" ]]; then
        local size=$(du -sh "$DOCKER_TMP_DIR" 2>/dev/null | cut -f1)
        echo "✓ Docker temp directory: $DOCKER_TMP_DIR ($size)"
    else
        echo "✗ Docker temp directory: not found"
    fi

    # Check Docker images
    if command -v docker >/dev/null 2>&1; then
        export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"
        export TMPDIR="$DOCKER_TMP_DIR"
        export XDG_DATA_HOME="$GOINFRE_DIR"

        if docker images -q "$IMAGE_NAME" 2>/dev/null | grep -q .; then
            local size=$(docker images "$IMAGE_NAME" --format "table {{.Size}}" | tail -n1)
            echo "✓ Docker image: $IMAGE_NAME ($size)"
        else
            echo "✗ Docker image: $IMAGE_NAME not found"
        fi
    fi

    echo ""
    log_info "All side effects are contained in ~/goinfre/ and ~/.config/systemd/user/"
    log_info "Use '$SCRIPT_NAME --cleanup' to remove all side effects"
}

# === Main Execution ===
main() {
    # Parse command line arguments
    case "${1:-}" in
        --help|-h)
            show_usage
            exit 0
            ;;
        --cleanup)
            perform_complete_cleanup
            exit 0
            ;;
        --show-side-effects)
            show_side_effects
            exit 0
            ;;
        "")
            # Normal execution
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac

    log_info "🎯 Entering Nix flake environment in one shot..."
    echo ""

    ensure_goinfre_directories
    setup_docker_environment
    ensure_rootless_docker
    verify_docker_goinfre
    build_and_enter_nix_container

    # This line should never be reached due to exec
    log_error "Failed to enter container"
    exit 1
}

# Execute main function
main "$@"