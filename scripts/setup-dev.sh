#!/bin/bash

# CoffeeShop Development Environment Setup Script
# This script sets up the development environment using Docker Compose

set -e

source "$(dirname "$0")/common/utils.sh"

COMPOSE_FILE="development/docker-compose.yml"
PROJECT_NAME="coffeeshop"

check_prerequisites() {
    check_docker_prerequisites true
}

pull_images() {
    local images=(
        "postgres:14-alpine"
        "rabbitmq:3.11-management-alpine"
        "ghcr.io/nongvantinh/devops-training:latest"
    )
    
    pull_docker_images "${images[@]}"
}

start_services() {
    log "Starting CoffeeShop development environment..."
    
    docker_compose -f ${COMPOSE_FILE} -p ${PROJECT_NAME} down --remove-orphans
    docker_compose -f ${COMPOSE_FILE} -p ${PROJECT_NAME} up -d
    
    log "Services started successfully!"
}

wait_for_services() {
    log "Waiting for services to be healthy..."
    
    wait_for_container_cmd "${PROJECT_NAME}_postgres_1" "pg_isready -U postgres -d coffeeshop" 60 "PostgreSQL"
    wait_for_container_cmd "${PROJECT_NAME}_rabbitmq_1" "rabbitmq-diagnostics ping" 60 "RabbitMQ"
    
    wait_for_port "localhost" 5001 60 "Product service"
    wait_for_port "localhost" 5002 60 "Counter service" 
    wait_for_port "localhost" 5000 60 "Proxy service"
    wait_for_port "localhost" 8888 60 "Web service"
    
    # Final verification
    if nc -z localhost 8888 && nc -z localhost 5000 && nc -z localhost 5002 && nc -z localhost 5001; then
        log "All services are healthy and ready!"
    else
        warn "Some services may not be fully ready, but basic connectivity is established"
    fi
}

show_status() {
    log "Service status:"
    docker_compose -f ${COMPOSE_FILE} -p ${PROJECT_NAME} ps
    
    info ""
    info "Service URLs:"
    info "- Web Application: http://localhost:8888"
    info "- Proxy API: http://localhost:5000"
    info "- Product Service: http://localhost:5001"
    info "- Counter Service: http://localhost:5002"
    info "- RabbitMQ Management: http://localhost:15672 (admin/password)"
    info "- PostgreSQL: localhost:5433 (postgres/password)"
    info ""
}

show_logs() {
    if [ "$1" = "logs" ]; then
        if [ -n "$2" ]; then
            log "Showing logs for service: $2"
            docker_compose -f ${COMPOSE_FILE} -p ${PROJECT_NAME} logs -f $2
        else
            log "Showing logs for all services (press Ctrl+C to exit):"
            docker_compose -f ${COMPOSE_FILE} -p ${PROJECT_NAME} logs -f
        fi
    fi
}

stop_services() {
    if [ "$1" = "stop" ]; then
        log "Stopping CoffeeShop development environment..."
        docker_compose -f ${COMPOSE_FILE} -p ${PROJECT_NAME} down
        log "Services stopped successfully!"
        exit 0
    fi
}

cleanup() {
    if [ "$1" = "cleanup" ]; then
        log "Cleaning up CoffeeShop development environment..."
        docker_compose -f ${COMPOSE_FILE} -p ${PROJECT_NAME} down --volumes --remove-orphans
        docker system prune -f
        log "Cleanup completed!"
        exit 0
    fi
}

usage() {
    local script_name=$(basename "$0")
    
    echo "Usage: $script_name [COMMAND]"
    echo ""
    echo "CoffeeShop Development Environment Management"
    echo ""
    echo "Commands:"
    echo "  start         Start all services and set up the development environment (default)"
    echo "  stop          Stop all running services"
    echo "  logs [service] Show logs for all services or a specific service"
    echo "  cleanup       Stop services and remove all containers, volumes, and unused images"
    echo "  help          Show this help message"
    echo ""
    echo "Available services for logs command:"
    echo "  web, proxy, product, counter, barista, kitchen, postgres, rabbitmq"
    echo ""
    echo "Examples:"
    echo "  $script_name                    # Start the development environment"
    echo "  $script_name start              # Start the development environment"
    echo "  $script_name stop               # Stop all services"
    echo "  $script_name logs               # Show logs for all services"
    echo "  $script_name logs web           # Show logs for web service only"
    echo "  $script_name cleanup            # Clean up everything"
    echo ""
}

main() {
    case "${1:-start}" in
        "start")
            log "Starting CoffeeShop development environment setup..."
            check_prerequisites
            pull_images
            start_services
            wait_for_services
            show_status
            log "Development environment setup completed successfully!"
            ;;
        "stop")
            stop_services $1
            ;;
        "logs")
            show_logs $1 $2
            ;;
        "cleanup")
            cleanup $1
            ;;
        "help"|"-h"|"--help")
            usage
            ;;
        *)
            error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"