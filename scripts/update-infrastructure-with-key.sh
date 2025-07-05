#!/bin/bash

# Redeploy AWS infrastructure with SSH key pair support
# This script will update the existing deployment to include SSH key access

set -e

source "$(dirname "$0")/common/utils.sh"

ENVIRONMENT="dev"
AWS_REGION="us-west-2"
TERRAFORM_DIR="../infrastructure"

# Check if we're in the right directory
if [ ! -f "${TERRAFORM_DIR}/main.tf" ]; then
    error "This script must be run from the scripts directory"
    exit 1
fi

# Check prerequisites
if ! command_exists aws; then
    error "AWS CLI is not installed"
    exit 1
fi

if [ -z "$AWS_PROFILE" ] || [ "$AWS_PROFILE" != "devops-training" ]; then
    error "AWS_PROFILE must be set to 'devops-training'"
    exit 1
fi

if ! command_exists terraform; then
    error "Terraform is not installed"
    exit 1
fi

log "🔄 Updating AWS infrastructure with SSH key pair support..."

# Copy the private key to a permanent location
if [ -f "/tmp/coffeeshop-dev-key.pem" ]; then
    cp /tmp/coffeeshop-dev-key.pem /home/ubuntu/Projects/devops-training/scripts/coffeeshop-dev-key.pem
    chmod 400 /home/ubuntu/Projects/devops-training/scripts/coffeeshop-dev-key.pem
    log "SSH private key copied to: /home/ubuntu/Projects/devops-training/scripts/coffeeshop-dev-key.pem"
fi

# Navigate to terraform directory
cd ${TERRAFORM_DIR}

# Select dev workspace
terraform workspace select dev || terraform workspace new dev

# Initialize terraform
log "Initializing Terraform..."
terraform init

# Plan the changes
log "Planning infrastructure changes..."
terraform plan -var-file="environments/dev.tfvars" -out=dev-with-key.tfplan

# Ask for confirmation
echo
info "This will update your existing AWS infrastructure to include SSH key pair support."
info "The changes will:"
info "- Add SSH key pair resource"
info "- Update EC2 instance to use the key pair"
info "- Allow SSH access to the EC2 instance"
echo
read -p "Continue with the update? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Update cancelled"
    exit 0
fi

# Apply the changes
log "Applying infrastructure changes..."
terraform apply dev-with-key.tfplan

# Get the instance IP
INSTANCE_IP=$(terraform output -raw dev_instance_public_ip 2>/dev/null || echo '')

cd ..

log "🎉 Infrastructure update completed successfully!"
echo
info "✅ SSH key pair has been added to your AWS infrastructure"
info "✅ EC2 instance now supports SSH access"
info "✅ Instance IP: $INSTANCE_IP"
echo
info "📋 Next steps:"
info "1. Set SSH key path: export SSH_KEY_PATH=/home/ubuntu/Projects/devops-training/scripts/coffeeshop-dev-key.pem"
info "2. Deploy application: ./scripts/deploy-to-ec2.sh"
info "3. Access your application at: http://$INSTANCE_IP:8888"
echo
info "🔑 SSH Access:"
info "ssh -i /home/ubuntu/Projects/devops-training/scripts/coffeeshop-dev-key.pem ec2-user@$INSTANCE_IP"
