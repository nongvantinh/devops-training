# AWS IAM Permission Error Fix Guide

## Quick Fix (Most Common Issue)

**Problem**: The script creates an IAM user but fails to attach the policy, leaving the user without permissions.

**Solution**: Manually attach the policy using root credentials:

1. **Configure root credentials temporarily**:
   ```bash
   aws configure
   # Enter your root/admin AWS credentials
   ```

2. **Attach the policy to the existing user**:
   ```bash
   # Automatic ARN detection (recommended)
   aws iam attach-user-policy \
     --user-name devops-training-user \
     --policy-arn $(aws iam list-policies --query "Policies[?PolicyName=='DevOpsTrainingTerraformPolicy'].Arn" --output text)
   ```

3. **Configure the region for the devops-training profile**:
   ```bash
   aws configure set region us-west-2 --profile devops-training
   aws configure set output json --profile devops-training
   ```

4. **Test the fix**:
   ```bash
   export AWS_PROFILE=devops-training
   aws sts get-caller-identity
   aws ec2 describe-availability-zones --region us-west-2
   ```

5. **Run the dry-run**:
   ```bash
   export AWS_PROFILE=devops-training
   ./scripts/deploy-infrastructure.sh --dry-run dev
   ```

**Important**: Always set `export AWS_PROFILE=devops-training` before running commands, or the script will use your default AWS credentials instead of the devops-training user.

## Alternative: Use the Automated Script

**Easier Option**: Use the automated setup script:
```bash
./deploy.sh setup-aws
# OR
./scripts/setup-aws-config.sh fix-permissions
```

## Common Permission Issues and Solutions

### 1. ElastiCache Permissions
**Error**: `User is not authorized to perform: elasticache:CreateCacheSubnetGroup`

**Solution**: The IAM policy has been updated to include ElastiCache permissions:
```bash
export AWS_PROFILE=devops-training
./scripts/setup-aws-config.sh fix-permissions
```

### 2. PostgreSQL Version Compatibility
**Error**: `cannot find version 14.9 for postgres`

**Solution**: The RDS module has been updated to use PostgreSQL 14.12 (supported version).

### 3. ECR Repository Conflicts
**Error**: `RepositoryAlreadyExistsException`

**Solution**: The deployment script now lets Terraform manage ECR repositories to avoid conflicts.

## Verification Steps

After applying the fix:

1. **Verify AWS identity**:
   ```bash
   export AWS_PROFILE=devops-training
   aws sts get-caller-identity
   ```

2. **Test EC2 permissions**:
   ```bash
   aws ec2 describe-availability-zones --region us-west-2
   ```

3. **Run Terraform dry-run**:
   ```bash
   ./scripts/deploy-infrastructure.sh --dry-run dev
   ```

**Expected Results:**
- ✅ EC2 DescribeAvailabilityZones: PASS
- ✅ EC2 DescribeImages: PASS  
- ⚠️ S3 Access: FAIL (normal - bucket created during deployment)

## Troubleshooting

### Issue: "User is not authorized to perform: ec2:DescribeAvailabilityZones"
**Cause**: The IAM policy wasn't attached to the user.
**Solution**: Use the quick fix above or run `./scripts/setup-aws-config.sh fix-permissions`

### Issue: "EntityAlreadyExists" when creating user/policy
**Cause**: Resources already exist from previous attempts.
**Solution**: Skip creation and go directly to policy attachment.

### Issue: Root user showing instead of IAM user
**Cause**: AWS CLI is using default profile instead of devops-training profile.
**Solution**: Always export the profile: `export AWS_PROFILE=devops-training`

## Resource Cleanup

When finished with the project:

```bash
# Complete cleanup (stops all billing)
./deploy.sh cleanup

# Check what resources exist
./scripts/cleanup-infrastructure.sh --verify-only

# Emergency cleanup (if script fails)
./scripts/cleanup-infrastructure.sh --force
```

## Need More Help?

- **Use the automated script**: `./deploy.sh setup-aws`
- **Check the step-by-step guide**: [STEP_BY_STEP_GUIDE.md](STEP_BY_STEP_GUIDE.md)
- **Review technical details**: [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)

**💡 Remember**: The automated setup script (`./deploy.sh setup-aws`) handles most of these issues automatically!
