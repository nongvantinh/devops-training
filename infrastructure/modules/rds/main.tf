# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-db-subnet-group"
  subnet_ids = var.private_subnets

  tags = merge(var.tags, {
    Name = "${var.environment}-db-subnet-group"
  })
}

# DB Parameter Group
resource "aws_db_parameter_group" "main" {
  family = "postgres14"
  name   = "${var.environment}-postgres-params"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "all"
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-postgres-params"
  })
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier = "${var.environment}-coffeeshop-db"

  # Engine options
  engine         = "postgres"
  engine_version = "14.12"
  instance_class = var.environment == "prod" ? "db.t3.medium" : "db.t3.micro"

  # Storage
  allocated_storage     = var.environment == "prod" ? 100 : 20
  max_allocated_storage = var.environment == "prod" ? 1000 : 100
  storage_type          = "gp2"
  storage_encrypted     = true

  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  # Network & Security
  vpc_security_group_ids = var.security_groups
  db_subnet_group_name   = aws_db_subnet_group.main.name
  publicly_accessible    = false

  # Parameter and option groups
  parameter_group_name = aws_db_parameter_group.main.name

  # Backup
  backup_retention_period = var.environment == "prod" ? 7 : 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Deletion protection
  deletion_protection       = var.environment == "prod" ? true : false
  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${var.environment}-coffeeshop-db-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  # Performance insights
  performance_insights_enabled = var.environment == "prod"

  tags = merge(var.tags, {
    Name = "${var.environment}-coffeeshop-db"
  })
}

# RabbitMQ using ElastiCache for Redis as message broker alternative
# Note: For a complete RabbitMQ setup, you'd typically use Amazon MQ or deploy RabbitMQ on EC2
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.environment}-redis-subnet-group"
  subnet_ids = var.private_subnets

  tags = merge(var.tags, {
    Name = "${var.environment}-redis-subnet-group"
  })
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.environment}-coffeeshop-redis"
  description          = "Redis cluster for ${var.environment} environment"

  node_type            = var.environment == "prod" ? "cache.t3.medium" : "cache.t3.micro"
  port                 = 6379
  parameter_group_name = "default.redis7"

  num_cache_clusters = var.environment == "prod" ? 2 : 1

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = var.security_groups

  # Backup
  snapshot_retention_limit = var.environment == "prod" ? 3 : 0
  snapshot_window          = "03:00-05:00"
  maintenance_window       = "sun:05:00-sun:07:00"

  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  tags = merge(var.tags, {
    Name = "${var.environment}-coffeeshop-redis"
  })
}