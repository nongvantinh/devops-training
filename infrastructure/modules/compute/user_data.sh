#!/bin/bash

# Update system
yum update -y

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Create directory for CoffeeShop application
mkdir -p /opt/coffeeshop
chown ec2-user:ec2-user /opt/coffeeshop

# Create a simple script to pull ECR images
cat > /opt/coffeeshop/ecr-login.sh << 'EOF'
#!/bin/bash
AWS_REGION="us-west-2"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
EOF

chmod +x /opt/coffeeshop/ecr-login.sh
chown ec2-user:ec2-user /opt/coffeeshop/ecr-login.sh

# Log installation completion
echo "EC2 instance setup completed for ${environment} environment" > /var/log/user-data.log