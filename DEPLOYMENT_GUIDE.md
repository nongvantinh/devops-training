# CoffeeShop DevOps Deployment Guide

**Technical reference and troubleshooting**

**For complete workflow**: Use [STEP_BY_STEP_GUIDE.md](STEP_BY_STEP_GUIDE.md)  
**For AWS issues**: Use [AWS_PERMISSION_FIX.md](AWS_PERMISSION_FIX.md)

## 🏗️ Technical Architecture

### System Overview
```
                    [Application Load Balancer]
                            │
                    [CoffeeShop Proxy]
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
   [Product Service]  [Counter Service]  [Web Frontend]
        │                   │                   │
        └───────────────────┼───────────────────┘
                            │
                    [Message Queue - RabbitMQ]
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
   [Barista Service]  [Kitchen Service]  [PostgreSQL DB]
```

### Component Details

#### Microservices
- **Web Frontend** (Port 8888): React/Go customer interface
- **Proxy** (Port 8080): Nginx reverse proxy and API gateway
- **Product Service** (Port 8081): Product catalog and inventory
- **Counter Service** (Port 8082): Order management and payment
- **Barista Service** (Port 8083): Drink preparation queue
- **Kitchen Service** (Port 8084): Food preparation workflow

#### Infrastructure
- **Database**: PostgreSQL (RDS for production, containerized for dev)
- **Message Queue**: RabbitMQ for asynchronous service communication
- **Load Balancer**: AWS ALB for production traffic distribution
- **Cache**: ElastiCache Redis for performance optimization

## 🔧 Environment Details

### Local Development
```bash
# Start complete environment
./scripts/setup-dev.sh

# Services available at:
# - Web App: http://localhost:8888
# - Proxy API: http://localhost:8080
# - RabbitMQ UI: http://localhost:15672 (guest/guest)
# - Database: localhost:5432 (coffeeshop/coffeeshop)
```

### AWS Development
- **EC2**: Single t3.medium instance with Docker Compose
- **RDS**: PostgreSQL t3.micro (Free Tier eligible)
- **ALB**: Application Load Balancer with health checks
- **VPC**: Custom networking with public/private subnets
- **Cost**: ~$50/month

### AWS Production (EKS)
- **EKS**: Managed Kubernetes cluster with auto-scaling
- **RDS**: Multi-AZ PostgreSQL with automated backups
- **ALB**: SSL termination and advanced routing
- **Monitoring**: Prometheus and Grafana stack
- **Cost**: ~$150-300/month

## 🔍 Troubleshooting

### Common Issues

#### Docker Issues
```bash
# Permission denied
sudo usermod -aG docker $USER
newgrp docker

# Port conflicts
./scripts/setup-dev.sh stop
docker system prune -f

# Database connection
./scripts/setup-dev.sh cleanup
./scripts/setup-dev.sh
```

#### AWS Issues
```bash
# Permission errors
./scripts/setup-aws-config.sh fix-permissions

# Terraform errors
export AWS_PROFILE=devops-training
./scripts/deploy-infrastructure.sh dev --dry-run

# Can't access application
# Check security groups allow HTTP traffic
# Verify load balancer health checks
```

#### Kubernetes Issues
```bash
# Check pod status
kubectl get pods -n coffeeshop

# View logs
kubectl logs -f deployment/coffeeshop-web -n coffeeshop

# Scale deployment
kubectl scale deployment coffeeshop-web --replicas=3 -n coffeeshop
```

### Service Health Checks
```bash
# Local environment
curl http://localhost:8080/health

# AWS environment
curl http://<load-balancer-dns>/health

# Kubernetes environment
kubectl get pods -n coffeeshop
kubectl describe pod <pod-name> -n coffeeshop
```

## 💰 Cost Optimization

### Development Environment
- **EC2 t3.medium**: ~$30/month
- **RDS t3.micro**: $0-15/month (Free Tier)
- **ALB**: ~$18/month
- **Total**: ~$50/month

### Production Environment
- **EKS cluster**: $72/month (control plane)
- **Worker nodes**: $30-90/month
- **RDS production**: $50-150/month
- **ALB + extras**: ~$30/month
- **Total**: $150-300/month

### Cost Reduction Tips
- Use spot instances for non-critical workloads
- Stop development environments when not in use
- Use RDS Free Tier for development
- Monitor costs with billing alerts

## 🔒 Security Best Practices

### Infrastructure Security
- **VPC isolation**: Custom VPC with private subnets
- **Security groups**: Least-privilege firewall rules
- **IAM roles**: Service-specific permissions
- **Encryption**: Data at rest and in transit

### Application Security
- **Container scanning**: Automated vulnerability assessment
- **Secrets management**: No hardcoded credentials
- **TLS encryption**: HTTPS for external traffic
- **Network policies**: Kubernetes network isolation

## 📊 Monitoring and Operations

### Health Monitoring
- **Prometheus**: Metrics collection from all services
- **Grafana**: Visualization dashboards
- **CloudWatch**: AWS infrastructure monitoring
- **Health endpoints**: Service-level health checks

### Log Management
```bash
# Local logs
./scripts/setup-dev.sh logs

# Kubernetes logs
kubectl logs -f deployment/coffeeshop-web -n coffeeshop

# AWS logs (on EC2)
ssh -i key.pem ec2-user@<instance-ip>
docker-compose logs -f
```

## 🔧 Advanced Configuration

### Scaling
```bash
# Kubernetes horizontal scaling
kubectl scale deployment coffeeshop-web --replicas=3 -n coffeeshop

# AWS Auto Scaling (configured in Terraform)
# Automatic based on CPU/memory metrics
```

### Backup and Recovery
- **RDS**: Daily automated backups with point-in-time recovery
- **Terraform State**: S3 bucket with versioning
- **Container Images**: ECR with lifecycle policies

### Disaster Recovery
```bash
# Infrastructure recovery
./scripts/deploy-infrastructure.sh <environment>

# Database recovery
aws rds restore-db-instance-from-db-snapshot

# Application recovery
kubectl rollout undo deployment/<service-name>
```

## 🧹 Resource Cleanup

### Development Environment
```bash
# Stop services but keep data
./scripts/setup-dev.sh stop

# Complete cleanup
./scripts/setup-dev.sh cleanup
```

### AWS Resources
```bash
# Complete cleanup (stops all billing)
./deploy.sh cleanup

# Verify cleanup
./scripts/cleanup-infrastructure.sh --verify-only

# Emergency cleanup
./scripts/cleanup-infrastructure.sh --force
```

**Important**: Always clean up AWS resources when done to avoid charges!

## 📚 Additional Resources

- **Complete Workflow**: [STEP_BY_STEP_GUIDE.md](STEP_BY_STEP_GUIDE.md)
- **AWS Troubleshooting**: [AWS_PERMISSION_FIX.md](AWS_PERMISSION_FIX.md)
- **Project Overview**: [README.md](README.md)

---

**Need help?** Check the [STEP_BY_STEP_GUIDE.md](STEP_BY_STEP_GUIDE.md) for complete workflow instructions.
