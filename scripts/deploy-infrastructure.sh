#!/bin/bash

# CoffeeShop Infrastructure Deployment Script
# This script deploys the complete infrastructure using Terraform

set -e

source "$(dirname "$0")/common/utils.sh"

AWS_REGION="us-west-2"
TERRAFORM_DIR="infrastructure"
DRY_RUN=false
ENVIRONMENT="dev"

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            help|-h|--help)
                usage
                exit 0
                ;;
            dev|staging|prod)
                ENVIRONMENT=$1
                shift
                ;;
            *)
                # If it's the first unknown argument and looks like an environment, set it
                if [[ "$1" =~ ^(dev|staging|prod)$ ]]; then
                    ENVIRONMENT=$1
                else
                    error "Unknown parameter: $1"
                fi
                shift
                ;;
        esac
    done
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Checking available tools and configurations..."
    fi
    
    if command_exists aws; then
        log "✓ AWS CLI is installed"
    else
        if [ "$DRY_RUN" = true ]; then
            warn "✗ AWS CLI is not installed. For actual deployment, please install it first."
        else
            error "AWS CLI is not installed. Please install it first."
        fi
    fi
    
    if command_exists terraform; then
        log "✓ Terraform is installed"
        
        # Check Terraform version compatibility
        local tf_version=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [[ "$tf_version" < "1.0.0" ]]; then
            warn "Terraform version $tf_version detected. Recommend version 1.0.0 or higher."
        else
            log "✓ Terraform version $tf_version is compatible"
        fi
    else
        error "Terraform is not installed. Please install it first."
    fi
    
    if command_exists kubectl; then
        log "✓ kubectl is installed"
    else
        if [ "$DRY_RUN" = true ]; then
            warn "✗ kubectl is not installed. For production deployments, please install it first."
        else
            error "kubectl is not installed. Please install it first."
        fi
    fi
    
    if command_exists docker; then
        log "✓ Docker is installed"
    else
        if [ "$DRY_RUN" = true ]; then
            warn "✗ Docker is not installed. For development environment, please install it first."
        else
            error "Docker is not installed. Please install it first."
        fi
    fi
    
    if aws sts get-caller-identity &> /dev/null; then
        log "✓ AWS credentials are configured"
        
        # Validate AWS region if credentials are available
        if ! aws ec2 describe-regions --region-names ${AWS_REGION} &> /dev/null; then
            error "Invalid AWS region: ${AWS_REGION}"
        fi
    else
        if [ "$DRY_RUN" = true ]; then
            warn "✗ AWS credentials not configured. For actual deployment, please run 'aws configure'."
        else
            error "AWS credentials not configured. Please run 'aws configure'."
        fi
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log "Prerequisites check completed (dry run mode)!"
    else
        log "Prerequisites check passed!"
    fi
}

validate_terraform_files() {
    log "Validating Terraform configuration files..."
    
    if [ ! -f "${TERRAFORM_DIR}/main.tf" ]; then
        error "main.tf not found in ${TERRAFORM_DIR}. Please create Terraform configuration files."
    fi
    
    if [ ! -f "${TERRAFORM_DIR}/variables.tf" ]; then
        warn "variables.tf not found in ${TERRAFORM_DIR}. Consider adding variable definitions."
    fi
    
    if [ ! -f "${TERRAFORM_DIR}/outputs.tf" ]; then
        warn "outputs.tf not found in ${TERRAFORM_DIR}. Consider adding output definitions."
    fi
    
    if [ ! -f "${TERRAFORM_DIR}/environments/${ENVIRONMENT}.tfvars" ]; then
        error "Environment variables file not found: ${TERRAFORM_DIR}/environments/${ENVIRONMENT}.tfvars"
    fi
    
    # Check for required modules (custom infrastructure)
    local required_dirs=("modules/vpc" "modules/security" "modules/compute")
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "${TERRAFORM_DIR}/${dir}" ]; then
            warn "Recommended module directory not found: ${dir}. Ensure custom VPC, Security Groups, and Compute resources are defined."
        fi
    done
    
    log "Terraform files validation completed!"
}

setup_ecr_repositories() {
    log "Setting up ECR repositories for CoffeeShop services..."
    
    local services=("web" "proxy" "barista" "kitchen" "counter" "product")
    
    if [ "$DRY_RUN" = true ]; then
        for service in "${services[@]}"; do
            local repo_name="coffeeshop-${service}"
            log "[DRY RUN] Would check/create ECR repository: ${repo_name}"
        done
        log "ECR repositories setup completed (dry run)!"
        return 0
    fi
    
    log "Note: ECR repositories will be created by Terraform modules"
    log "Skipping manual ECR repository creation to avoid conflicts"
    
    log "ECR repositories setup completed!"
}

validate_aws_permissions() {
    log "Validating AWS permissions..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would validate AWS permissions..."
        return 0
    fi
    
    if ! aws ec2 describe-vpcs --max-items 1 &> /dev/null; then
        error "Insufficient EC2 permissions. Please ensure your AWS user has EC2 full access."
    fi
    
    if ! aws s3 ls &> /dev/null; then
        error "Insufficient S3 permissions. Please ensure your AWS user has S3 access."
    fi
    
    if ! aws ecr describe-repositories --max-items 1 &> /dev/null; then
        warn "Limited ECR permissions detected. ECR repository creation may fail."
    fi
    
    if [ "${ENVIRONMENT}" = "prod" ]; then
        if ! aws eks list-clusters &> /dev/null; then
            error "Insufficient EKS permissions for production deployment."
        fi
    fi
    
    if ! aws rds describe-db-instances --max-items 1 &> /dev/null; then
        warn "Limited RDS permissions detected. RDS database creation may fail."
    fi
    
    log "AWS permissions validation completed!"
}

setup_backend() {
    log "Setting up Terraform backend..."
    
    # Use consistent naming based on environment
    BUCKET_NAME="coffeeshop-terraform-state-${ENVIRONMENT}-$(whoami)"
    DYNAMODB_TABLE="terraform-state-locks"
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would create S3 bucket: ${BUCKET_NAME}"
        log "[DRY RUN] Would create DynamoDB table: ${DYNAMODB_TABLE}"
        log "[DRY RUN] Would update backend configuration in ${TERRAFORM_DIR}/main.tf"
        log "Backend setup completed (dry run)!"
        return 0
    fi
    
    # Create S3 bucket for state
    if ! aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
        log "Creating S3 bucket: ${BUCKET_NAME}"
        aws s3 mb "s3://${BUCKET_NAME}" --region ${AWS_REGION}
        aws s3api put-bucket-versioning --bucket ${BUCKET_NAME} --versioning-configuration Status=Enabled
        aws s3api put-bucket-encryption --bucket ${BUCKET_NAME} --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'
        aws s3api put-public-access-block --bucket ${BUCKET_NAME} --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    fi
    
    # Create DynamoDB table for state locking
    if ! aws dynamodb describe-table --table-name ${DYNAMODB_TABLE} --region ${AWS_REGION} 2>/dev/null; then
        log "Creating DynamoDB table: ${DYNAMODB_TABLE}"
        aws dynamodb create-table \
            --table-name ${DYNAMODB_TABLE} \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
            --region ${AWS_REGION}
        
        log "Waiting for DynamoDB table to be ready..."
        aws dynamodb wait table-exists --table-name ${DYNAMODB_TABLE} --region ${AWS_REGION}
    fi
    
    # Update backend configuration with proper escaping
    if [ -f "${TERRAFORM_DIR}/main.tf" ]; then
        cp "${TERRAFORM_DIR}/main.tf" "${TERRAFORM_DIR}/main.tf.backup"
        
        # Update bucket name more precisely
        sed -i.bak "s/bucket[[:space:]]*=[[:space:]]*\"[^\"]*\"/bucket = \"${BUCKET_NAME}\"/" "${TERRAFORM_DIR}/main.tf"
        
        log "Updated backend configuration with bucket: ${BUCKET_NAME}"
    fi
    
    log "Backend setup completed!"
}

deploy_infrastructure() {
    log "Deploying infrastructure for environment: ${ENVIRONMENT}"
    
    cd ${TERRAFORM_DIR}
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Running Terraform dry run for environment: ${ENVIRONMENT}"
        
        # Backup and temporarily disable backend for dry run
        if [ -f "main.tf" ]; then
            cp main.tf main.tf.backup
            # Comment out the backend block
            sed -i '/backend "s3" {/,/}/s/^/# /' main.tf
        fi
        
        # Initialize Terraform without backend
        log "Initializing Terraform..."
        if ! terraform init; then
            # Restore backup if init fails
            [ -f "main.tf.backup" ] && mv main.tf.backup main.tf
            error "Terraform initialization failed"
        fi
        
        # Create workspace if it doesn't exist
        if ! terraform workspace list | grep -q ${ENVIRONMENT}; then
            log "Creating workspace: ${ENVIRONMENT}"
            if ! terraform workspace new ${ENVIRONMENT}; then
                [ -f "main.tf.backup" ] && mv main.tf.backup main.tf
                error "Failed to create Terraform workspace: ${ENVIRONMENT}"
            fi
        else
            log "Selecting workspace: ${ENVIRONMENT}"
            if ! terraform workspace select ${ENVIRONMENT}; then
                [ -f "main.tf.backup" ] && mv main.tf.backup main.tf
                error "Failed to select Terraform workspace: ${ENVIRONMENT}"
            fi
        fi
        
        log "Validating Terraform configuration..."
        if ! terraform validate; then
            [ -f "main.tf.backup" ] && mv main.tf.backup main.tf
            error "Terraform configuration validation failed"
        fi
        
        # For dry run, only validate syntax without requiring AWS credentials
        log "Running Terraform plan (showing what would be created)..."
        log "Note: Skipping actual plan execution in dry run mode to avoid AWS credential requirements"
        
        if aws sts get-caller-identity &> /dev/null; then
            log "AWS credentials detected, running terraform plan..."
            if ! terraform plan -var-file="environments/${ENVIRONMENT}.tfvars"; then
                [ -f "main.tf.backup" ] && mv main.tf.backup main.tf
                error "Terraform planning failed"
            fi
        else
            log "No AWS credentials detected - skipping terraform plan in dry run mode"
            log "Configuration validation passed. Plan would execute with proper AWS credentials."
        fi
        
        if [ -f "main.tf.backup" ]; then
            mv main.tf.backup main.tf
            log "Restored original main.tf configuration"
        fi
        
        log "Infrastructure dry run completed!"
        cd ..
        return 0
    fi
    
    # Regular deployment (non-dry-run)
    log "Initializing Terraform..."
    if ! terraform init; then
        error "Terraform initialization failed"
    fi
    
    if ! terraform workspace list | grep -q ${ENVIRONMENT}; then
        log "Creating workspace: ${ENVIRONMENT}"
        if ! terraform workspace new ${ENVIRONMENT}; then
            error "Failed to create Terraform workspace: ${ENVIRONMENT}"
        fi
    else
        log "Selecting workspace: ${ENVIRONMENT}"
        if ! terraform workspace select ${ENVIRONMENT}; then
            error "Failed to select Terraform workspace: ${ENVIRONMENT}"
        fi
    fi
    
    log "Validating Terraform configuration..."
    if ! terraform validate; then
        error "Terraform configuration validation failed"
    fi
    
    log "Planning infrastructure deployment..."
    if ! terraform plan -var-file="environments/${ENVIRONMENT}.tfvars" -out=${ENVIRONMENT}.tfplan; then
        error "Terraform planning failed"
    fi
    
    log "Applying infrastructure deployment..."
    if ! terraform apply ${ENVIRONMENT}.tfplan; then
        error "Terraform apply failed"
    fi
    
    mkdir -p ../outputs
    if ! terraform output -json > "../outputs/${ENVIRONMENT}-outputs.json"; then
        warn "Failed to save Terraform outputs"
    fi
    
    cd ..
    
    log "Infrastructure deployment completed!"
}

configure_kubectl() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would configure kubectl for production environment"
        return 0
    fi
    
    if [ "${ENVIRONMENT}" = "prod" ]; then
        log "Configuring kubectl for EKS cluster..."
        
        cd ${TERRAFORM_DIR}
        CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "coffeeshop-prod")
        cd ..
        
        if ! aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}; then
            warn "Failed to configure kubectl for EKS cluster"
            return 1
        fi
        
        log "kubectl configured successfully!"
    fi
}

show_deployment_info() {
    info ""
    info "Deployment Summary:"
    info "- Environment: ${ENVIRONMENT}"
    info "- AWS Region: ${AWS_REGION}"
    info "- Terraform Directory: ${TERRAFORM_DIR}"
    
    if [ "$DRY_RUN" = true ]; then
        info "- Mode: DRY RUN (no resources created)"
        return 0
    fi
    
    if [ "${ENVIRONMENT}" = "dev" ]; then
        cd ${TERRAFORM_DIR}
        DEV_IP=$(terraform output -raw dev_instance_public_ip 2>/dev/null || echo 'Check Terraform outputs')
        cd ..
        
        info ""
        info "Development Environment:"
        info "- Instance IP: ${DEV_IP}"
        info "- Next step: Connect to the EC2 instance and run docker-compose"
        info "- SSH command: ssh -i your-key.pem ec2-user@${DEV_IP}"
        
    elif [ "${ENVIRONMENT}" = "prod" ]; then
        info ""
        info "Production Environment:"
        info "- EKS cluster configured"
        info "- Next step: Deploy Kubernetes manifests"
        info "- Run: ./scripts/deploy-k8s.sh"
    fi
    info ""
}

cleanup_on_error() {
    if [ $? -ne 0 ]; then
        warn "Deployment failed. Cleaning up temporary files..."
        cd ${TERRAFORM_DIR} 2>/dev/null || return
        
        # Clean up terraform plan file
        rm -f ${ENVIRONMENT}.tfplan
        
        # Restore main.tf backup if it exists
        if [ -f "main.tf.backup" ]; then
            mv main.tf.backup main.tf
            log "Restored original main.tf configuration"
        fi
    fi
}

usage() {
    local script_name=$(basename "$0")
    
    echo "Usage: $script_name [OPTIONS] [ENVIRONMENT]"
    echo ""
    echo "CoffeeShop Infrastructure Deployment"
    echo ""
    echo "Arguments:"
    echo "  ENVIRONMENT   Target environment (dev|staging|prod) [default: dev]"
    echo ""
    echo "Options:"
    echo "  --dry-run     Show what would be done without executing"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $script_name --dry-run              # Dry run for dev environment"
    echo "  $script_name --dry-run dev          # Dry run for dev environment"
    echo "  $script_name dev                    # Deploy to dev environment"
    echo "  $script_name staging                # Deploy to staging environment"
    echo "  $script_name prod                   # Deploy to production environment"
    echo ""
    echo "Prerequisites:"
    echo "  - AWS CLI installed and configured (for actual deployment)"
    echo "  - Terraform installed"
    echo "  - kubectl installed (for production deployments)"
    echo "  - Proper AWS credentials with required permissions (for actual deployment)"
    echo ""
}

main() {
    parse_arguments "$@"
    
    # Trap to cleanup on error
    trap cleanup_on_error ERR
    
    # Validate environment argument only for deployment commands
    if [[ ! "${ENVIRONMENT}" =~ ^(dev|staging|prod)$ ]]; then
        error "Invalid environment: ${ENVIRONMENT}. Must be one of: dev, staging, prod"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log "🔍 DRY RUN MODE - No AWS resources will be created"
        log "=================================================="
    fi
    
    log "Starting CoffeeShop infrastructure deployment..."
    
    mkdir -p outputs
    
    check_prerequisites
    validate_aws_permissions
    validate_terraform_files
    setup_ecr_repositories
    setup_backend
    deploy_infrastructure
    configure_kubectl
    show_deployment_info
    
    if [ "$DRY_RUN" = true ]; then
        log "🔍 DRY RUN COMPLETED - No actual resources were created"
    else
        log "Infrastructure deployment completed successfully!"
    fi
}

main "$@"