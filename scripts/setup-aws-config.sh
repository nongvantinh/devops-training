#!/bin/bash

# AWS Configuration Helper Script
# This script helps configure AWS credentials for CoffeeShop deployment

set -e

source "$(dirname "$0")/common/utils.sh"

check_aws_config() {
    log "Checking current AWS configuration..."
    
    if aws sts get-caller-identity &>/dev/null; then
        log "✅ AWS credentials are configured"
        local current_user=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null)
        info "Current identity: $current_user"
        
        # Check if using recommended profile
        if echo "$current_user" | grep -q "devops-training-user"; then
            log "✅ Using recommended devops-training profile"
        elif [ -n "${AWS_PROFILE}" ] && [ "${AWS_PROFILE}" = "devops-training" ]; then
            log "✅ AWS_PROFILE set to devops-training"
        else
            warn "Not using devops-training profile (recommended)"
            info "Run: export AWS_PROFILE=devops-training"
        fi
    else
        error "AWS credentials not configured. Run: ./scripts/setup-aws-config.sh create-profile"
    fi
}

test_permissions() {
    log "Testing required AWS permissions..."
    
    local failed_tests=0
    
    # Test essential permissions
    if aws ec2 describe-availability-zones --region us-west-2 &>/dev/null; then
        log "✅ EC2 permissions: PASS"
    else
        warn "❌ EC2 permissions: FAIL"
        ((failed_tests++))
    fi
    
    if aws elasticache describe-cache-clusters --region us-west-2 --max-items 1 &>/dev/null; then
        log "✅ ElastiCache permissions: PASS"
    else
        warn "❌ ElastiCache permissions: FAIL"
        ((failed_tests++))
    fi
    
    if aws iam get-user &>/dev/null; then
        log "✅ IAM permissions: PASS"
    else
        warn "❌ IAM permissions: FAIL"
        ((failed_tests++))
    fi
    
    echo
    if [ $failed_tests -eq 0 ]; then
        log "🎉 All permission tests passed!"
        return 0
    else
        warn "⚠️  $failed_tests permission test(s) failed"
        warn "Run: ./scripts/setup-aws-config.sh fix-permissions"
        return 1
    fi
}

create_devops_profile() {
    log "Creating DevOps Training AWS Profile..."
    echo
    
    # Check if we have AWS credentials configured first
    if ! aws sts get-caller-identity &>/dev/null; then
        error "No AWS credentials found. You need to configure AWS root/admin credentials first."
        echo
        info "To fix this, you need to:"
        echo "1. Get your AWS Root Account Access Key ID and Secret Access Key from the AWS Console"
        echo "2. Run: aws configure"
        echo "3. Enter your ROOT account credentials when prompted"
        echo "4. Then run this script again"
        echo
        info "⚠️  IMPORTANT: This script will use your root credentials to create a separate"
        info "   'devops-training' profile. Your root credentials will remain unchanged."
        echo
        info "For detailed instructions, see: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html"
        exit 1
    fi
    
    # Check if current user has IAM permissions
    if ! aws iam get-user &>/dev/null; then
        error "Current AWS user doesn't have IAM permissions."
        echo
        info "You need to use AWS root account credentials or an IAM user with administrator permissions."
        echo "Make sure your current AWS credentials have the following permissions:"
        echo "- iam:CreateUser"
        echo "- iam:CreatePolicy"
        echo "- iam:AttachUserPolicy"
        echo "- iam:CreateAccessKey"
        echo "- iam:ListPolicies"
        echo "- iam:GetUser"
        echo
        info "💡 TIP: If you're using root credentials, these permissions are included by default."
        exit 1
    fi
    
    # Show what profile we're currently using
    local current_identity=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null)
    info "Current AWS identity: $current_identity"
    
    # Check if we're about to overwrite an existing devops-training profile
    if aws configure list --profile devops-training &>/dev/null; then
        warn "AWS profile 'devops-training' already exists."
        echo
        read -p "Do you want to recreate it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Setup cancelled. Existing profile preserved."
            exit 0
        fi
    fi
    
    local user_name="devops-training-user"
    local policy_name="DevOpsTrainingTerraformPolicy"
    local profile_name="devops-training"
    local policy_file="infrastructure/terraform-iam-policy.json"
    
    if [ ! -f "$policy_file" ]; then
        error "Policy file $policy_file not found"
    fi
    
    # Step 1: Create IAM user
    info "Creating IAM user '$user_name'..."
    if aws iam create-user --user-name "$user_name" &>/dev/null; then
        log "✅ IAM user created successfully"
    else
        info "ℹ️  IAM user already exists"
    fi
    
    # Step 2: Create IAM policy
    info "Creating IAM policy '$policy_name'..."
    if aws iam create-policy --policy-name "$policy_name" --policy-document file://"$policy_file" &>/dev/null; then
        log "✅ IAM policy created successfully"
    else
        info "ℹ️  IAM policy already exists"
    fi
    
    # Step 3: Attach policy to user
    info "Attaching policy to user..."
    local policy_arn=$(aws iam list-policies --query "Policies[?PolicyName=='$policy_name'].Arn" --output text)
    if aws iam attach-user-policy --user-name "$user_name" --policy-arn "$policy_arn" &>/dev/null; then
        log "✅ Policy attached successfully"
    else
        info "ℹ️  Policy already attached"
    fi
    
    # Step 4: Clean up existing access keys if needed
    info "Checking for existing access keys..."
    local existing_keys=$(aws iam list-access-keys --user-name "$user_name" --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null)
    if [ -n "$existing_keys" ]; then
        warn "Found existing access keys for user '$user_name'"
        echo "Existing keys: $existing_keys"
        read -p "Delete existing keys and create new ones? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for key in $existing_keys; do
                info "Deleting access key: $key"
                aws iam delete-access-key --user-name "$user_name" --access-key-id "$key"
            done
            log "✅ Old access keys deleted"
        else
            error "Cannot create new access keys. User already has maximum number of keys."
            info "Please delete existing keys manually or choose to delete them above."
            exit 1
        fi
    fi
    
    # Step 5: Create access keys
    info "Creating access keys..."
    local access_key_output=$(aws iam create-access-key --user-name "$user_name" 2>/dev/null)
    if [ $? -eq 0 ]; then
        local access_key_id=$(echo "$access_key_output" | grep -o '"AccessKeyId": "[^"]*"' | cut -d'"' -f4)
        local secret_access_key=$(echo "$access_key_output" | grep -o '"SecretAccessKey": "[^"]*"' | cut -d'"' -f4)
        
        log "✅ Access keys created successfully"
        echo
        
        # Step 6: Configure AWS profile
        info "Configuring AWS profile '$profile_name'..."
        aws configure set aws_access_key_id "$access_key_id" --profile "$profile_name"
        aws configure set aws_secret_access_key "$secret_access_key" --profile "$profile_name"
        aws configure set region "us-west-2" --profile "$profile_name"
        aws configure set output "json" --profile "$profile_name"
        
        log "✅ AWS profile '$profile_name' configured successfully"
        echo
        info "🎯 Next steps:"
        echo "1. Set the profile: export AWS_PROFILE=devops-training"
        echo "2. Test the setup: ./scripts/setup-aws-config.sh test"
        
    else
        warn "❌ Failed to create access keys (user may already have 2 keys)"
        info "Check existing keys: aws iam list-access-keys --user-name $user_name"
    fi
}

fix_permissions() {
    log "Fixing devops-training-user permissions..."
    
    local user_name="devops-training-user"
    local policy_name="DevOpsTrainingTerraformPolicy"
    
    # Check if user exists
    if ! aws iam get-user --user-name "$user_name" &>/dev/null; then
        error "User '$user_name' does not exist. Run: ./scripts/setup-aws-config.sh create-profile"
    fi
    
    # Get and attach policy
    local policy_arn=$(aws iam list-policies --query "Policies[?PolicyName=='$policy_name'].Arn" --output text 2>/dev/null)
    if [ -z "$policy_arn" ]; then
        error "Policy '$policy_name' not found. Run: ./scripts/setup-aws-config.sh create-profile"
    fi
    
    if aws iam attach-user-policy --user-name "$user_name" --policy-arn "$policy_arn"; then
        log "✅ Policy attached successfully!"
        info "Test with: export AWS_PROFILE=devops-training && ./scripts/setup-aws-config.sh test"
    else
        error "Failed to attach policy. Make sure you have IAM permissions."
    fi
}

main() {
    case "${1:-check}" in
        "check"|"test")
            check_aws_config
            test_permissions
            ;;
        "create-profile")
            create_devops_profile
            ;;
        "fix-permissions")
            fix_permissions
            ;;
        *)
            echo "Usage: $0 [check|test|create-profile|fix-permissions]"
            echo
            echo "Commands:"
            echo "  check            - Check AWS configuration and test permissions (default)"
            echo "  test             - Same as check"
            echo "  create-profile   - Create complete DevOps training AWS profile"
            echo "  fix-permissions  - Fix permissions for devops-training-user"
            echo
            echo "Examples:"
            echo "  $0                                    # Check current setup"
            echo "  $0 create-profile                     # Create new AWS profile"
            echo "  export AWS_PROFILE=devops-training    # Set profile"
            echo "  $0 test                               # Test permissions"
            ;;
    esac
}

main "$@"
