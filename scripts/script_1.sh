#!/bin/bash
# Post-deploy setup for OpenSearch Semantic Search demo
# Run this after Stack 1 (os-demo-search) is CREATE_COMPLETE
set -euo pipefail

STACK_NAME="${1:-os-demo-search}"
REGION="${2:-us-east-1}"

echo "=== Reading Stack 1 outputs ==="
get_output() { aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }

DOMAIN_ENDPOINT=$(get_output DomainEndpoint)
MASTER_ROLE=$(get_output DomainMasterRoleArn)
OSI_ROLE=$(get_output OSIPipelineRoleArn)
ML_ROLE=$(get_output MLCommonsRoleArn)
BEDROCK_ROLE=$(get_output BedrockConnectorRoleArn)
BUCKET=$(get_output ContractsBucketName)

echo "Domain: $DOMAIN_ENDPOINT"
echo "Master Role: $MASTER_ROLE"
echo "Bedrock Connector Role: $BEDROCK_ROLE"

# Step 1: Add PassRole permission for Bedrock connector
echo -e "\n=== Step 1: Adding PassRole permission ==="
MASTER_ROLE_NAME=$(echo "$MASTER_ROLE" | awk -F'/' '{print $2}')
aws iam put-role-policy --role-name "$MASTER_ROLE_NAME" --policy-name PassBedrockConnectorRole \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"iam:PassRole\",\"Resource\":\"$BEDROCK_ROLE\"}]}" \
  --region "$REGION"
echo "  Done"
echo "  Waiting for IAM propagation..."
sleep 15

# Step 2: Map roles, create connector, model, pipeline, index
echo -e "\n=== Step 2: Configuring OpenSearch domain ==="
python3 - "$DOMAIN_ENDPOINT" "$MASTER_ROLE" "$OSI_ROLE" "$ML_ROLE" "$BEDROCK_ROLE" "$REGION" <<'PYEOF'
import sys, json, boto3, time
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
import urllib3
http = urllib3.PoolManager(cert_reqs='CERT_REQUIRED')

endpoint, master_role, osi_role, ml_role, bedrock_role, region = sys.argv[1:7]

sts = boto3.client('sts')
c = sts.assume_role(RoleArn=master_role, RoleSessionName='setup')['Credentials']
session = boto3.Session(aws_access_key_id=c['AccessKeyId'],
    aws_secret_access_key=c['SecretAccessKey'],
    aws_session_token=c['SessionToken'])
creds = session.get_credentials()

def req(method, path, body=None, ignore_404=False):
    url = f"{endpoint}{path}"
    r = AWSRequest(method=method, url=url, data=body, headers={'Content-Type': 'application/json'})
    SigV4Auth(creds, 'es', region).add_auth(r)
    resp = http.request(method, url, body=body, headers=dict(r.headers))
    data = json.loads(resp.data.decode())
    print(f"  {method} {path} -> {resp.status}")
    if resp.status >= 400:
        if ignore_404 and resp.status == 404:
            return data
        raise RuntimeError(f"OpenSearch API error {resp.status} on {method} {path}: {data}")
    return data

# Map roles to all_access and ml_full_access
roles = [master_role, osi_role, ml_role]
mapping = json.dumps({"backend_roles": roles, "hosts": [], "users": []})
print("Mapping all_access...")
req('PUT', '/_plugins/_security/api/rolesmapping/all_access', mapping)
print("Mapping ml_full_access...")
req('PUT', '/_plugins/_security/api/rolesmapping/ml_full_access', mapping)

# Create Bedrock connector
print("\nCreating Bedrock Titan V2 connector...")
result = req('POST', '/_plugins/_ml/connectors/_create', json.dumps({
    'name': 'Bedrock Titan Embed V2', 'version': '1', 'protocol': 'aws_sigv4',
    'parameters': {'region': region, 'service_name': 'bedrock', 'model': 'amazon.titan-embed-text-v2:0'},
    'credential': {'roleArn': bedrock_role},
    'actions': [{'action_type': 'predict', 'method': 'POST',
        'url': f'https://bedrock-runtime.{region}.amazonaws.com/model/amazon.titan-embed-text-v2:0/invoke',
        'headers': {'content-type': 'application/json'},
        'request_body': '{"inputText": "${parameters.inputText}"}',
        'pre_process_function': 'connector.pre_process.bedrock.embedding',
        'post_process_function': 'connector.post_process.bedrock.embedding'}]
}))
connector_id = result['connector_id']
print(f"  Connector ID: {connector_id}")

# Register and deploy embedding model
print("\nRegistering embedding model...")
result = req('POST', '/_plugins/_ml/models/_register', json.dumps({
    'name': 'Titan Embed V2', 'function_name': 'remote', 'connector_id': connector_id}))
task_id = result['task_id']
time.sleep(10)
task = req('GET', f'/_plugins/_ml/tasks/{task_id}')
model_id = task['model_id']
print(f"  Model ID: {model_id}")

print("Deploying embedding model...")
req('POST', f'/_plugins/_ml/models/{model_id}/_deploy')
time.sleep(10)

# Create ingest pipeline
print("\nCreating embedding ingest pipeline...")
req('PUT', '/_ingest/pipeline/embedding-pipeline', json.dumps({
    'description': 'Auto-generate embeddings via Bedrock Titan V2',
    'processors': [{'text_embedding': {'model_id': model_id, 'field_map': {'content': 'content_embedding'}}}]
}))

# Delete existing index if present, create with correct mapping + pipeline
print("\nCreating contracts index with k-NN and ingest pipeline...")
req('DELETE', '/contracts', ignore_404=True)
req('PUT', '/contracts', json.dumps({
    'settings': {'index': {'knn': True, 'default_pipeline': 'embedding-pipeline'}},
    'mappings': {'properties': {
        'content': {'type': 'text'},
        'content_embedding': {'type': 'knn_vector', 'dimension': 1024,
            'method': {'name': 'hnsw', 'engine': 'faiss', 'space_type': 'l2'}},
        'doc_id': {'type': 'keyword'}, 'title': {'type': 'text'}, 'category': {'type': 'keyword'}
    }}
}))

print(f"\nSetup complete. Embedding model ID: {model_id}")
PYEOF

# Step 3: Index sample data from local repo into OpenSearch
echo -e "\n=== Step 3: Indexing sample data from sample-data/ ==="
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$(cd "$SCRIPT_DIR/../sample-data" && pwd)"

python3 - "$DOMAIN_ENDPOINT" "$MASTER_ROLE" "$REGION" "$DATA_DIR" <<'PYEOF'
import sys, json, os, boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
import urllib3
http = urllib3.PoolManager(cert_reqs='CERT_REQUIRED')

endpoint, master_role, region, data_dir = sys.argv[1:5]

sts = boto3.client('sts')
c = sts.assume_role(RoleArn=master_role, RoleSessionName='ingest')['Credentials']
session = boto3.Session(aws_access_key_id=c['AccessKeyId'],
    aws_secret_access_key=c['SecretAccessKey'],
    aws_session_token=c['SessionToken'])
creds = session.get_credentials()

def req(method, path, body=None):
    url = f"{endpoint}{path}"
    r = AWSRequest(method=method, url=url, data=body, headers={'Content-Type': 'application/json'})
    SigV4Auth(creds, 'es', region).add_auth(r)
    resp = http.request(method, url, body=body, headers=dict(r.headers))
    data = json.loads(resp.data.decode())
    if resp.status >= 400:
        raise RuntimeError(f"OpenSearch API error {resp.status} on {method} {path}: {data}")
    return data

json_files = ['contracts.json']

total = 0
for filename in json_files:
    filepath = os.path.join(data_dir, filename)
    if not os.path.exists(filepath):
        print(f"  ⚠️ Skipping {filename} — not found at {filepath}")
        continue
    with open(filepath) as f:
        data = json.load(f)
    docs = data if isinstance(data, list) else [data]
    for doc in docs:
        req('POST', '/contracts/_doc', json.dumps(doc))
        total += 1
    print(f"  Indexed {len(docs)} docs from {filename}")

import time; time.sleep(3)
req('POST', '/contracts/_refresh')
count = req('GET', '/contracts/_count')
print(f"\n  Total documents indexed: {count['count']}")
PYEOF

# Step 4: Verify
echo -e "\n=== Step 4: Verifying ==="
QUERY_FN=$(get_output QueryFunctionName)
aws lambda invoke --function-name "$QUERY_FN" --region "$REGION" \
    --payload '{"query":"termination rights","type":"neural","k":3}' \
    --cli-binary-format raw-in-base64-out /tmp/verify.json > /dev/null 2>&1
python3 -c "
import json
r = json.load(open('/tmp/verify.json'))
hits = r['body']['hits']['total']['value']
print(f'  Neural search hits: {hits}')
if hits > 0:
    print(f'  Top score: {r[\"body\"][\"hits\"][\"hits\"][0][\"_score\"]:.4f}')
    print('  ✅ Neural search working!')
else:
    print('  ❌ No results. Check embedding model deployment.')
"

echo -e "\n=== Script 1 complete! ==="
echo "Next: Deploy Stack 2 (integrations_stack.yaml) with:"
echo "  AmazonOpenSearchEndpoint: $DOMAIN_ENDPOINT"
echo "  LambdaInvokeOpenSearchMLCommonsRoleName: LambdaInvokeOpenSearchMLCommonsRole-$STACK_NAME"
