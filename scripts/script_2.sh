#!/bin/bash
# Run after Stack 2 (os-demo-highlighting) is CREATE_COMPLETE
# Deploys the highlighting model and updates the query Lambda with MODEL_ID
set -euo pipefail

SEARCH_STACK="${1:-os-demo-search}"
HIGHLIGHT_STACK="${2:-os-demo-highlighting}"
REGION="${3:-us-east-1}"

echo "=== Reading stack outputs ==="
FUNC=$(aws cloudformation describe-stacks --stack-name "$SEARCH_STACK" --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`QueryFunctionName`].OutputValue' --output text)
DOMAIN=$(aws cloudformation describe-stacks --stack-name "$SEARCH_STACK" --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`DomainEndpoint`].OutputValue' --output text)
MASTER_ROLE=$(aws cloudformation describe-stacks --stack-name "$SEARCH_STACK" --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`DomainMasterRoleArn`].OutputValue' --output text)
MODEL_ID=$(aws cloudformation describe-stacks --stack-name "$HIGHLIGHT_STACK" --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`ModelId`].OutputValue' --output text)

echo "Function: $FUNC"
echo "Domain: $DOMAIN"
echo "Model ID: $MODEL_ID"

# Step 1: Deploy the highlighting model in OpenSearch
echo -e "\n=== Step 1: Deploying highlighting model ==="
python3 -c "
import boto3, json, urllib3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest

domain = '$DOMAIN'
region = '$REGION'
role_arn = '$MASTER_ROLE'
model_id = '$MODEL_ID'

sts = boto3.client('sts')
c = sts.assume_role(RoleArn=role_arn, RoleSessionName='deploy-hl')['Credentials']
session = boto3.Session(aws_access_key_id=c['AccessKeyId'],
    aws_secret_access_key=c['SecretAccessKey'],
    aws_session_token=c['SessionToken'])
creds = session.get_credentials()
http = urllib3.PoolManager(cert_reqs='CERT_REQUIRED')

url = f'{domain}/_plugins/_ml/models/{model_id}/_deploy'
r = AWSRequest(method='POST', url=url, headers={'Content-Type': 'application/json'})
SigV4Auth(creds, 'es', region).add_auth(r)
resp = http.request('POST', url, headers=dict(r.headers))
result = json.loads(resp.data.decode())
print(f'  Deploy status: {result.get(\"status\", result)}')
"

# Step 2: Update query Lambda with MODEL_ID
echo -e "\n=== Step 2: Updating query Lambda ==="
VARS=$(aws lambda get-function-configuration --function-name "$FUNC" --region "$REGION" \
  --query 'Environment.Variables' --output json)
NEW_VARS=$(echo "$VARS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
d['MODEL_ID'] = '$MODEL_ID'
print(','.join(f'{k}={v}' for k, v in d.items()))
")

aws lambda update-function-configuration --function-name "$FUNC" --region "$REGION" \
  --environment "Variables={$NEW_VARS}" > /dev/null

echo "  Done. Lambda updated with MODEL_ID=$MODEL_ID"

# Step 3: Verify semantic highlighting
echo -e "\n=== Step 3: Verifying semantic highlighting ==="
sleep 5
aws lambda invoke --function-name "$FUNC" --region "$REGION" \
  --payload "{\"query\":\"termination rights\",\"type\":\"neural\",\"k\":3,\"model_id\":\"$MODEL_ID\"}" \
  --cli-binary-format raw-in-base64-out /tmp/hl-verify.json > /dev/null 2>&1
python3 -c "
import json
r = json.load(open('/tmp/hl-verify.json'))
shards = r['body']['_shards']
hits = r['body']['hits']['hits']
print(f'  Hits: {r[\"body\"][\"hits\"][\"total\"][\"value\"]} | Failed shards: {shards.get(\"failed\",0)}')
for h in hits[:2]:
    hl = h.get('highlight',{}).get('content',[''])[0]
    has_em = '<em>' in hl
    print(f'  Score: {h[\"_score\"]:.4f} | Semantic highlight: {\"✅\" if has_em else \"⚠️ no <em> tags\"}')
    if has_em:
        # Show the highlighted portion
        import re
        matches = re.findall(r'<em>(.*?)</em>', hl)
        if matches:
            print(f'    Highlighted: <em>{matches[0][:100]}...</em>')
"

echo -e "\n=== Script 2 complete! ==="
echo "Test with: {\"query\":\"termination rights\",\"type\":\"neural\",\"k\":3,\"model_id\":\"$MODEL_ID\"}"
