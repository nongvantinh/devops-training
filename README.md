# Go CoffeeShop DevOps Project

**Complete microservices application with local and AWS deployment options**

## 🚀 Quick Start

Choose your deployment path:

```bash
./deploy.sh local              # Local development (2 min, $0)
# Configure AWS (one-time)
export AWS_PROFILE=devops-training && ./deploy.sh setup-aws
./deploy.sh aws-dev            # AWS development (~$50/month)
./deploy.sh aws-prod           # AWS production (~$150-300/month)
./deploy.sh cleanup            # Clean up AWS resources
```

## 📖 Documentation

- **[STEP_BY_STEP_GUIDE.md](STEP_BY_STEP_GUIDE.md)** - Complete workflow guide
- **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** - Technical reference
- **[AWS_PERMISSION_FIX.md](AWS_PERMISSION_FIX.md)** - AWS troubleshooting

## 🎯 What You'll Build

- **6 Microservices**: Web, Proxy, Product, Counter, Barista, Kitchen
- **Infrastructure**: AWS VPC, EC2, RDS, ElastiCache, Load Balancer
- **Container Registry**: ECR repositories
- **Local Environment**: Docker Compose
- **Production**: Kubernetes on EKS
- **Monitoring**: Prometheus & Grafana

## Architecture

6 microservices (Web, Proxy, Product, Counter, Barista, Kitchen) with PostgreSQL, RabbitMQ, and monitoring.

## Prerequisites

- **Docker** (for local development)
- **AWS CLI & Terraform** (for AWS deployments)
- **kubectl** (for production deployments)

## Next Steps

1. **Start local**: `./deploy.sh local`
2. **Try AWS**: `./deploy.sh setup-aws` then `./deploy.sh aws-dev`
3. **Production**: `./deploy.sh aws-prod`
4. **Cleanup**: `./deploy.sh cleanup`

## 🧹 Cleanup

For comprehensive cleanup of AWS resources:

```bash
# Check what resources exist
./scripts/cleanup-infrastructure.sh --verify-only prod

# Preview what would be deleted (dry-run)
./scripts/cleanup-infrastructure.sh --dry-run prod

# Full cleanup with confirmation
./scripts/cleanup-infrastructure.sh prod

# Terraform-only cleanup
./scripts/cleanup-infrastructure.sh --terraform-only prod

# Full cleanup without confirmation prompts
./scripts/cleanup-infrastructure.sh --force prod
```

The unified cleanup script handles resource dependencies correctly, provides detailed logging, and eliminates the need for manual cleanup. It supports multiple modes including dry-run for safe preview of operations.

**💰 Cost Warning**: AWS deployments cost real money (~$50-300/month)

---

**For complete instructions, see [STEP_BY_STEP_GUIDE.md](STEP_BY_STEP_GUIDE.md)**
