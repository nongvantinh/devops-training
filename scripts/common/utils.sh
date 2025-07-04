#!/bin/bash

# Common utilities for DevOps training scripts
# Source this file in other scripts: source "$(dirname "$0")/common/utils.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Helper function to use the correct Docker Compose command
docker_compose() {
    if command -v docker-compose &> /dev/null; then
        docker-compose "$@"
    else
        docker compose "$@"
    fi
}

# Check if Docker is installed and accessible
check_docker() {
    log "Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker is not accessible. Please run the following commands:
        
    # Add user to docker group
    sudo usermod -aG docker \$USER
    
    # Start Docker service
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Apply group membership (then logout/login or run)
    newgrp docker
    
    # Verify Docker is working
    docker info"
    fi
    
    log "Docker is available and accessible!"
}

# Check if Docker Compose is available
check_docker_compose() {
    log "Checking Docker Compose..."
    
    if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is not available. Please install Docker Compose first."
    fi
    
    log "Docker Compose is available!"
}

# Check Docker Hub authentication with optional login
check_docker_auth() {
    local auto_login=${1:-false}
    
    log "Checking Docker Hub authentication..."
    if ! docker system info | grep -i "username" &> /dev/null; then
        warn "You are not logged in to Docker Hub. This may cause rate limit issues."
        info "To login to Docker Hub, run: docker login"
        info "If you don't have a Docker Hub account, create one at https://hub.docker.com"
        
        if [ "$auto_login" = "true" ]; then
            read -p "Do you want to login now? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                docker login
                if [ $? -ne 0 ]; then
                    error "Docker login failed. Please try again manually with 'docker login'"
                fi
            else
                warn "Continuing without Docker Hub login. You may encounter rate limits."
            fi
        else
            warn "Continuing without Docker Hub login. You may encounter rate limits."
        fi
    else
        log "Docker Hub authentication verified!"
    fi
}

# Pull a list of Docker images
pull_docker_images() {
    local images=("$@")
    
    log "Pulling Docker images..."
    
    for image in "${images[@]}"; do
        log "Pulling ${image}..."
        if ! docker pull "${image}"; then
            error "Failed to pull image: ${image}"
        fi
    done
    
    log "All images pulled successfully!"
}

# Wait for a service to be ready on a specific port
wait_for_port() {
    local host=${1:-localhost}
    local port=$2
    local timeout=${3:-60}
    local service_name=${4:-"service"}
    
    if [ -z "$port" ]; then
        error "Port number is required for wait_for_port function"
    fi
    
    log "Waiting for ${service_name}..."
    
    if timeout $timeout bash -c "until nc -z $host $port 2>/dev/null; do sleep 2; done"; then
        log "${service_name} is ready on ${host}:${port}!"
        return 0
    else
        warn "${service_name} health check timeout on ${host}:${port}"
        return 1
    fi
}

# Wait for a Docker container command to succeed
wait_for_container_cmd() {
    local container_name=$1
    local command=$2
    local timeout=${3:-60}
    local service_name=${4:-"service"}
    
    if [ -z "$container_name" ] || [ -z "$command" ]; then
        error "Container name and command are required for wait_for_container_cmd function"
    fi
    
    log "Waiting for ${service_name}..."
    
    if timeout $timeout bash -c "until docker exec $container_name $command 2>/dev/null; do sleep 2; done"; then
        log "${service_name} is ready!"
        return 0
    else
        warn "${service_name} health check timeout, but checking if it's actually ready..."
        if docker exec $container_name $command 2>/dev/null; then
            log "${service_name} is ready!"
            return 0
        else
            error "${service_name} failed to start properly"
        fi
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Get script directory (useful for relative paths)
get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
}

# Simple usage function template
show_usage() {
    local script_name=$(basename "$0")
    local commands=("$@")
    
    echo "Usage: $script_name [COMMAND]"
    echo ""
    echo "Commands:"
    for cmd in "${commands[@]}"; do
        echo "  $cmd"
    done
    echo "  help      Show this help message"
    echo ""
}

# Verify prerequisites for Docker-based scripts
check_docker_prerequisites() {
    local auto_login=${1:-false}
    
    log "Checking prerequisites..."
    check_docker
    check_docker_compose
    check_docker_auth "$auto_login"
    log "Prerequisites check passed!"
}