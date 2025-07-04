#!/bin/bash

# CoffeeShop DevOps Master Deployment Script
# This script provides a unified interface for all deployment scenarios

set -e

source "$(dirname "$0")/scripts/common/utils.sh"

show_banner() {
    echo "╔═══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                       CoffeeShop DevOps Deployment                           ║"
    echo "║                                                                               ║"
    echo "║   A complete microservices deployment with Infrastructure as Code            ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════════╝"
    echo
}

show_options() {
    info "🚀 Deployment Options:"
    echo
    echo "  1. local     - Local development environment (Docker Compose)"
    echo "                 • No AWS costs"
    echo "                 • 2-minute setup"
    echo "                 • Perfect for testing"
    echo
    echo "  2. aws-dev   - AWS development environment"
    echo "                 • Real AWS infrastructure"
    echo "                 • ~$50/month"
    echo "                 • Great for portfolios"
    echo
    echo "  3. aws-prod  - AWS production environment (EKS)"
    echo "                 • Kubernetes cluster"
    echo "                 • Auto-scaling & monitoring"
    echo "                 • ~$150-300/month"
    echo
    echo "  4. setup-aws - Configure AWS credentials"
    echo "                 • Create devops-training profile"
    echo "                 • Set up permissions"
    echo
    echo "  5. cleanup   - Clean up AWS resources"
    echo "                 • Stop billing"
    echo "                 • Remove all resources"
    echo
}

deploy_local() {
    log "🐳 Starting Local Development Deployment..."
    echo
    
    info "This will start all services locally using Docker Compose"
    info "No AWS costs, perfect for development and testing"
    echo
    
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Deployment cancelled"
        exit 0
    fi
    
    ./scripts/setup-dev.sh
    
    log "🎉 Local deployment completed successfully!"
    echo
    info "🌐 Access your application at: http://localhost:8888"
    info "📊 RabbitMQ management: http://localhost:15672 (guest/guest)"
    info "🗄️  Database: localhost:5432 (postgres/coffeeshop)"
    echo
    info "📝 Useful commands:"
    echo "  ./scripts/setup-dev.sh logs     # View logs"
    echo "  ./scripts/setup-dev.sh stop     # Stop services"
    echo "  ./scripts/setup-dev.sh cleanup  # Clean up everything"
}

deploy_aws_dev() {
    log "☁️ Starting AWS Development Deployment..."
    echo
    
    info "This will create real AWS infrastructure (~$50/month)"
    info "Includes: EC2, RDS, ElastiCache, Load Balancer, ECR"
    echo
    
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Deployment cancelled"
        exit 0
    fi
    
    # Check AWS profile
    if [ -z "$AWS_PROFILE" ] || [ "$AWS_PROFILE" != "devops-training" ]; then
        warn "AWS_PROFILE not set to 'devops-training'"
        echo
        info "Run: export AWS_PROFILE=devops-training"
        info "Or: ./deploy.sh setup-aws"
        exit 1
    fi
    
    # Deploy infrastructure
    ./scripts/deploy-infrastructure.sh dev
    
    log "🎉 AWS development deployment completed successfully!"
    echo
    info "💰 Cost reminder: This deployment costs ~$50/month"
    info "🧹 Clean up when done: ./deploy.sh cleanup"
}

deploy_aws_prod() {
    log "🚢 Starting AWS Production Deployment..."
    echo
    
    info "This will create production infrastructure (~$150-300/month)"
    info "Includes: EKS cluster, managed services, auto-scaling, monitoring"
    echo
    
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Deployment cancelled"
        exit 0
    fi
    
    # Check AWS profile
    if [ -z "$AWS_PROFILE" ] || [ "$AWS_PROFILE" != "devops-training" ]; then
        warn "AWS_PROFILE not set to 'devops-training'"
        echo
        info "Run: export AWS_PROFILE=devops-training"
        info "Or: ./deploy.sh setup-aws"
        exit 1
    fi
    
    # Deploy infrastructure
    ./scripts/deploy-infrastructure.sh prod
    
    # Deploy to Kubernetes
    ./scripts/deploy-k8s.sh
    
    log "🎉 AWS production deployment completed successfully!"
    echo
    info "💰 Cost reminder: This deployment costs ~$150-300/month"
    info "🧹 Clean up when done: ./deploy.sh cleanup"
}

setup_aws() {
    log "🔧 Setting up AWS Configuration..."
    echo
    
    info "This will create a dedicated AWS profile for this project"
    info "You'll need your AWS root account credentials configured first"
    echo
    
    warn "⚠️  IMPORTANT: Make sure you have AWS root/admin credentials configured"
    echo "   If you haven't set up AWS credentials yet, you need to:"
    echo "   1. Get your AWS Access Key ID and Secret Access Key from AWS Console"
    echo "   2. Run: aws configure"
    echo "   3. Enter your ROOT account credentials when prompted"
    echo "   4. Then run this command again"
    echo
    
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Setup cancelled"
        exit 0
    fi
    
    if ./scripts/setup-aws-config.sh create-profile; then
        echo
        log "🎉 AWS configuration completed!"
        echo
        info "📝 Next steps:"
        echo "  export AWS_PROFILE=devops-training"
        echo "  ./deploy.sh aws-dev    # Deploy to AWS development"
        echo "  ./deploy.sh aws-prod   # Deploy to AWS production"
    else
        echo
        error "AWS setup failed. Please follow the instructions above and try again."
        exit 1
    fi
}

cleanup_resources() {
    log "🧹 Cleaning up AWS Resources..."
    echo
    
    warn "This will remove ALL AWS resources and stop billing"
    warn "Make sure you've backed up any important data"
    echo
    
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Cleanup cancelled"
        exit 0
    fi
    
    ./scripts/cleanup-infrastructure.sh
    
    log "🎉 Cleanup completed!"
}

usage() {
    show_banner
    echo "Usage: $0 [OPTION]"
    echo
    show_options
    echo
    echo "Examples:"
    echo "  $0 local          # Start local development"
    echo "  $0 setup-aws      # Configure AWS credentials"
    echo "  $0 aws-dev        # Deploy to AWS development"
    echo "  $0 aws-prod       # Deploy to AWS production"
    echo "  $0 cleanup        # Clean up AWS resources"
    echo
    echo "📖 For detailed instructions, see: STEP_BY_STEP_GUIDE.md"
}

main() {
    case "${1:-help}" in
        "local")
            deploy_local
            ;;
        "aws-dev")
            deploy_aws_dev
            ;;
        "aws-prod")
            deploy_aws_prod
            ;;
        "setup-aws")
            setup_aws
            ;;
        "cleanup")
            cleanup_resources
            ;;
        "help"|"-h"|"--help")
            usage
            ;;
        *)
            show_banner
            warn "Unknown option: $1"
            echo
            show_options
            echo
            info "Run: $0 help"
            exit 1
            ;;
    esac
}

main "$@"
