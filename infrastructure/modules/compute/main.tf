# Data source for latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Data source for EKS optimized AMI
data "aws_ami" "eks_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-1.28-v*"]
  }
}

# User data script for EC2 instance
locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    environment = var.environment
  }))
}

# EC2 Instance (for dev and staging environments)
resource "aws_instance" "app_server" {
  count = var.environment != "prod" ? 1 : 0

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = var.key_name != "" ? var.key_name : null
  vpc_security_group_ids = var.security_groups
  subnet_id              = var.public_subnets[0]

  user_data = local.user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-coffeeshop-server"
    Type = "AppServer"
  })
}

# EKS Cluster (for prod environment)
resource "aws_eks_cluster" "main" {
  count = var.environment == "prod" ? 1 : 0

  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster[0].arn
  version  = "1.28"

  vpc_config {
    subnet_ids              = concat(var.public_subnets, var.private_subnets)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks[0].arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_service_policy,
    aws_cloudwatch_log_group.eks_cluster,
  ]

  tags = merge(var.tags, {
    Name = "${var.environment}-eks-cluster"
  })
}

# EKS Node Group
resource "aws_eks_node_group" "main" {
  count = var.environment == "prod" ? 1 : 0

  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = var.eks_node_group_name
  node_role_arn   = aws_iam_role.eks_node_group[0].arn
  subnet_ids      = var.private_subnets

  capacity_type  = "ON_DEMAND"
  ami_type       = "AL2_x86_64"
  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.desired_capacity
    max_size     = var.max_capacity
    min_size     = var.min_capacity
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_registry_policy,
  ]

  tags = merge(var.tags, {
    Name = "${var.environment}-eks-node-group"
  })
}

# Launch template for EKS nodes
resource "aws_launch_template" "eks_nodes" {
  count = var.environment == "prod" ? 1 : 0

  name_prefix   = "${var.environment}-eks-nodes-"
  image_id      = data.aws_ami.eks_optimized.id
  instance_type = var.node_instance_types[0]

  vpc_security_group_ids = var.security_groups

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 50
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.environment}-eks-worker-node"
    })
  }
}

# KMS key for EKS encryption
resource "aws_kms_key" "eks" {
  count = var.environment == "prod" ? 1 : 0

  description             = "EKS Secret Encryption Key"
  deletion_window_in_days = 7

  tags = merge(var.tags, {
    Name = "${var.environment}-eks-encryption-key"
  })
}

# CloudWatch Log Group for EKS
resource "aws_cloudwatch_log_group" "eks_cluster" {
  count = var.environment == "prod" ? 1 : 0

  name              = "/aws/eks/${var.eks_cluster_name}/cluster"
  retention_in_days = 7

  tags = merge(var.tags, {
    Name = "${var.environment}-eks-logs"
  })
}

# EKS Access Entry for IAM User
resource "aws_eks_access_entry" "admin_user" {
  count = var.environment == "prod" ? 1 : 0

  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = "arn:aws:iam::123264127435:user/devops-training-user"
  type          = "STANDARD"

  depends_on = [aws_eks_cluster.main]
}

# EKS Access Policy Association for admin access
resource "aws_eks_access_policy_association" "admin_user_policy" {
  count = var.environment == "prod" ? 1 : 0

  cluster_name  = aws_eks_cluster.main[0].name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = aws_eks_access_entry.admin_user[0].principal_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin_user]
}