environment = "staging"
aws_region  = "us-west-2"
vpc_cidr    = "10.1.0.0/16"

public_subnets  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnets = ["10.1.10.0/24", "10.1.11.0/24"]

# EC2 Configuration for staging
instance_type = "t3.large"
key_name      = "" # Add your AWS key pair name here

# Database Configuration
db_name     = "coffeeshop_staging"
db_username = "postgres"
db_password = "staging-password-456" # Change this in production

# Common tags
common_tags = {
  Environment = "staging"
  Project     = "CoffeeShop"
  Owner       = "DevOps-Training"
  ManagedBy   = "Terraform"
}