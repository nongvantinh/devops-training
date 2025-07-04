environment = "prod"
aws_region  = "us-west-2"
vpc_cidr    = "10.2.0.0/16"

public_subnets  = ["10.2.1.0/24", "10.2.2.0/24"]
private_subnets = ["10.2.10.0/24", "10.2.11.0/24"]

# EKS Configuration for production
eks_cluster_name    = "coffeeshop-prod"
eks_node_group_name = "coffeeshop-prod-nodes"
node_instance_types = ["t3.medium", "t3.large"]
desired_capacity    = 3
max_capacity        = 10
min_capacity        = 2

# Database Configuration
db_name     = "coffeeshop_prod"
db_username = "postgres"
db_password = "CHANGE_ME_IN_PRODUCTION" # Use AWS Secrets Manager in real production

# Common tags
common_tags = {
  Environment = "prod"
  Project     = "CoffeeShop"
  Owner       = "DevOps-Training"
  ManagedBy   = "Terraform"
}
