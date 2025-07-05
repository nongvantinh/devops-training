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
    info "And deploy the application automatically to EC2"
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
    
    # Deploy infrastructure and application
    ./scripts/deploy-infrastructure.sh dev
    
    log "🎉 AWS development deployment completed successfully!"
    echo
    info "🌐 Your CoffeeShop application is now running on AWS!"
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
    if ! ./scripts/deploy-infrastructure.sh prod; then
        error "Infrastructure deployment failed. Cannot proceed with Kubernetes deployment."
        exit 1
    fi
    
    # Allow some time for EKS cluster to be fully ready
    log "Waiting for EKS cluster to be fully initialized..."
    sleep 30
    
    # Deploy to Kubernetes
    log "Deploying to Kubernetes..."
    if ! ./scripts/deploy-k8s.sh; then
        error "Kubernetes deployment failed. Infrastructure is deployed but application deployment failed."
        echo
        info "💡 Troubleshooting tips:"
        info "1. Check EKS cluster status: aws eks describe-cluster --name coffeeshop-prod --region us-west-2"
        info "2. Configure kubectl manually: aws eks update-kubeconfig --region us-west-2 --name coffeeshop-prod"
        info "3. Check cluster nodes: kubectl get nodes"
        info "4. View deployment logs: kubectl logs -f deployment/<service-name> -n coffeeshop"
        exit 1
    fi
    
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
    
    # Check what environments might exist
    info "Checking for deployed environments..."
    local environments_found=""
    
    if [ -d "infrastructure/terraform.tfstate.d/dev" ] && [ "$(ls -A infrastructure/terraform.tfstate.d/dev 2>/dev/null)" ]; then
        environments_found="${environments_found} dev"
    fi
    
    if [ -d "infrastructure/terraform.tfstate.d/staging" ] && [ "$(ls -A infrastructure/terraform.tfstate.d/staging 2>/dev/null)" ]; then
        environments_found="${environments_found} staging"
    fi
    
    if [ -d "infrastructure/terraform.tfstate.d/prod" ] && [ "$(ls -A infrastructure/terraform.tfstate.d/prod 2>/dev/null)" ]; then
        environments_found="${environments_found} prod"
    fi
    
    if [ -n "$environments_found" ]; then
        info "Found deployed environments:$environments_found"
        echo
        info "This will clean up ALL environments. If you want to clean up specific environments:"
        for env in $environments_found; do
            info "  ./scripts/cleanup-infrastructure.sh $env"
        done
        echo
    fi
    
    read -p "Are you sure you want to clean up ALL environments? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Cleanup cancelled"
        exit 0
    fi
    
    # Clean up all found environments
    for env in $environments_found; do
        log "Cleaning up environment: $env"
        ./scripts/cleanup-infrastructure.sh --force "$env" || warn "Cleanup of $env environment may have failed"
    done
    
    # If no environments found, run default cleanup
    if [ -z "$environments_found" ]; then
        log "No terraform workspaces found, running default cleanup..."
        ./scripts/cleanup-infrastructure.sh
    fi
    
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
