environment = "dev"
aws_region  = "us-west-2"
vpc_cidr    = "10.0.0.0/16"

public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]

# EC2 Configuration for development
instance_type = "t3.medium"
key_name      = "coffeeshop-dev-key" # SSH key pair for EC2 access

# Database Configuration
db_name     = "coffeeshop_dev"
db_username = "postgres"
db_password = "dev-password-123" # Change this in production

# Common tags
common_tags = {
  Environment = "dev"
  Project     = "CoffeeShop"
  Owner       = "DevOps-Training"
  ManagedBy   = "Terraform"
}
