#!/bin/bash
# CoffeeShop Infrastructure Cleanup Script
# This script safely removes all AWS resources created by the DevOps training project

set -e

source "$(dirname "$0")/common/utils.sh"

AWS_REGION="us-west-2"
TERRAFORM_DIR="infrastructure"
ENVIRONMENT="dev"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

cleanup_terraform() {
    log "📦 Cleaning up Terraform-managed resources..."
    
    cd ${TERRAFORM_DIR}
    
    # Check if workspace exists
    if terraform workspace list | grep -q ${ENVIRONMENT}; then
        log "Selecting workspace: ${ENVIRONMENT}"
        terraform workspace select ${ENVIRONMENT}
        
        log "Running terraform destroy..."
        if terraform destroy -var-file="environments/${ENVIRONMENT}.tfvars" -auto-approve; then
            log "✅ Terraform destroy completed successfully"
        else
            warn "❌ Terraform destroy failed - some resources may need manual cleanup"
        fi
    else
        warn "No ${ENVIRONMENT} workspace found, skipping terraform destroy"
    fi
    
    cd ..
}

cleanup_ecr_repositories() {
    log "🗂️ Cleaning up ECR repositories..."
    
    local services=("web" "proxy" "barista" "kitchen" "counter" "product")
    
    for service in "${services[@]}"; do
        local repo_name="coffeeshop-${service}"
        if aws ecr describe-repositories --repository-names ${repo_name} --region ${AWS_REGION} 2>/dev/null; then
            log "Deleting ECR repository: ${repo_name}"
            if aws ecr delete-repository --repository-name ${repo_name} --region ${AWS_REGION} --force; then
                log "✅ ECR repository ${repo_name} deleted"
            else
                warn "❌ Failed to delete ECR repository: ${repo_name}"
            fi
        else
            log "ECR repository ${repo_name} not found (already deleted)"
        fi
    done
}

cleanup_backend_resources() {
    log "🗄️ Backend resources cleanup..."
    
    local bucket_name="coffeeshop-terraform-state-${ENVIRONMENT}-$(whoami)"
    local dynamodb_table="terraform-state-locks"
    
    echo -e "${YELLOW}⚠️  WARNING: This will delete Terraform state files!${NC}"
    echo -e "${YELLOW}⚠️  You will not be able to manage existing resources with Terraform after this.${NC}"
    echo ""
    read -p "Do you want to delete the Terraform state bucket and DynamoDB table? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Delete S3 bucket
        if aws s3 ls "s3://${bucket_name}" 2>/dev/null; then
            log "Deleting S3 bucket: ${bucket_name}"
            aws s3 rm "s3://${bucket_name}" --recursive 2>/dev/null || true
            aws s3 rb "s3://${bucket_name}" 2>/dev/null || true
            log "✅ S3 bucket deleted"
        fi
        
        # Delete DynamoDB table
        if aws dynamodb describe-table --table-name ${dynamodb_table} --region ${AWS_REGION} 2>/dev/null; then
            log "Deleting DynamoDB table: ${dynamodb_table}"
            aws dynamodb delete-table --table-name ${dynamodb_table} --region ${AWS_REGION} 2>/dev/null || true
            log "✅ DynamoDB table deleted"
        fi
    else
        log "Skipping backend resources cleanup"
    fi
}

cleanup_iam_resources() {
    log "👤 IAM resources cleanup..."
    
    echo -e "${YELLOW}⚠️  WARNING: This will delete the devops-training-user and policy!${NC}"
    echo -e "${YELLOW}⚠️  You will need to recreate them to run the deployment again.${NC}"
    echo ""
    read -p "Do you want to delete the devops-training-user and policy? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Get policy ARN
        local policy_arn=$(aws iam list-policies --query "Policies[?PolicyName=='DevOpsTrainingTerraformPolicy'].Arn" --output text 2>/dev/null)
        
        if [ -n "$policy_arn" ]; then
            # Detach policy from user
            log "Detaching policy from user..."
            aws iam detach-user-policy \
                --user-name devops-training-user \
                --policy-arn ${policy_arn} 2>/dev/null || true
            
            # Delete access keys
            log "Deleting access keys..."
            aws iam list-access-keys --user-name devops-training-user --query 'AccessKeyMetadata[*].AccessKeyId' --output text 2>/dev/null | \
            xargs -I {} aws iam delete-access-key --user-name devops-training-user --access-key-id {} 2>/dev/null || true
            
            # Delete user
            log "Deleting user..."
            aws iam delete-user --user-name devops-training-user 2>/dev/null || true
            
            # Delete policy
            log "Deleting policy..."
            aws iam delete-policy --policy-arn ${policy_arn} 2>/dev/null || true
            
            log "✅ IAM resources deleted"
        else
            warn "DevOpsTrainingTerraformPolicy not found"
        fi
    else
        log "Skipping IAM resources cleanup"
    fi
}

verify_cleanup() {
    log "🔍 Verifying cleanup..."
    
    # Check EC2 instances
    local ec2_instances=$(aws ec2 describe-instances --region ${AWS_REGION} --query 'Reservations[*].Instances[?State.Name!=`terminated` && Tags[?Key==`Name` && contains(Value, `coffeeshop`)]].[InstanceId,State.Name]' --output text 2>/dev/null)
    if [ -n "$ec2_instances" ]; then
        warn "⚠️  EC2 instances still running:"
        echo "$ec2_instances"
    else
        log "✅ No EC2 instances found"
    fi
    
    # Check RDS instances
    local rds_instances=$(aws rds describe-db-instances --region ${AWS_REGION} --query 'DBInstances[?contains(DBInstanceIdentifier, `coffeeshop`)].[DBInstanceIdentifier,DBInstanceStatus]' --output text 2>/dev/null)
    if [ -n "$rds_instances" ]; then
        warn "⚠️  RDS instances still exist:"
        echo "$rds_instances"
    else
        log "✅ No RDS instances found"
    fi
    
    # Check ElastiCache clusters
    local cache_clusters=$(aws elasticache describe-cache-clusters --region ${AWS_REGION} --query 'CacheClusters[?contains(CacheClusterId, `coffeeshop`)].[CacheClusterId,CacheClusterStatus]' --output text 2>/dev/null)
    if [ -n "$cache_clusters" ]; then
        warn "⚠️  ElastiCache clusters still exist:"
        echo "$cache_clusters"
    else
        log "✅ No ElastiCache clusters found"
    fi
    
    # Check Load Balancers
    local load_balancers=$(aws elbv2 describe-load-balancers --region ${AWS_REGION} --query 'LoadBalancers[?contains(LoadBalancerName, `coffeeshop`)].[LoadBalancerName,State.Code]' --output text 2>/dev/null)
    if [ -n "$load_balancers" ]; then
        warn "⚠️  Load balancers still exist:"
        echo "$load_balancers"
    else
        log "✅ No load balancers found"
    fi
    
    # Check VPCs
    local vpcs=$(aws ec2 describe-vpcs --region ${AWS_REGION} --query 'Vpcs[?Tags[?Key==`Name` && contains(Value, `coffeeshop`)]].[VpcId,Tags[?Key==`Name`].Value|[0]]' --output text 2>/dev/null)
    if [ -n "$vpcs" ]; then
        warn "⚠️  VPCs still exist:"
        echo "$vpcs"
    else
        log "✅ No VPCs found"
    fi
    
    # Check ECR repositories
    local ecr_repos=$(aws ecr describe-repositories --region ${AWS_REGION} --query 'repositories[?contains(repositoryName, `coffeeshop`)].repositoryName' --output text 2>/dev/null)
    if [ -n "$ecr_repos" ]; then
        warn "⚠️  ECR repositories still exist:"
        echo "$ecr_repos"
    else
        log "✅ No ECR repositories found"
    fi
}

manual_cleanup_resources() {
    log "🛠️ Manual cleanup of remaining resources..."
    
    # Terminate EC2 instances
    local instances=$(aws ec2 describe-instances --region ${AWS_REGION} --query 'Reservations[*].Instances[?State.Name!=`terminated` && Tags[?Key==`Name` && contains(Value, `coffeeshop`)]].InstanceId' --output text)
    if [ -n "$instances" ]; then
        log "Terminating EC2 instances: $instances"
        echo "$instances" | xargs -I {} aws ec2 terminate-instances --region ${AWS_REGION} --instance-ids {}
    fi
    
    # Delete RDS instances
    local rds_instances=$(aws rds describe-db-instances --region ${AWS_REGION} --query 'DBInstances[?contains(DBInstanceIdentifier, `coffeeshop`)].DBInstanceIdentifier' --output text)
    if [ -n "$rds_instances" ]; then
        log "Deleting RDS instances: $rds_instances"
        echo "$rds_instances" | xargs -I {} aws rds delete-db-instance --region ${AWS_REGION} --db-instance-identifier {} --skip-final-snapshot
    fi
    
    # Delete ElastiCache clusters
    local cache_clusters=$(aws elasticache describe-cache-clusters --region ${AWS_REGION} --query 'CacheClusters[?contains(CacheClusterId, `coffeeshop`)].CacheClusterId' --output text)
    if [ -n "$cache_clusters" ]; then
        log "Deleting ElastiCache clusters: $cache_clusters"
        echo "$cache_clusters" | xargs -I {} aws elasticache delete-cache-cluster --region ${AWS_REGION} --cache-cluster-id {}
    fi
    
    # Delete Load Balancers
    local load_balancers=$(aws elbv2 describe-load-balancers --region ${AWS_REGION} --query 'LoadBalancers[?contains(LoadBalancerName, `coffeeshop`)].LoadBalancerArn' --output text)
    if [ -n "$load_balancers" ]; then
        log "Deleting Load Balancers: $load_balancers"
        echo "$load_balancers" | xargs -I {} aws elbv2 delete-load-balancer --region ${AWS_REGION} --load-balancer-arn {}
    fi
    
    # Wait a bit for resources to be deleted
    log "Waiting 30 seconds for resources to be deleted..."
    sleep 30
    
    # Delete NAT Gateways
    local nat_gateways=$(aws ec2 describe-nat-gateways --region ${AWS_REGION} --query 'NatGateways[?State==`available` && Tags[?Key==`Name` && contains(Value, `coffeeshop`)]].NatGatewayId' --output text)
    if [ -n "$nat_gateways" ]; then
        log "Deleting NAT Gateways: $nat_gateways"
        echo "$nat_gateways" | xargs -I {} aws ec2 delete-nat-gateway --region ${AWS_REGION} --nat-gateway-id {}
    fi
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "CoffeeShop Infrastructure Cleanup Script"
    echo ""
    echo "Options:"
    echo "  --terraform-only    Only run terraform destroy"
    echo "  --manual-only       Only run manual cleanup (skip terraform)"
    echo "  --verify-only       Only verify what resources exist"
    echo "  --force             Skip confirmation prompts"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                   # Full cleanup with confirmations"
    echo "  $0 --terraform-only  # Only terraform destroy"
    echo "  $0 --verify-only     # Check what resources exist"
    echo ""
}

main() {
    local terraform_only=false
    local manual_only=false
    local verify_only=false
    local force=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --terraform-only)
                terraform_only=true
                shift
                ;;
            --manual-only)
                manual_only=true
                shift
                ;;
            --verify-only)
                verify_only=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown parameter: $1"
                ;;
        esac
    done
    
    # Check prerequisites
    if [ "$verify_only" = false ]; then
        if ! command_exists aws; then
            error "AWS CLI is not installed"
        fi
        
        if ! command_exists terraform && [ "$manual_only" = false ]; then
            error "Terraform is not installed"
        fi
        
        if ! aws sts get-caller-identity &> /dev/null; then
            error "AWS credentials not configured or profile not set"
        fi
    fi
    
    echo -e "${BLUE}🧹 CoffeeShop Infrastructure Cleanup${NC}"
    echo -e "${BLUE}=====================================${NC}"
    
    if [ "$verify_only" = true ]; then
        verify_cleanup
        exit 0
    fi
    
    if [ "$force" = false ]; then
        echo -e "${YELLOW}⚠️  This will delete AWS resources and may incur costs for early termination.${NC}"
        echo -e "${YELLOW}⚠️  Make sure you have backups of any important data.${NC}"
        echo ""
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Set AWS profile
    export AWS_PROFILE=devops-training
    log "Using AWS profile: $AWS_PROFILE"
    
    # Run cleanup steps
    if [ "$manual_only" = false ]; then
        cleanup_terraform
    fi
    
    if [ "$terraform_only" = false ]; then
        cleanup_ecr_repositories
        manual_cleanup_resources
        cleanup_backend_resources
        cleanup_iam_resources
    fi
    
    # Verify cleanup
    verify_cleanup
    
    echo ""
    echo -e "${GREEN}✅ Cleanup completed!${NC}"
    echo -e "${GREEN}💰 Check your AWS billing dashboard to confirm resources are deleted.${NC}"
    echo ""
}

main "$@"
