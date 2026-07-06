#!/bin/bash
# Test semantic highlighting after Stack 2 is deployed
set -euo pipefail

STACK1="${1:-os-demo-search}"
STACK2="${2:-os-demo-highlighting}"
REGION="${3:-us-east-1}"

echo "=== Reading outputs ==="
QUERY_FN=$(aws cloudformation describe-stacks --stack-name "$STACK1" --region "$REGION" --query "Stacks[0].Outputs[?OutputKey=='QueryFunctionName'].OutputValue" --output text)
MODEL_ID=$(aws cloudformation describe-stacks --stack-name "$STACK2" --region "$REGION" --query "Stacks[0].Outputs[?OutputKey=='ModelId'].OutputValue" --output text)

echo "Query Lambda: $QUERY_FN"
echo "Highlight Model ID: $MODEL_ID"

echo -e "\n=== Test 1: Keyword search with semantic highlighting ==="
aws lambda invoke --function-name "$QUERY_FN" --region "$REGION" \
    --payload "{\"query\":\"data breach notification requirements\",\"type\":\"keyword\",\"model_id\":\"$MODEL_ID\",\"k\":3}" \
    --cli-binary-format raw-in-base64-out /tmp/test1.json > /dev/null 2>&1
python3 -c "
import json
r = json.load(open('/tmp/test1.json'))
b = r.get('body', {})
print(f'Status: {r.get(\"statusCode\")}')
for i, hit in enumerate(b.get('hits', {}).get('hits', []), 1):
    print(f'\nResult {i} (score: {hit.get(\"_score\", 0):.2f}):')
    hl = hit.get('highlight', {}).get('content', [])
    if hl:
        print('  Semantic highlights:')
        for h in hl[:3]:
            print(f'    ...{h[:200]}...')
    else:
        print('  No highlights returned')
"

echo -e "\n=== Test 2: Neural (hybrid) search with semantic highlighting ==="
aws lambda invoke --function-name "$QUERY_FN" --region "$REGION" \
    --payload "{\"query\":\"what are the payment terms and penalties for late payment\",\"type\":\"neural\",\"model_id\":\"$MODEL_ID\",\"k\":3}" \
    --cli-binary-format raw-in-base64-out /tmp/test2.json > /dev/null 2>&1
python3 -c "
import json
r = json.load(open('/tmp/test2.json'))
b = r.get('body', {})
print(f'Status: {r.get(\"statusCode\")}')
for i, hit in enumerate(b.get('hits', {}).get('hits', []), 1):
    print(f'\nResult {i} (score: {hit.get(\"_score\", 0):.2f}):')
    hl = hit.get('highlight', {}).get('content', [])
    if hl:
        print('  Semantic highlights:')
        for h in hl[:3]:
            print(f'    ...{h[:200]}...')
    else:
        print('  No highlights returned')
"

echo -e "\n=== Test 3: Compare keyword vs semantic highlighting ==="
echo "--- Standard keyword highlighting (no model_id) ---"
aws lambda invoke --function-name "$QUERY_FN" --region "$REGION" \
    --payload '{"query":"termination clause","type":"keyword","k":1}' \
    --cli-binary-format raw-in-base64-out /tmp/test3a.json > /dev/null 2>&1
python3 -c "
import json
r = json.load(open('/tmp/test3a.json'))
for hit in r.get('body',{}).get('hits',{}).get('hits',[])[:1]:
    hl = hit.get('highlight',{}).get('content',['(none)'])
    print(f'  {hl[0][:200]}')
"

echo -e "\n--- Semantic highlighting (with model_id) ---"
aws lambda invoke --function-name "$QUERY_FN" --region "$REGION" \
    --payload "{\"query\":\"termination clause\",\"type\":\"keyword\",\"model_id\":\"$MODEL_ID\",\"k\":1}" \
    --cli-binary-format raw-in-base64-out /tmp/test3b.json > /dev/null 2>&1
python3 -c "
import json
r = json.load(open('/tmp/test3b.json'))
for hit in r.get('body',{}).get('hits',{}).get('hits',[])[:1]:
    hl = hit.get('highlight',{}).get('content',['(none)'])
    print(f'  {hl[0][:200]}')
"

echo -e "\n=== All tests complete ==="
