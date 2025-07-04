terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "coffeeshop-terraform-state-dev-ubuntu"
    key            = "terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = data.aws_availability_zones.available.names
  public_subnets     = var.public_subnets
  private_subnets    = var.private_subnets

  tags = var.common_tags
}

# Security Module
module "security" {
  source = "./modules/security"

  environment = var.environment
  vpc_id      = module.vpc.vpc_id

  tags = var.common_tags
}

# ECR Module
module "ecr" {
  source = "./modules/ecr"

  environment = var.environment
  services    = var.services

  tags = var.common_tags
}

# RDS Module
module "rds" {
  source = "./modules/rds"

  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
  security_groups = [module.security.rds_security_group_id]

  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password

  tags = var.common_tags
}

# Compute Module (EC2 for dev, EKS for prod)
module "compute" {
  source = "./modules/compute"

  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  public_subnets  = module.vpc.public_subnets
  private_subnets = module.vpc.private_subnets
  security_groups = module.security.ec2_security_group_ids

  # EC2 specific
  instance_type = var.instance_type
  key_name      = var.key_name

  # EKS specific
  eks_cluster_name    = var.eks_cluster_name
  eks_node_group_name = var.eks_node_group_name
  node_instance_types = var.node_instance_types
  desired_capacity    = var.desired_capacity
  max_capacity        = var.max_capacity
  min_capacity        = var.min_capacity

  tags = var.common_tags
}
