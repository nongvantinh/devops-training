#!/bin/bash

# Update security group to allow internet access to web application
# This is a temporary solution for development testing

set -e

source "$(dirname "$0")/common/utils.sh"

ENVIRONMENT="dev"
AWS_REGION="us-west-2"
SECURITY_GROUP_ID="sg-01c66b5999f60c1a3"

# Check prerequisites
if ! command_exists aws; then
    error "AWS CLI is not installed"
    exit 1
fi

if [ -z "$AWS_PROFILE" ] || [ "$AWS_PROFILE" != "devops-training" ]; then
    error "AWS_PROFILE must be set to 'devops-training'"
    exit 1
fi

log "Updating security group to allow internet access to web application..."

# Add HTTP access on port 80 from internet
aws --profile devops-training ec2 authorize-security-group-ingress \
    --region $AWS_REGION \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --output text || warn "Port 80 rule may already exist"

# Add web application access on port 8888 from internet
aws --profile devops-training ec2 authorize-security-group-ingress \
    --region $AWS_REGION \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 8888 \
    --cidr 0.0.0.0/0 \
    --output text || warn "Port 8888 rule may already exist"

# Add proxy access on port 5000 from internet
aws --profile devops-training ec2 authorize-security-group-ingress \
    --region $AWS_REGION \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 5000 \
    --cidr 0.0.0.0/0 \
    --output text || warn "Port 5000 rule may already exist"

log "Security group updated successfully!"
info "Your application should now be accessible from the internet"
info "Access URLs:"
info "- Web Application: http://35.93.150.83:8888"
info "- Proxy API: http://35.93.150.83:5000"
info "- HTTP Proxy: http://35.93.150.83:80"
