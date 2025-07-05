# CoffeeShop DevOps Project - Step-by-Step Guide

**Complete deployment guide for all environments**

**📍 Quick Navigation:**
- **[Local Development](#-option-1-local-development)** (2 minutes, $0)
- **[AWS Development](#-option-2-aws-development)** (~$50/month)
- **[AWS Production](#-option-3-aws-production)** (~$150-300/month)
- **[Troubleshooting](#troubleshooting)** (Common issues)
- **[Cleanup](#cleanup)** (Stop billing)

## 🚀 Choose Your Path

```
What's your goal?
├── 🧪 Just testing/learning → Option 1 (Local) - 2 minutes, $0
├── 🎯 Demo for work/portfolio → Option 2 (AWS Dev) - 15 minutes, ~$50/month
├── 🏭 Production deployment → Option 3 (AWS Prod) - 30 minutes, ~$150-300/month
└── 🛠️ Need help? → See Troubleshooting section below
```

## 🎬 Before You Start

**Prerequisites:**
- **Local**: Docker and Docker Compose
- **AWS**: AWS CLI, Terraform, kubectl
- **Important**: AWS costs real money! Set up billing alerts.

---

## 📦 Option 1: Local Development

**✅ No AWS costs • ✅ 2-minute setup • ✅ Full application**

### One-Command Setup
```bash
# Clone and start everything
git clone https://github.com/nongvantinh/devops-training.git
cd devops-training
./deploy.sh local
```

### Access Your Application
- **Web App**: http://localhost:8888
- **API Gateway**: http://localhost:8080
- **RabbitMQ**: http://localhost:15672 (guest/guest)

### Useful Commands
```bash
./deploy.sh local               # Start/restart services
./scripts/setup-dev.sh logs     # View logs
./scripts/setup-dev.sh stop     # Stop services
./scripts/setup-dev.sh cleanup  # Complete cleanup
```

**🎉 Success**: You can access the CoffeeShop application at http://localhost:8888

---

## ☁️ Option 2: AWS Development

**💰 ~$50/month • ✅ Production-like • ✅ Free Tier eligible**

### Step 1: AWS Setup (One-time)
```bash
# Configure AWS credentials and permissions
./deploy.sh setup-aws

# Follow the interactive prompts to:
# - Create dedicated AWS profile
# - Set up all required permissions
# - Configure AWS CLI automatically
```

### Step 2: Deploy to AWS
```bash
# Deploy development environment
./deploy.sh aws-dev

# Wait ~10-15 minutes for deployment
# Access URL will be displayed when ready
```

### Step 3: Access Your Application
```bash
# URL will be shown after deployment completes
# Format: http://coffeeshop-dev-alb-xxxxxxxxx.us-west-2.elb.amazonaws.com
```

**🎉 Success**: You can access your application via the AWS Load Balancer URL

---

## 🏭 Option 3: AWS Production (EKS)

**💰 ~$150-300/month • ✅ Kubernetes • ✅ Auto-scaling • ✅ High availability**

### Step 1: Deploy Production Infrastructure
```bash
# Deploy production environment with EKS
./deploy.sh aws-prod

# Wait ~20-30 minutes for EKS cluster creation
```

### Step 2: Deploy Application to Kubernetes
```bash
# Deploy microservices to EKS
./scripts/deploy-k8s.sh

# Check deployment status
kubectl get pods -n coffeeshop
```

### Step 3: Access Application
```bash
# Get load balancer URL
kubectl get svc -n coffeeshop coffeeshop-web

# Access monitoring
kubectl port-forward svc/grafana 3000:3000 -n monitoring
# Open http://localhost:3000 (admin/admin)
```

**🎉 Success**: You have a production-ready Kubernetes deployment with monitoring

---

## Troubleshooting

### Common Issues

**Docker Issues:**
```bash
# Docker permission denied
sudo usermod -aG docker $USER
newgrp docker

# Port conflicts
docker stop $(docker ps -aq)
docker system prune -f
```

**AWS Permission Errors:**
```bash
# Fix permissions automatically
./deploy.sh setup-aws
# OR
./scripts/setup-aws-config.sh fix-permissions
```

**Terraform Errors:**
```bash
# Test configuration without deploying
./scripts/deploy-infrastructure.sh dev --dry-run

# Common fixes
export AWS_PROFILE=devops-training
terraform workspace select dev
terraform plan
```

**Can't Access Application:**
```bash
# Local development
curl http://localhost:8888
docker ps  # Check if containers are running

# AWS development
# Check security groups allow HTTP traffic
# Verify load balancer is healthy
```

### Getting Help
- **AWS Issues**: See [AWS_PERMISSION_FIX.md](AWS_PERMISSION_FIX.md)
- **Technical Details**: See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
- **Check Logs**: `./scripts/setup-dev.sh logs` (local) or `kubectl logs` (K8s)

---

## Cleanup

### Stop Local Development
```bash
./scripts/setup-dev.sh stop     # Stop but keep data
./scripts/setup-dev.sh cleanup  # Remove everything
```

### Clean Up AWS Resources
```bash
# Complete cleanup (stops all billing)
./deploy.sh cleanup

# Unified cleanup script options
./scripts/cleanup-infrastructure.sh --verify-only prod    # Check what exists
./scripts/cleanup-infrastructure.sh prod                  # Full cleanup
./scripts/cleanup-infrastructure.sh --terraform-only prod # Terraform only
./scripts/cleanup-infrastructure.sh --force prod          # Skip prompts
```

The unified cleanup script handles resource dependencies correctly and eliminates the need for manual cleanup.

**💰 Important**: Always clean up AWS resources when done to avoid charges!

---

## Next Steps

### After Local Development
1. **Learn**: Explore the microservices architecture
2. **Experiment**: Modify code and see changes
3. **Scale up**: Try AWS development environment

### After AWS Development
1. **Monitor**: Check AWS costs in billing dashboard
2. **Scale**: Try production deployment
3. **Optimize**: Adjust instance sizes for your needs

### After Production
1. **Monitor**: Set up alerts and dashboards
2. **Secure**: Review security best practices
3. **Optimize**: Fine-tune for performance and costs

**🎯 Remember**: This is a learning project - always clean up resources when done!

---

## 💡 Quick Commands Reference

```bash
# Essential commands
./deploy.sh local              # Start local development
./deploy.sh setup-aws          # Configure AWS (one-time)
./deploy.sh aws-dev            # Deploy to AWS development
./deploy.sh aws-prod           # Deploy to AWS production
./deploy.sh cleanup            # Clean up all AWS resources

# Local development
./scripts/setup-dev.sh         # Start local environment
./scripts/setup-dev.sh logs    # View logs
./scripts/setup-dev.sh stop    # Stop services
./scripts/setup-dev.sh cleanup # Remove everything

# AWS troubleshooting
./scripts/setup-aws-config.sh test           # Test permissions
./scripts/setup-aws-config.sh fix-permissions # Fix permission issues
./scripts/cleanup-infrastructure.sh --verify-only # Check resources
```

**🚀 Ready to start? Pick an option above and follow the steps!**
