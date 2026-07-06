#!/bin/bash
# Creates the minimum-privilege IAM role for deploying and running this solution.
# Run this BEFORE using Claude CLI for deployment.
set -euo pipefail

ROLE_NAME="${1:-os-demo-deployer-role}"
REGION="${2:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Creating deployer role: $ROLE_NAME ==="

# Create trust policy for current user/role
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"AWS": "$CALLER_ARN"},
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

# Create role
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document "$TRUST_POLICY" \
  --description "Minimum-privilege role for deploying the OpenSearch semantic search demo" \
  --region "$REGION" > /dev/null

# Attach inline policy
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "os-demo-deploy-policy" \
  --policy-document "file://${SCRIPT_DIR}/../iam-deployer-policy.json" \
  --region "$REGION"

echo "  Role ARN: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo ""
echo "=== Export for Claude CLI ==="
echo "export OS_DEMO_DEPLOYER_ROLE=arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo "export AWS_DEFAULT_REGION=$REGION"
echo ""
echo "=== Next: Use Claude CLI ==="
echo "claude \"Deploy the OpenSearch semantic search demo using the instructions in README.md. Use region $REGION.\""
