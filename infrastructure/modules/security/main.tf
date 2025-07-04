# Web/Application Load Balancer Security Group
resource "aws_security_group" "alb" {
  name_prefix = "${var.environment}-alb-"
  vpc_id      = var.vpc_id

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-alb-sg"
  })
}

# EC2 Security Group
resource "aws_security_group" "ec2" {
  name_prefix = "${var.environment}-ec2-"
  vpc_id      = var.vpc_id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict this in production
  }

  # HTTP access from ALB
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # CoffeeShop application ports
  ingress {
    from_port   = 5000
    to_port     = 5002
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # Web application port
  ingress {
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # Docker daemon port for management
  ingress {
    from_port   = 2376
    to_port     = 2376
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-ec2-sg"
  })
}

# EKS Cluster Security Group
resource "aws_security_group" "eks_cluster" {
  count = var.environment == "prod" ? 1 : 0

  name_prefix = "${var.environment}-eks-cluster-"
  vpc_id      = var.vpc_id

  # HTTPS access for EKS API server
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-eks-cluster-sg"
  })
}

# EKS Node Group Security Group
resource "aws_security_group" "eks_nodes" {
  count = var.environment == "prod" ? 1 : 0

  name_prefix = "${var.environment}-eks-nodes-"
  vpc_id      = var.vpc_id

  # Allow nodes to communicate with cluster API Server
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster[0].id]
  }

  # Allow nodes to communicate with each other
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  # Allow pods to communicate with cluster API Server
  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster[0].id]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-eks-nodes-sg"
  })
}

# RDS Security Group
resource "aws_security_group" "rds" {
  name_prefix = "${var.environment}-rds-"
  vpc_id      = var.vpc_id

  # PostgreSQL access from EC2 and EKS nodes
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = concat([aws_security_group.ec2.id], var.environment == "prod" ? [aws_security_group.eks_nodes[0].id] : [])
  }

  # RabbitMQ access from application servers
  ingress {
    from_port       = 5672
    to_port         = 5672
    protocol        = "tcp"
    security_groups = concat([aws_security_group.ec2.id], var.environment == "prod" ? [aws_security_group.eks_nodes[0].id] : [])
  }

  # RabbitMQ Management interface
  ingress {
    from_port       = 15672
    to_port         = 15672
    protocol        = "tcp"
    security_groups = concat([aws_security_group.ec2.id], var.environment == "prod" ? [aws_security_group.eks_nodes[0].id] : [])
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-rds-sg"
  })
}