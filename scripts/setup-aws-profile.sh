#!/bin/bash

# Quick AWS Profile Setup for DevOps Training
# This script provides a streamlined way to set up AWS credentials for this project

set -e

source "$(dirname "$0")/common/utils.sh"

log "DevOps Training AWS Profile Setup"
echo
info "This script will help you create a dedicated AWS profile for this project."
info "You have two options:"
echo
info "1. Create a new AWS user and profile (Recommended)"
info "2. Use existing AWS credentials"
echo
info "Choose option 1 if you want isolated permissions for this project."
info "Choose option 2 if you already have AWS credentials configured."
echo

# Get user choice
while true; do
    read -p "Enter your choice (1 or 2): " choice
    case $choice in
        1)
            echo
            log "Creating new AWS user and profile..."
            ./scripts/setup-aws-config.sh create-profile
            
            echo
            info "Profile created! To use it, run:"
            echo "export AWS_PROFILE=devops-training"
            echo
            info "Add this to your shell profile to make it permanent:"
            echo "echo 'export AWS_PROFILE=devops-training' >> ~/.bashrc"
            echo "source ~/.bashrc"
            break
            ;;
        2)
            echo
            log "Checking existing AWS configuration..."
            ./scripts/setup-aws-config.sh check
            
            echo
            info "If you see permission errors, you may need to:"
            echo "1. Create the required IAM policy: ./scripts/setup-aws-config.sh create-policy"
            echo "2. Attach it to your user (see AWS_PERMISSION_FIX.md for details)"
            break
            ;;
        *)
            warn "Please enter 1 or 2"
            ;;
    esac
done

echo
info "Next steps:"
echo "1. Test the configuration: ./scripts/setup-aws-config.sh test"
echo "2. Run a dry-run: ./scripts/deploy-infrastructure.sh --dry-run"
echo "3. Deploy to AWS: ./scripts/deploy-infrastructure.sh dev"
echo
info "For detailed instructions, see:"
echo "- AWS_PERMISSION_FIX.md (troubleshooting)"
echo "- STEP_BY_STEP_GUIDE.md (complete workflow)"
echo "- DEPLOYMENT_GUIDE.md (detailed guide)"
