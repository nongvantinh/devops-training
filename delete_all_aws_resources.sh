#!/bin/bash

# Use set -o errexit to exit on errors (for portability)
set -o errexit

# Get all AWS regions
regions=$(aws ec2 describe-regions --query "Regions[*].RegionName" --output text)

echo "Starting deletion of AWS resources in all regions..."

# Delete global resources
echo "Deleting global resources..."

# S3 Buckets: Empty and delete all versions and delete markers
for bucket in $(aws s3api list-buckets --query "Buckets[].Name" --output text); do
  echo "Emptying and deleting all versions in bucket: $bucket"
  
  # Get all versions and delete markers
  versions=$(aws s3api list-object-versions --bucket $bucket --query "Versions[].{Key:Key,VersionId:VersionId}" --output json)
  delete_markers=$(aws s3api list-object-versions --bucket $bucket --query "DeleteMarkers[].{Key:Key,VersionId:VersionId}" --output json)
  
  # Delete all versions
  for version in $(echo $versions | jq -r '.[] | @base64'); do
    _jq() {
      echo ${version} | base64 --decode | jq -r ${1}
    }
    key=$(_jq '.Key')
    version_id=$(_jq '.VersionId')
    echo "Deleting version: $key (Version ID: $version_id)"
    aws s3api delete-object --bucket $bucket --key "$key" --version-id "$version_id"
  done
  
  # Delete all delete markers
  for delete_marker in $(echo $delete_markers | jq -r '.[] | @base64'); do
    _jq() {
      echo ${delete_marker} | base64 --decode | jq -r ${1}
    }
    key=$(_jq '.Key')
    version_id=$(_jq '.VersionId')
    echo "Deleting delete marker: $key (Version ID: $version_id)"
    aws s3api delete-object --bucket $bucket --key "$key" --version-id "$version_id"
  done

  # Now delete the bucket
  aws s3api delete-bucket --bucket $bucket
done

# IAM cleanup (manual review may still be required)
echo "IAM cleanup (manual review may still be required)"
# AWS does not allow easy mass deletion of IAM resources via CLI
# Recommend to manually verify IAM users/roles/groups from the console

for region in $regions; do
  echo "Processing region: $region"

  # EC2 Instances
  instance_ids=$(aws ec2 describe-instances --region $region --query "Reservations[].Instances[].InstanceId" --output text)
  if [ "$instance_ids" ]; then
    echo "Terminating EC2 instances in $region: $instance_ids"
    aws ec2 terminate-instances --region $region --instance-ids $instance_ids
  fi

  # Lambda Functions
  for func in $(aws lambda list-functions --region $region --query "Functions[].FunctionName" --output text); do
    echo "Deleting Lambda: $func"
    aws lambda delete-function --function-name $func --region $region
  done

  # RDS Instances
  for db in $(aws rds describe-db-instances --region $region --query "DBInstances[].DBInstanceIdentifier" --output text); do
    echo "Deleting RDS DB instance: $db"
    aws rds delete-db-instance --db-instance-identifier $db --region $region --skip-final-snapshot
  done

  # CloudFormation Stacks
  for stack in $(aws cloudformation describe-stacks --region $region --query "Stacks[].StackName" --output text); do
    echo "Deleting CloudFormation stack: $stack"
    aws cloudformation delete-stack --stack-name $stack --region $region
  done

  # VPCs (must detach/delete sub-resources first)
  for vpc_id in $(aws ec2 describe-vpcs --region $region --query "Vpcs[].VpcId" --output text); do
    echo "Deleting VPC and associated resources: $vpc_id"

    # Get Subnets in the VPC
    subnet_ids=$(aws ec2 describe-subnets --region $region --filters Name=vpc-id,Values=$vpc_id --query "Subnets[].SubnetId" --output text)

    # Loop through subnets and delete their resources
    for subnet in $subnet_ids; do
      echo "Checking subnet: $subnet for dependencies..."

      # Terminate EC2 instances in subnet
      instance_ids_in_subnet=$(aws ec2 describe-instances --region $region --filters "Name=subnet-id,Values=$subnet" --query "Reservations[].Instances[].InstanceId" --output text)
      if [ "$instance_ids_in_subnet" ]; then
        echo "Terminating EC2 instances in subnet: $subnet"
        aws ec2 terminate-instances --region $region --instance-ids $instance_ids_in_subnet
      fi

      # Disassociate Elastic IPs (if any)
      eips=$(aws ec2 describe-addresses --region $region --query "Addresses[?AssociationId!=null].AssociationId" --output text)
      if [ "$eips" ]; then
        for eip in $eips; do
          echo "Releasing Elastic IP: $eip"
          aws ec2 disassociate-address --association-id $eip --region $region
        done
      fi

      # Delete Network Interfaces (ENIs) attached to resources in subnet
      eni_ids=$(aws ec2 describe-network-interfaces --region $region --filters Name=subnet-id,Values=$subnet --query "NetworkInterfaces[].NetworkInterfaceId" --output text)
      if [ "$eni_ids" ]; then
        for eni in $eni_ids; do
          echo "Checking if ENI $eni is attached to a resource..."

          # Check if ENI is attached to a resource
          attachment=$(aws ec2 describe-network-interfaces --region $region --network-interface-ids $eni --query "NetworkInterfaces[].Attachment" --output text)
          
          if [[ $attachment == *"AttachmentId"* ]]; then
            # Detach the ENI if it's attached
            attachment_id=$(echo $attachment | awk '{print $2}')
            echo "Detaching ENI $eni from attachment $attachment_id"
            aws ec2 detach-network-interface --attachment-id $attachment_id --region $region
            # Wait for ENI to detach before attempting deletion
            aws ec2 wait network-interface-available --network-interface-id $eni --region $region
          fi

          # Now delete the ENI
          echo "Deleting ENI: $eni"
          aws ec2 delete-network-interface --network-interface-id $eni --region $region
        done
      fi

      # Delete Route Tables (skip main route table)
      route_table_ids=$(aws ec2 describe-route-tables --region $region --filters Name=vpc-id,Values=$vpc_id --query "RouteTables[?Associations[?Main!=\`true\`]].RouteTableId" --output text)
      if [ "$route_table_ids" ]; then
        for rt_id in $route_table_ids; do
          echo "Deleting route table: $rt_id"
          aws ec2 delete-route-table --route-table-id $rt_id --region $region
        done
      fi

      # Check for NAT Gateways in the subnet
      nat_gateways=$(aws ec2 describe-nat-gateways --region $region --filter "Name=subnet-id,Values=$subnet" --query "NatGateways[].NatGatewayId" --output text)
      if [ "$nat_gateways" ]; then
        for nat_gateway in $nat_gateways; do
          echo "Deleting NAT Gateway: $nat_gateway"
          aws ec2 delete-nat-gateway --nat-gateway-id $nat_gateway --region $region
        done
      fi

      # Check for VPN connections in the subnet
      vpn_connections=$(aws ec2 describe-vpn-connections --region $region --query "VpnConnections[].VpnConnectionId" --output text)
      if [ "$vpn_connections" ]; then
        for vpn_connection in $vpn_connections; do
          echo "Deleting VPN connection: $vpn_connection"
          aws ec2 delete-vpn-connection --vpn-connection-id $vpn_connection --region $region
        done
      fi

      # Finally delete the subnet
      echo "Deleting subnet: $subnet"
      aws ec2 delete-subnet --subnet-id $subnet --region $region
    done

    # Finally delete the VPC
    aws ec2 delete-vpc --vpc-id $vpc_id --region $region
  done

  # Security Groups (except default)
  for sg_id in $(aws ec2 describe-security-groups --region $region --query "SecurityGroups[?GroupName!='default'].GroupId" --output text); do
    aws ec2 delete-security-group --group-id $sg_id --region $region || true
  done

  # Elastic Load Balancers
  for elb in $(aws elb describe-load-balancers --region $region --query "LoadBalancerDescriptions[].LoadBalancerName" --output text); do
    aws elb delete-load-balancer --load-balancer-name $elb --region $region
  done

  # EBS Volumes
  for volume in $(aws ec2 describe-volumes --region $region --query "Volumes[].VolumeId" --output text); do
    aws ec2 delete-volume --volume-id $volume --region $region || true
  done

done

echo "Resource deletion complete."
