#!/bin/bash
# Deploy the OpenSearch Semantic Search & Highlighting demo
# Usage: ./deploy.sh [region]
set -euo pipefail

REGION="${1:-us-east-1}"
STACK1="os-demo-search"
STACK2="os-demo-highlighting"

echo "=== Deploying OpenSearch Semantic Highlighting Demo ==="
echo "Region: $REGION"
echo ""

# Step 1: Deploy Stack 1 (OpenSearch domain, S3, OSI pipeline, embeddings)
echo "=== Step 1/4: Deploying Stack 1 ($STACK1) ==="
aws cloudformation deploy \
  --template-file cfn-templates/os-demo-search.yaml \
  --stack-name "$STACK1" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$REGION" \
  --parameter-overrides StackPrefix=os-demo SourceS3Bucket=not-used

echo "  Waiting for stack to complete..."
if ! aws cloudformation wait stack-create-complete --stack-name "$STACK1" --region "$REGION" 2>/dev/null; then
  STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK1" --region "$REGION" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "UNKNOWN")
  if [[ "$STATUS" != *"COMPLETE"* ]]; then
    echo "  ❌ Stack 1 failed (status: $STATUS). Check CloudFormation console for details."
    exit 1
  fi
fi
echo "  ✅ Stack 1 deployed"

# Step 2: Run post-deploy setup (connector, model, ingest data)
echo ""
echo "=== Step 2/4: Running post-deploy setup (script_1.sh) ==="
bash scripts/script_1.sh "$STACK1" "$REGION"

# Step 3: Deploy Stack 2 (SageMaker endpoint, highlighting model)
echo ""
echo "=== Step 3/4: Deploying Stack 2 ($STACK2) ==="
DOMAIN_ENDPOINT=$(aws cloudformation describe-stacks --stack-name "$STACK1" --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`DomainEndpoint`].OutputValue' --output text)
LAMBDA_ROLE_NAME=$(aws cloudformation describe-stacks --stack-name "$STACK1" --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`LambdaInvokeRoleName`].OutputValue' --output text)

aws cloudformation deploy \
  --template-file cfn-templates/os-demo-highlighting.yaml \
  --stack-name "$STACK2" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$REGION" \
  --parameter-overrides \
    AmazonOpenSearchEndpoint="$DOMAIN_ENDPOINT" \
    LambdaInvokeOpenSearchMLCommonsRoleName="$LAMBDA_ROLE_NAME"

echo "  Waiting for stack to complete (SageMaker endpoint ~10 min)..."
if ! aws cloudformation wait stack-create-complete --stack-name "$STACK2" --region "$REGION" 2>/dev/null; then
  STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK2" --region "$REGION" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "UNKNOWN")
  if [[ "$STATUS" != *"COMPLETE"* ]]; then
    echo "  ❌ Stack 2 failed (status: $STATUS). Check CloudFormation console for details."
    exit 1
  fi
fi
echo "  ✅ Stack 2 deployed"

# Step 4: Deploy highlighting model and verify
echo ""
echo "=== Step 4/4: Deploying highlighting model (script_2.sh) ==="
bash scripts/script_2.sh "$STACK1" "$STACK2" "$REGION"

echo ""
echo "=== ✅ Deployment complete! ==="
echo ""
echo "Test with:"
echo "  FUNC=\$(aws cloudformation describe-stacks --stack-name $STACK1 --region $REGION --query 'Stacks[0].Outputs[?OutputKey==\`QueryFunctionName\`].OutputValue' --output text)"
echo "  aws lambda invoke --function-name \$FUNC --region $REGION --payload '{\"query\":\"termination rights\",\"type\":\"neural\",\"k\":3}' --cli-binary-format raw-in-base64-out /tmp/test.json && cat /tmp/test.json | python3 -m json.tool"
echo ""
echo "Clean up with:"
echo "  bash scripts/cleanup.sh $REGION"
