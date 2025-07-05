#!/bin/bash
# Quick resource verification script

set -e

AWS_REGION="us-west-2"
ENVIRONMENT="prod"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Set AWS profile
export AWS_PROFILE=devops-training
log "Using AWS profile: $AWS_PROFILE"

echo -e "${BLUE}🔍 AWS Resources Verification${NC}"
echo -e "${BLUE}============================${NC}"

# Check resources using ResourceGroupsTaggingAPI
echo ""
log "Resources tagged with Environment=$ENVIRONMENT:"
aws resourcegroupstaggingapi get-resources \
    --tag-filters "Key=Environment,Values=$ENVIRONMENT" \
    --query 'ResourceTagMappingList[].ResourceARN' \
    --output table --region $AWS_REGION 2>/dev/null || warn "No tagged resources found"

echo ""
log "Extracting resource IDs for easy cleanup:"

# Get all tagged resources
TAGGED_RESOURCES=$(aws resourcegroupstaggingapi get-resources \
    --tag-filters "Key=Environment,Values=$ENVIRONMENT" \
    --query 'ResourceTagMappingList[].ResourceARN' \
    --output text --region $AWS_REGION 2>/dev/null || echo "")

if [ -n "$TAGGED_RESOURCES" ]; then
    echo ""
    echo -e "${BLUE}EC2 Instances:${NC}"
    echo "$TAGGED_RESOURCES" | grep -o 'instance/i-[a-zA-Z0-9]*' | cut -d'/' -f2 | sort -u || echo "None found"
    
    echo ""
    echo -e "${BLUE}NAT Gateways:${NC}"
    echo "$TAGGED_RESOURCES" | grep -o 'natgateway/nat-[a-zA-Z0-9]*' | cut -d'/' -f2 | sort -u || echo "None found"
    
    echo ""
    echo -e "${BLUE}Security Groups:${NC}"
    echo "$TAGGED_RESOURCES" | grep -o 'security-group/sg-[a-zA-Z0-9]*' | cut -d'/' -f2 | sort -u || echo "None found"
    
    echo ""
    echo -e "${BLUE}Subnets:${NC}"
    echo "$TAGGED_RESOURCES" | grep -o 'subnet/subnet-[a-zA-Z0-9]*' | cut -d'/' -f2 | sort -u || echo "None found"
    
    echo ""
    echo -e "${BLUE}VPCs:${NC}"
    echo "$TAGGED_RESOURCES" | grep -o 'vpc/vpc-[a-zA-Z0-9]*' | cut -d'/' -f2 | sort -u || echo "None found"
    
    echo ""
    echo -e "${BLUE}RDS Parameter Groups:${NC}"
    echo "$TAGGED_RESOURCES" | grep -o 'pg:[^[:space:]]*' | cut -d':' -f2 | sort -u || echo "None found"
    
    echo ""
    echo -e "${BLUE}RDS Subnet Groups:${NC}"
    echo "$TAGGED_RESOURCES" | grep -o 'subgrp:[^[:space:]]*' | cut -d':' -f2 | sort -u || echo "None found"
    
    echo ""
    echo -e "${BLUE}KMS Keys:${NC}"
    echo "$TAGGED_RESOURCES" | grep -o 'key/[a-zA-Z0-9-]*' | cut -d'/' -f2 | sort -u || echo "None found"
    
    echo ""
    echo -e "${BLUE}ElastiCache Snapshots:${NC}"
    echo "$TAGGED_RESOURCES" | grep -o 'snapshot:[^[:space:]]*' | cut -d':' -f2 | sort -u || echo "None found"
    
    echo ""
    echo -e "${YELLOW}Quick cleanup commands:${NC}"
    
    # EC2 instances
    INSTANCES=$(echo "$TAGGED_RESOURCES" | grep -o 'instance/i-[a-zA-Z0-9]*' | cut -d'/' -f2 | sort -u | tr '\n' ' ')
    if [ -n "$INSTANCES" ]; then
        echo -e "${BLUE}Terminate instances:${NC}"
        echo "aws ec2 terminate-instances --instance-ids $INSTANCES --region $AWS_REGION"
    fi
    
    # NAT Gateways
    NATGWS=$(echo "$TAGGED_RESOURCES" | grep -o 'natgateway/nat-[a-zA-Z0-9]*' | cut -d'/' -f2 | sort -u | tr '\n' ' ')
    if [ -n "$NATGWS" ]; then
        echo -e "${BLUE}Delete NAT gateways:${NC}"
        for ngw in $NATGWS; do
            echo "aws ec2 delete-nat-gateway --nat-gateway-id $ngw --region $AWS_REGION"
        done
    fi
    
    # Security Groups
    SGS=$(echo "$TAGGED_RESOURCES" | grep -o 'security-group/sg-[a-zA-Z0-9]*' | cut -d'/' -f2 | sort -u | tr '\n' ' ')
    if [ -n "$SGS" ]; then
        echo -e "${BLUE}Delete security groups (after dependencies are removed):${NC}"
        for sg in $SGS; do
            echo "aws ec2 delete-security-group --group-id $sg --region $AWS_REGION"
        done
    fi
    
    # Subnets
    SUBNETS=$(echo "$TAGGED_RESOURCES" | grep -o 'subnet/subnet-[a-zA-Z0-9]*' | cut -d'/' -f2 | sort -u | tr '\n' ' ')
    if [ -n "$SUBNETS" ]; then
        echo -e "${BLUE}Delete subnets:${NC}"
        for subnet in $SUBNETS; do
            echo "aws ec2 delete-subnet --subnet-id $subnet --region $AWS_REGION"
        done
    fi
    
    # VPCs
    VPCS=$(echo "$TAGGED_RESOURCES" | grep -o 'vpc/vpc-[a-zA-Z0-9]*' | cut -d'/' -f2 | sort -u | tr '\n' ' ')
    if [ -n "$VPCS" ]; then
        echo -e "${BLUE}Delete VPCs:${NC}"
        for vpc in $VPCS; do
            echo "aws ec2 delete-vpc --vpc-id $vpc --region $AWS_REGION"
        done
    fi
    
    # RDS resources
    PARAM_GROUPS=$(echo "$TAGGED_RESOURCES" | grep -o 'pg:[^:]*' | cut -d':' -f2 | sort -u | tr '\n' ' ')
    if [ -n "$PARAM_GROUPS" ]; then
        echo -e "${BLUE}Delete RDS parameter groups:${NC}"
        for pg in $PARAM_GROUPS; do
            echo "aws rds delete-db-parameter-group --db-parameter-group-name $pg --region $AWS_REGION"
        done
    fi
    
    SUBNET_GROUPS=$(echo "$TAGGED_RESOURCES" | grep -o 'subgrp:[^:]*' | cut -d':' -f2 | sort -u | tr '\n' ' ')
    if [ -n "$SUBNET_GROUPS" ]; then
        echo -e "${BLUE}Delete RDS subnet groups:${NC}"
        for sg in $SUBNET_GROUPS; do
            echo "aws rds delete-db-subnet-group --db-subnet-group-name $sg --region $AWS_REGION"
        done
    fi
    
    # ElastiCache snapshots
    SNAPSHOTS=$(echo "$TAGGED_RESOURCES" | grep -o 'snapshot:[^:]*' | cut -d':' -f2 | sort -u | tr '\n' ' ')
    if [ -n "$SNAPSHOTS" ]; then
        echo -e "${BLUE}Delete ElastiCache snapshots:${NC}"
        for snapshot in $SNAPSHOTS; do
            echo "aws elasticache delete-snapshot --snapshot-name $snapshot --region $AWS_REGION"
        done
    fi
    
    # KMS keys
    KEYS=$(echo "$TAGGED_RESOURCES" | grep -o 'key/[a-zA-Z0-9-]*' | cut -d'/' -f2 | sort -u | tr '\n' ' ')
    if [ -n "$KEYS" ]; then
        echo -e "${BLUE}Schedule KMS key deletion:${NC}"
        for key in $KEYS; do
            echo "aws kms schedule-key-deletion --key-id $key --pending-window-in-days 7 --region $AWS_REGION"
        done
    fi
    
else
    log "No resources found with Environment=$ENVIRONMENT tag"
fi

echo ""
echo -e "${GREEN}✅ Verification completed!${NC}"
echo -e "${YELLOW}💡 Use the unified cleanup script for automated cleanup:${NC}"
echo -e "${YELLOW}   ./scripts/cleanup-infrastructure.sh${NC}"
echo ""
