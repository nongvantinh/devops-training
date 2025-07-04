output "repository_urls" {
  description = "Map of service names to ECR repository URLs"
  value = {
    for service, repo in aws_ecr_repository.coffeeshop_services :
    service => repo.repository_url
  }
}

output "repository_arns" {
  description = "Map of service names to ECR repository ARNs"
  value = {
    for service, repo in aws_ecr_repository.coffeeshop_services :
    service => repo.arn
  }
}