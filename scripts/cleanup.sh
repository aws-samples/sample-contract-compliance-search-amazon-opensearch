#!/bin/bash
# Cleanup all demo resources
set -euo pipefail

STACK1="${1:-os-demo-search}"
STACK2="${2:-os-demo-highlighting}"
REGION="${3:-us-east-1}"

echo "=== Cleaning up demo resources ==="

# Delete Stack 2 first (depends on Stack 1 resources)
echo -e "\n--- Deleting Stack 2: $STACK2 ---"
if aws cloudformation describe-stacks --stack-name "$STACK2" --region "$REGION" > /dev/null 2>&1; then
    aws cloudformation delete-stack --stack-name "$STACK2" --region "$REGION"
    echo "  Waiting for Stack 2 deletion..."
    aws cloudformation wait stack-delete-complete --stack-name "$STACK2" --region "$REGION" 2>/dev/null || true
    echo "  Stack 2 deleted."
else
    echo "  Stack 2 not found, skipping."
fi

# Empty the contracts bucket before deleting Stack 1
echo -e "\n--- Emptying contracts bucket ---"
BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK1" --region "$REGION" --query "Stacks[0].Outputs[?OutputKey=='ContractsBucketName'].OutputValue" --output text 2>/dev/null || echo "")
if [ -n "$BUCKET" ] && [ "$BUCKET" != "None" ]; then
    aws s3 rm "s3://$BUCKET" --recursive --region "$REGION" 2>/dev/null || true
    echo "  Bucket emptied."
fi

# Clean up the S3 bucket created by Stack 2's helper Lambda
ACCT=$(aws sts get-caller-identity --query Account --output text)
HIGHLIGHT_BUCKET="opensearch-cfn-semantic-highlighting-${REGION}-${ACCT}"
echo -e "\n--- Cleaning highlighting bucket: $HIGHLIGHT_BUCKET ---"
aws s3 rm "s3://$HIGHLIGHT_BUCKET" --recursive --region "$REGION" 2>/dev/null || true
aws s3 rb "s3://$HIGHLIGHT_BUCKET" --region "$REGION" 2>/dev/null || true

# Delete Stack 1
echo -e "\n--- Deleting Stack 1: $STACK1 ---"
if aws cloudformation describe-stacks --stack-name "$STACK1" --region "$REGION" > /dev/null 2>&1; then
    aws cloudformation delete-stack --stack-name "$STACK1" --region "$REGION"
    echo "  Waiting for Stack 1 deletion..."
    aws cloudformation wait stack-delete-complete --stack-name "$STACK1" --region "$REGION" 2>/dev/null || true
    echo "  Stack 1 deleted."
else
    echo "  Stack 1 not found, skipping."
fi

# Clean up CloudWatch log groups
echo -e "\n--- Cleaning up log groups ---"
for prefix in "/aws/lambda/os-demo" "/aws/vendedlogs/os-demo"; do
    for lg in $(aws logs describe-log-groups --log-group-name-prefix "$prefix" --region "$REGION" --query 'logGroups[*].logGroupName' --output text 2>/dev/null); do
        aws logs delete-log-group --log-group-name "$lg" --region "$REGION" 2>/dev/null || true
        echo "  Deleted: $lg"
    done
done

echo -e "\n=== Cleanup complete ==="
