output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "ec2_security_group_ids" {
  description = "IDs of the EC2 security groups"
  value       = [aws_security_group.ec2.id]
}

output "eks_cluster_security_group_id" {
  description = "ID of the EKS cluster security group"
  value       = var.environment == "prod" ? aws_security_group.eks_cluster[0].id : null
}

output "eks_nodes_security_group_id" {
  description = "ID of the EKS nodes security group"
  value       = var.environment == "prod" ? aws_security_group.eks_nodes[0].id : null
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}