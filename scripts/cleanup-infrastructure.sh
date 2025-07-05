#!/bin/bash
# CoffeeShop Infrastructure Cleanup Script
# This script safely removes all AWS resources created by the DevOps training project
# Unified script with comprehensive resource cleanup and dependency management

set -e

source "$(dirname "$0")/common/utils.sh"

AWS_REGION="us-west-2"
TERRAFORM_DIR="infrastructure"
ENVIRONMENT="dev"  # Default, will be overridden by argument parsing
SCRIPT_DIR="$(dirname "$0")"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variable to store all tagged resources
ALL_TAGGED_RESOURCES=""

# Function to get all resources tagged with Environment
get_all_tagged_resources() {
    if [ -z "$ALL_TAGGED_RESOURCES" ]; then
        ALL_TAGGED_RESOURCES=$(aws resourcegroupstaggingapi get-resources \
            --tag-filters "Key=Environment,Values=${ENVIRONMENT}" \
            --query 'ResourceTagMappingList[].ResourceARN' \
            --output text --region ${AWS_REGION} 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' || echo "")
    fi
    echo "$ALL_TAGGED_RESOURCES"
}

# Function to extract resource IDs from ARNs
extract_resource_ids() {
    local resource_type="$1"
    local arns="$2"
    
    case "$resource_type" in
        "ec2-instance")
            echo "$arns" | grep -o 'instance/i-[a-zA-Z0-9]*' | cut -d'/' -f2 | grep -v '^[[:space:]]*$' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//' || echo ""
            ;;
        "nat-gateway")
            echo "$arns" | grep -o 'natgateway/nat-[a-zA-Z0-9]*' | cut -d'/' -f2 | grep -v '^[[:space:]]*$' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//' || echo ""
            ;;
        "security-group")
            echo "$arns" | grep -o 'security-group/sg-[a-zA-Z0-9]*' | cut -d'/' -f2 | grep -v '^[[:space:]]*$' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//' || echo ""
            ;;
        "subnet")
            echo "$arns" | grep -o 'subnet/subnet-[a-zA-Z0-9]*' | cut -d'/' -f2 | grep -v '^[[:space:]]*$' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//' || echo ""
            ;;
        "vpc")
            echo "$arns" | grep -o 'vpc/vpc-[a-zA-Z0-9]*' | cut -d'/' -f2 | grep -v '^[[:space:]]*$' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//' || echo ""
            ;;
        "rds-parameter-group")
            echo "$arns" | grep -o 'pg:[^[:space:]]*' | cut -d':' -f2 | grep -v '^[[:space:]]*$' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//' || echo ""
            ;;
        "rds-subnet-group")
            echo "$arns" | grep -o 'subgrp:[^[:space:]]*' | cut -d':' -f2 | grep -v '^[[:space:]]*$' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//' || echo ""
            ;;
        "kms-key")
            echo "$arns" | grep -o 'key/[a-zA-Z0-9-]*' | cut -d'/' -f2 | grep -v '^[[:space:]]*$' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//' || echo ""
            ;;
        "elasticache-snapshot")
            echo "$arns" | grep -o 'arn:aws:elasticache:[^:]*:[^:]*:snapshot:[^[:space:]]*' | sed 's/.*:snapshot://' | grep -v '^[[:space:]]*$' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//' || echo ""
            ;;
    esac
}

# Function to wait for resource deletion with timeout
wait_for_resource_deletion() {
    local resource_type="$1"
    local resource_id="$2"
    local max_attempts=30
    local attempt=0
    
    log "Waiting for ${resource_type} ${resource_id} to be deleted..."
    
    while [ $attempt -lt $max_attempts ]; do
        case "$resource_type" in
            "nat-gateway")
                local state=$(aws ec2 describe-nat-gateways --nat-gateway-ids "$resource_id" --region ${AWS_REGION} --query 'NatGateways[0].State' --output text 2>/dev/null || echo "deleted")
                if [ "$state" = "deleted" ] || [ "$state" = "None" ]; then
                    log "✅ NAT Gateway $resource_id deleted"
                    return 0
                fi
                ;;
            "instance")
                local state=$(aws ec2 describe-instances --instance-ids "$resource_id" --region ${AWS_REGION} --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "terminated")
                if [ "$state" = "terminated" ] || [ "$state" = "None" ]; then
                    log "✅ Instance $resource_id terminated"
                    return 0
                fi
                ;;
        esac
        
        sleep 10
        ((attempt++))
    done
    
    warn "⚠️  Timeout waiting for ${resource_type} ${resource_id} to be deleted"
    return 1
}

# Function to show current resources
show_current_resources() {
    log "🔍 Checking current resources with Environment=${ENVIRONMENT} tag:"
    
    # Clear cache to get fresh data
    ALL_TAGGED_RESOURCES=""
    local tagged_resources=$(get_all_tagged_resources)
    
    if [ -n "$tagged_resources" ]; then
        echo ""
        echo -e "${BLUE}Current Resources:${NC}"
        echo "$tagged_resources" | tr ' ' '\n' | while read -r arn; do
            if [ -n "$arn" ] && [[ "$arn" =~ ^arn:aws: ]]; then
                case "$arn" in
                    *":snapshot:"*)
                        local resource_type="elasticache-snapshot"
                        local resource_id=$(echo "$arn" | sed 's/.*:snapshot://')
                        ;;
                    *)
                        local resource_type=$(echo "$arn" | cut -d':' -f6 | cut -d'/' -f1)
                        local resource_id=$(echo "$arn" | cut -d':' -f6 | cut -d'/' -f2)
                        ;;
                esac
                echo "  $resource_type: $resource_id"
            fi
        done
        
        echo ""
        echo -e "${BLUE}Resource Summary:${NC}"
        echo "  EC2 Instances: $(extract_resource_ids "ec2-instance" "$tagged_resources" | wc -w)"
        echo "  NAT Gateways: $(extract_resource_ids "nat-gateway" "$tagged_resources" | wc -w)"
        echo "  Security Groups: $(extract_resource_ids "security-group" "$tagged_resources" | wc -w)"
        echo "  Subnets: $(extract_resource_ids "subnet" "$tagged_resources" | wc -w)"
        echo "  VPCs: $(extract_resource_ids "vpc" "$tagged_resources" | wc -w)"
        echo "  RDS Parameter Groups: $(extract_resource_ids "rds-parameter-group" "$tagged_resources" | wc -w)"
        echo "  RDS Subnet Groups: $(extract_resource_ids "rds-subnet-group" "$tagged_resources" | wc -w)"
        echo "  KMS Keys: $(extract_resource_ids "kms-key" "$tagged_resources" | wc -w)"
        echo "  ElastiCache Snapshots: $(extract_resource_ids "elasticache-snapshot" "$tagged_resources" | wc -w)"
    else
        log "No resources found with Environment=${ENVIRONMENT} tag"
    fi
}

cleanup_kubernetes_resources() {
    if [ "$ENVIRONMENT" = "prod" ]; then
        log "🐙 Cleaning up Kubernetes resources from EKS cluster..."
        
        # Check if kubectl is configured and EKS cluster exists
        if command_exists kubectl && aws eks describe-cluster --name coffeeshop-prod --region ${AWS_REGION} &> /dev/null; then
            log "Configuring kubectl for EKS cluster..."
            if aws eks update-kubeconfig --region ${AWS_REGION} --name coffeeshop-prod &> /dev/null; then
                log "Removing CoffeeShop application from Kubernetes..."
                
                # Use the deploy-k8s.sh cleanup if available
                if [ -f "${SCRIPT_DIR}/deploy-k8s.sh" ]; then
                    log "Using deploy-k8s.sh cleanup..."
                    "${SCRIPT_DIR}/deploy-k8s.sh" cleanup || warn "Some Kubernetes resources may not have been cleaned up"
                else
                    # Manual cleanup
                    log "Manually cleaning up Kubernetes namespaces..."
                    kubectl delete namespace coffeeshop --ignore-not-found=true
                    kubectl delete namespace monitoring --ignore-not-found=true
                fi
                
                log "✅ Kubernetes resources cleaned up"
            else
                warn "Failed to configure kubectl for EKS cluster"
            fi
        else
            log "EKS cluster not found or kubectl not available, skipping Kubernetes cleanup"
        fi
    else
        log "Environment is not prod, skipping Kubernetes cleanup"
    fi
}

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

cleanup_elasticache_resources() {
    log "🗄️ Cleaning up ElastiCache resources..."
    
    # Clear cache to get fresh data
    ALL_TAGGED_RESOURCES=""
    local tagged_resources=$(get_all_tagged_resources)
    
    # Delete ElastiCache snapshots first
    local snapshots=$(extract_resource_ids "elasticache-snapshot" "$tagged_resources")
    if [ -n "$snapshots" ]; then
        log "Deleting ElastiCache snapshots: $snapshots"
        for snapshot in $snapshots; do
            if [ -n "$snapshot" ]; then
                # Check if snapshot exists before trying to delete
                if aws elasticache describe-snapshots --snapshot-name "$snapshot" --region ${AWS_REGION} >/dev/null 2>&1; then
                    aws elasticache delete-snapshot --snapshot-name "$snapshot" --region ${AWS_REGION} || warn "Failed to delete snapshot $snapshot"
                else
                    log "Snapshot $snapshot not found (already deleted)"
                fi
            fi
        done
    fi
    
    # Delete ElastiCache clusters by name pattern
    local cache_clusters=$(aws elasticache describe-cache-clusters --region ${AWS_REGION} --query 'CacheClusters[?contains(CacheClusterId, `coffeeshop`)].CacheClusterId' --output text)
    if [ -n "$cache_clusters" ]; then
        log "Deleting ElastiCache clusters: $cache_clusters"
        echo "$cache_clusters" | xargs -I {} aws elasticache delete-cache-cluster --region ${AWS_REGION} --cache-cluster-id {} || true
    fi
}

cleanup_ec2_instances() {
    log "🖥️ Cleaning up EC2 instances..."
    
    local tagged_resources=$(get_all_tagged_resources)
    
    # Get instances by name pattern and by tags
    local instances_by_name=$(aws ec2 describe-instances --region ${AWS_REGION} --query 'Reservations[*].Instances[?State.Name!=`terminated` && Tags[?Key==`Name` && contains(Value, `coffeeshop`)]].InstanceId' --output text)
    local instances_by_tag=$(extract_resource_ids "ec2-instance" "$tagged_resources")
    
    local all_instances=$(echo "$instances_by_name $instances_by_tag" | tr ' ' '\n' | grep -v '^[[:space:]]*$' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    
    if [ -n "$all_instances" ]; then
        log "Terminating EC2 instances: $all_instances"
        # Terminate instances one by one to avoid malformed ID issues
        for instance in $all_instances; do
            if [ -n "$instance" ]; then
                aws ec2 terminate-instances --region ${AWS_REGION} --instance-ids "$instance" || warn "Failed to terminate instance $instance"
            fi
        done
        
        # Wait for instances to terminate
        log "Waiting for instances to terminate..."
        for instance in $all_instances; do
            if [ -n "$instance" ]; then
                wait_for_resource_deletion "instance" "$instance" &
            fi
        done
        wait
    else
        log "No EC2 instances found"
    fi
}

cleanup_nat_gateways() {
    log "🌐 Cleaning up NAT gateways..."
    
    local tagged_resources=$(get_all_tagged_resources)
    local nat_gateways=$(extract_resource_ids "nat-gateway" "$tagged_resources")
    
    if [ -n "$nat_gateways" ]; then
        log "Deleting NAT gateways: $nat_gateways"
        for nat_gw in $nat_gateways; do
            if [ -n "$nat_gw" ]; then
                # Check if NAT gateway exists before trying to delete
                if aws ec2 describe-nat-gateways --nat-gateway-ids "$nat_gw" --region ${AWS_REGION} >/dev/null 2>&1; then
                    aws ec2 delete-nat-gateway --nat-gateway-id "$nat_gw" --region ${AWS_REGION} || warn "Failed to delete NAT gateway $nat_gw"
                else
                    log "NAT gateway $nat_gw not found (already deleted)"
                fi
            fi
        done
        
        # Wait for NAT gateways to be deleted
        for nat_gw in $nat_gateways; do
            if [ -n "$nat_gw" ]; then
                wait_for_resource_deletion "nat-gateway" "$nat_gw" &
            fi
        done
        wait
    else
        log "No NAT gateways found"
    fi
}

cleanup_rds_resources() {
    log "🗄️ Cleaning up RDS resources..."
    
    local tagged_resources=$(get_all_tagged_resources)
    
    # Delete RDS instances by name pattern
    local rds_instances=$(aws rds describe-db-instances --region ${AWS_REGION} --query 'DBInstances[?contains(DBInstanceIdentifier, `coffeeshop`)].DBInstanceIdentifier' --output text)
    if [ -n "$rds_instances" ]; then
        log "Disabling deletion protection for RDS instances: $rds_instances"
        echo "$rds_instances" | xargs -I {} aws rds modify-db-instance --region ${AWS_REGION} --db-instance-identifier {} --no-deletion-protection --apply-immediately || true
        
        sleep 10
        
        log "Deleting RDS instances: $rds_instances"
        echo "$rds_instances" | xargs -I {} aws rds delete-db-instance --region ${AWS_REGION} --db-instance-identifier {} --skip-final-snapshot || true
    fi
    
    # Delete RDS parameter groups
    local param_groups=$(extract_resource_ids "rds-parameter-group" "$tagged_resources")
    if [ -n "$param_groups" ]; then
        log "Deleting RDS parameter groups: $param_groups"
        echo "$param_groups" | xargs -I {} aws rds delete-db-parameter-group --db-parameter-group-name {} --region ${AWS_REGION} || true
    fi
    
    # Delete RDS subnet groups
    local subnet_groups=$(extract_resource_ids "rds-subnet-group" "$tagged_resources")
    if [ -n "$subnet_groups" ]; then
        log "Deleting RDS subnet groups: $subnet_groups"
        echo "$subnet_groups" | xargs -I {} aws rds delete-db-subnet-group --db-subnet-group-name {} --region ${AWS_REGION} || true
    fi
}

cleanup_load_balancers() {
    log "⚖️ Cleaning up Load Balancers..."
    
    local load_balancers=$(aws elbv2 describe-load-balancers --region ${AWS_REGION} --query 'LoadBalancers[?contains(LoadBalancerName, `coffeeshop`)].LoadBalancerArn' --output text)
    if [ -n "$load_balancers" ]; then
        log "Deleting Load Balancers: $load_balancers"
        echo "$load_balancers" | xargs -I {} aws elbv2 delete-load-balancer --region ${AWS_REGION} --load-balancer-arn {} || true
    else
        log "No Load Balancers found"
    fi
}

cleanup_security_groups() {
    log "🔒 Cleaning up Security Groups..."
    
    local tagged_resources=$(get_all_tagged_resources)
    local security_groups=$(extract_resource_ids "security-group" "$tagged_resources")
    
    if [ -n "$security_groups" ]; then
        log "Deleting Security Groups: $security_groups"
        local max_attempts=5
        local attempt=0
        
        while [ $attempt -lt $max_attempts ] && [ -n "$security_groups" ]; do
            log "Attempt $((attempt + 1)) to delete security groups..."
            local failed_sgs=""
            
            for sg in $security_groups; do
                # Skip default security groups
                local sg_name=$(aws ec2 describe-security-groups --group-ids "$sg" --region ${AWS_REGION} --query 'SecurityGroups[0].GroupName' --output text 2>/dev/null || echo "")
                if [ "$sg_name" = "default" ]; then
                    log "Skipping default security group: $sg"
                    continue
                fi
                
                # Check if security group exists before trying to delete
                if aws ec2 describe-security-groups --group-ids "$sg" --region ${AWS_REGION} >/dev/null 2>&1; then
                    if ! aws ec2 delete-security-group --group-id "$sg" --region ${AWS_REGION} 2>/dev/null; then
                        failed_sgs="$failed_sgs $sg"
                        warn "Failed to delete security group $sg (will retry)"
                    else
                        log "✅ Security group $sg deleted"
                    fi
                else
                    log "Security group $sg not found (already deleted)"
                fi
            done
            
            security_groups=$(echo "$failed_sgs" | xargs)
            ((attempt++))
            
            if [ -n "$security_groups" ] && [ $attempt -lt $max_attempts ]; then
                log "Waiting 30 seconds before retrying..."
                sleep 30
            fi
        done
        
        if [ -n "$security_groups" ]; then
            warn "⚠️  Could not delete some security groups: $security_groups"
        fi
    else
        log "No security groups found"
    fi
}

cleanup_network_resources() {
    log "🌐 Cleaning up Network resources..."
    
    local tagged_resources=$(get_all_tagged_resources)
    local vpc_ids=$(extract_resource_ids "vpc" "$tagged_resources")
    
    # Clean up Elastic IP addresses first
    log "Cleaning up Elastic IP addresses..."
    local elastic_ips=$(aws ec2 describe-addresses --region ${AWS_REGION} --query 'Addresses[?Tags[?Key==`Name` && contains(Value, `coffeeshop`)]].AllocationId' --output text 2>/dev/null || echo "")
    
    # Also find untagged EIPs associated with NAT gateways or instances with coffeeshop in the name
    local nat_eips=$(aws ec2 describe-addresses --region ${AWS_REGION} --query 'Addresses[?AssociationId && contains(InstanceId, `coffeeshop`)].AllocationId' --output text 2>/dev/null || echo "")
    
    local all_eips=$(echo "$elastic_ips $nat_eips" | tr ' ' '\n' | grep -v '^[[:space:]]*$' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    
    if [ -n "$all_eips" ]; then
        log "Releasing Elastic IP addresses: $all_eips"
        for eip in $all_eips; do
            if [ -n "$eip" ]; then
                aws ec2 release-address --allocation-id "$eip" --region ${AWS_REGION} || warn "Failed to release EIP $eip"
            fi
        done
    else
        log "No Elastic IP addresses found"
    fi
    
    if [ -n "$vpc_ids" ]; then
        # Delete Internet Gateways
        for vpc in $vpc_ids; do
            local igws=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --region ${AWS_REGION} --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null || echo "")
            if [ -n "$igws" ]; then
                log "Detaching and deleting Internet Gateways for VPC $vpc: $igws"
                for igw in $igws; do
                    aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc" --region ${AWS_REGION} || true
                    aws ec2 delete-internet-gateway --internet-gateway-id "$igw" --region ${AWS_REGION} || true
                done
            fi
        done
        
        # Delete Route Tables (non-main ones)
        for vpc in $vpc_ids; do
            local route_tables=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --region ${AWS_REGION} --query 'RouteTables[?!Main].RouteTableId' --output text 2>/dev/null || echo "")
            if [ -n "$route_tables" ]; then
                log "Deleting Route Tables for VPC $vpc: $route_tables"
                echo "$route_tables" | xargs -I {} aws ec2 delete-route-table --route-table-id {} --region ${AWS_REGION} || true
            fi
        done
        
        # Delete Subnets
        local subnets=$(extract_resource_ids "subnet" "$tagged_resources")
        if [ -n "$subnets" ]; then
            log "Deleting Subnets: $subnets"
            echo "$subnets" | xargs -I {} aws ec2 delete-subnet --subnet-id {} --region ${AWS_REGION} || true
        fi
        
        # Delete VPCs
        for vpc in $vpc_ids; do
            # Skip default VPC
            local is_default=$(aws ec2 describe-vpcs --vpc-ids "$vpc" --region ${AWS_REGION} --query 'Vpcs[0].IsDefault' --output text 2>/dev/null || echo "false")
            if [ "$is_default" = "true" ]; then
                log "Skipping default VPC: $vpc"
                continue
            fi
            
            log "Deleting VPC: $vpc"
            aws ec2 delete-vpc --vpc-id "$vpc" --region ${AWS_REGION} || true
        done
    else
        log "No VPCs found"
    fi
}

cleanup_kms_keys() {
    log "🔐 Cleaning up KMS keys..."
    
    local tagged_resources=$(get_all_tagged_resources)
    local kms_keys=$(extract_resource_ids "kms-key" "$tagged_resources")
    
    if [ -n "$kms_keys" ]; then
        log "Scheduling KMS key deletion: $kms_keys"
        for key in $kms_keys; do
            aws kms schedule-key-deletion --key-id "$key" --pending-window-in-days 7 --region ${AWS_REGION} || warn "Failed to schedule key deletion $key"
        done
    else
        log "No KMS keys found"
    fi
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

cleanup_route53_resources() {
    log "🌐 Cleaning up Route53 resources..."
    
    # Check if jq is available (needed for Route53 record manipulation)
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Skipping Route53 cleanup (manual cleanup may be required)"
        return
    fi
    
    # Find hosted zones with coffeeshop in the name
    local hosted_zones=$(aws route53 list-hosted-zones --query 'HostedZones[?contains(Name, `coffeeshop`)].Id' --output text 2>/dev/null || echo "")
    
    if [ -n "$hosted_zones" ]; then
        log "Found Route53 hosted zones: $hosted_zones"
        for zone_id in $hosted_zones; do
            # Clean up the zone ID (remove /hostedzone/ prefix)
            zone_id=$(echo "$zone_id" | sed 's|/hostedzone/||')
            
            if [ -n "$zone_id" ]; then
                log "Deleting Route53 hosted zone: $zone_id"
                
                # First, delete all records except NS and SOA
                local records=$(aws route53 list-resource-record-sets --hosted-zone-id "$zone_id" --query 'ResourceRecordSets[?Type != `NS` && Type != `SOA`]' --output json 2>/dev/null || echo "[]")
                
                if [ "$records" != "[]" ]; then
                    log "Deleting Route53 records in hosted zone $zone_id"
                    # Create a changeset to delete all records
                    local changeset=$(echo "$records" | jq '{Changes: [.[] | {Action: "DELETE", ResourceRecordSet: .}]}')
                    aws route53 change-resource-record-sets --hosted-zone-id "$zone_id" --change-batch "$changeset" || warn "Failed to delete records in hosted zone $zone_id"
                fi
                
                # Then delete the hosted zone
                aws route53 delete-hosted-zone --id "$zone_id" || warn "Failed to delete hosted zone $zone_id"
            fi
        done
    else
        log "No Route53 hosted zones found"
    fi
}

# Unified manual cleanup function that handles all resources in proper order
comprehensive_cleanup_resources() {
    log "🛠️ Starting comprehensive cleanup of tagged resources..."
    
    # Step 1: Clean up application-level resources first
    cleanup_elasticache_resources
    cleanup_ec2_instances
    cleanup_load_balancers
    
    # Step 2: Clean up NAT gateways (they prevent subnet deletion)
    cleanup_nat_gateways
    
    # Step 3: Clean up RDS resources
    cleanup_rds_resources
    
    # Step 4: Wait for previous resources to be deleted
    log "Waiting 60 seconds for resources to be deleted..."
    sleep 60
    
    # Step 5: Clean up network resources (order is important)
    cleanup_security_groups
    cleanup_network_resources
    
    # Step 6: Clean up remaining resources
    cleanup_kms_keys
    
    log "✅ Comprehensive cleanup completed"
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
    
    # Check Elastic IP addresses
    local elastic_ips=$(aws ec2 describe-addresses --region ${AWS_REGION} --query 'Addresses[?Tags[?Key==`Name` && contains(Value, `coffeeshop`)]].PublicIp' --output text 2>/dev/null)
    if [ -n "$elastic_ips" ]; then
        warn "⚠️  Elastic IP addresses still exist:"
        echo "$elastic_ips"
    else
        log "✅ No Elastic IP addresses found"
    fi
    
    # Check Route53 hosted zones
    local hosted_zones=$(aws route53 list-hosted-zones --query 'HostedZones[?contains(Name, `coffeeshop`)].Name' --output text 2>/dev/null)
    if [ -n "$hosted_zones" ]; then
        warn "⚠️  Route53 hosted zones still exist:"
        echo "$hosted_zones"
    else
        log "✅ No Route53 hosted zones found"
    fi
}

usage() {
    echo "Usage: $0 [OPTIONS] [ENVIRONMENT]"
    echo ""
    echo "CoffeeShop Infrastructure Cleanup Script"
    echo ""
    echo "Arguments:"
    echo "  ENVIRONMENT         Target environment (dev|staging|prod) [default: dev]"
    echo ""
    echo "Options:"
    echo "  --terraform-only    Only run terraform destroy"
    echo "  --manual-only       Only run manual cleanup (skip terraform)"
    echo "  --verify-only       Only verify what resources exist"
    echo "  --dry-run           Show what would be deleted without actually deleting"
    echo "  --force             Skip confirmation prompts"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                   # Full cleanup of dev environment"
    echo "  $0 prod              # Full cleanup of prod environment (EKS)"
    echo "  $0 --terraform-only prod  # Only terraform destroy for prod"
    echo "  $0 --verify-only     # Check what resources exist"
    echo "  $0 --dry-run prod    # Show what would be deleted in prod"
    echo ""
}

main() {
    local terraform_only=false
    local manual_only=false
    local verify_only=false
    local dry_run=false
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
            --dry-run)
                dry_run=true
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
            dev|staging|prod)
                ENVIRONMENT="$1"
                shift
                ;;
            *)
                error "Unknown parameter: $1"
                ;;
        esac
    done
    
    # Validate environment
    if [[ ! "${ENVIRONMENT}" =~ ^(dev|staging|prod)$ ]]; then
        error "Invalid environment: ${ENVIRONMENT}. Must be one of: dev, staging, prod"
    fi
    
    log "Cleaning up environment: ${ENVIRONMENT}"
    
    # Check prerequisites
    if [ "$verify_only" = false ] && [ "$dry_run" = false ]; then
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
    
    if [ "$verify_only" = true ] || [ "$dry_run" = true ]; then
        show_current_resources
        if [ "$dry_run" = true ]; then
            echo ""
            echo -e "${YELLOW}🔍 DRY RUN: The following actions would be performed:${NC}"
            echo ""
            echo "1. Kubernetes resources cleanup (if prod environment)"
            echo "2. Terraform destroy (if not --manual-only)"
            echo "3. ECR repositories cleanup (if not --terraform-only)"
            echo "4. Route53 hosted zones cleanup (if not --terraform-only)"
            echo "5. ElastiCache resources cleanup (if not --terraform-only)"
            echo "6. EC2 instances termination (if not --terraform-only)"
            echo "7. Load balancers cleanup (if not --terraform-only)"
            echo "8. NAT gateways cleanup (if not --terraform-only)"
            echo "9. RDS resources cleanup (if not --terraform-only)"
            echo "10. Security groups cleanup (if not --terraform-only)"
            echo "11. Network resources cleanup (Elastic IPs, VPCs, etc.) (if not --terraform-only)"
            echo "12. KMS keys scheduling for deletion (if not --terraform-only)"
            echo "13. Backend resources cleanup (S3, DynamoDB) (if not --terraform-only)"
            echo "14. IAM resources cleanup (if not --terraform-only)"
            echo ""
            echo -e "${GREEN}💡 Use --force to skip confirmation prompts${NC}"
        fi
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
    
    # Setup logging
    local log_file="cleanup-$(date +%Y%m%d-%H%M%S).log"
    log "Logging cleanup operations to: $log_file"
    
    # Log cleanup start
    {
        echo "CoffeeShop Infrastructure Cleanup Log"
        echo "======================================"
        echo "Start time: $(date)"
        echo "Environment: $ENVIRONMENT"
        echo "Options: terraform_only=$terraform_only, manual_only=$manual_only, force=$force"
        echo "User: $(whoami)"
        echo "AWS Profile: $AWS_PROFILE"
        echo ""
    } >> "$log_file"
    
    # Run cleanup steps in the correct order
    echo -e "${BLUE}🚀 Starting cleanup process...${NC}"
    echo -e "${BLUE}==============================${NC}"
    
    # 1. First cleanup Kubernetes resources (before destroying EKS cluster)
    if [ "$terraform_only" = false ]; then
        echo -e "${BLUE}[1/6] Cleaning up Kubernetes resources...${NC}"
        cleanup_kubernetes_resources
    fi
    
    # 2. Then cleanup Terraform-managed infrastructure
    if [ "$manual_only" = false ]; then
        echo -e "${BLUE}[2/6] Running Terraform destroy...${NC}"
        cleanup_terraform
    fi
    
    # 3. Finally cleanup any remaining manual resources
    if [ "$terraform_only" = false ]; then
        echo -e "${BLUE}[3/6] Cleaning up ECR repositories...${NC}"
        cleanup_ecr_repositories
        echo -e "${BLUE}[4/6] Cleaning up Route53 resources...${NC}"
        cleanup_route53_resources
        echo -e "${BLUE}[5/6] Cleaning up AWS resources...${NC}"
        comprehensive_cleanup_resources
        echo -e "${BLUE}[6/6] Cleaning up backend and IAM resources...${NC}"
        cleanup_backend_resources
        cleanup_iam_resources
    fi
    
    # Verify cleanup
    echo ""
    echo -e "${BLUE}🔍 Final Verification${NC}"
    echo -e "${BLUE}===================${NC}"
    verify_cleanup
    
    echo ""
    echo -e "${GREEN}✅ Cleanup completed successfully!${NC}"
    echo -e "${GREEN}💰 Check your AWS billing dashboard to confirm resources are deleted.${NC}"
    echo -e "${GREEN}📊 Consider running --verify-only to double-check no resources remain.${NC}"
    echo -e "${GREEN}📋 Cleanup log saved to: $log_file${NC}"
    echo ""
    
    # Log cleanup completion
    {
        echo ""
        echo "End time: $(date)"
        echo "Cleanup completed successfully"
    } >> "$log_file"
}

main "$@"
