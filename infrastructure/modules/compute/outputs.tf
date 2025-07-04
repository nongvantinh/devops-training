# EC2 Outputs
output "instance_id" {
  description = "ID of the EC2 instance"
  value       = var.environment != "prod" ? aws_instance.app_server[0].id : null
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = var.environment != "prod" ? aws_instance.app_server[0].public_ip : null
}

output "instance_private_ip" {
  description = "Private IP of the EC2 instance"
  value       = var.environment != "prod" ? aws_instance.app_server[0].private_ip : null
}

# EKS Outputs
output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = var.environment == "prod" ? aws_eks_cluster.main[0].name : null
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = var.environment == "prod" ? aws_eks_cluster.main[0].endpoint : null
}

output "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = var.environment == "prod" ? aws_eks_cluster.main[0].vpc_config[0].cluster_security_group_id : null
}

output "eks_cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = var.environment == "prod" ? aws_eks_cluster.main[0].arn : null
}