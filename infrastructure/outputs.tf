# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnets
}

# Security Group Outputs
output "ec2_security_group_ids" {
  description = "IDs of the EC2 security groups"
  value       = module.security.ec2_security_group_ids
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = module.security.rds_security_group_id
}

# ECR Outputs
output "ecr_repository_urls" {
  description = "URLs of the ECR repositories"
  value       = module.ecr.repository_urls
}

# RDS Outputs
output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "rds_port" {
  description = "RDS instance port"
  value       = module.rds.db_port
}

# Compute Outputs - Conditional based on environment
output "dev_instance_public_ip" {
  description = "Public IP of the development EC2 instance"
  value       = var.environment == "dev" ? module.compute.instance_public_ip : null
}

output "dev_instance_private_ip" {
  description = "Private IP of the development EC2 instance"
  value       = var.environment == "dev" ? module.compute.instance_private_ip : null
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = var.environment == "prod" ? module.compute.eks_cluster_name : null
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = var.environment == "prod" ? module.compute.eks_cluster_endpoint : null
  sensitive   = true
}

output "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = var.environment == "prod" ? module.compute.eks_cluster_security_group_id : null
}
