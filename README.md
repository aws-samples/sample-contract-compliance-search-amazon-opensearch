## Purpose

This repository contains CloudFormation templates and supporting scripts for a blog post demo showcasing **semantic search and highlighting** on contract documents using Amazon OpenSearch Service, Amazon Titan V2 embeddings, and a SageMaker-hosted highlighting model.


---

## CloudFormation Templates

| Template | Description |
|----------|-------------|
| `cfn-templates/os-demo-search.yaml` | OpenSearch domain, OSI ingestion pipeline, Titan V2 embedding connector, IAM roles, S3 contracts bucket |
| `cfn-templates/os-demo-highlighting.yaml` | SageMaker endpoint for semantic highlighting model, Lambda helpers for OpenSearch ML Commons connector/model registration, IAM roles |

### Deployment Order

1. **Stack 1** — `os-demo-search.yaml` (creates OpenSearch domain, S3 bucket, ingestion pipeline)
2. **Stack 2** — `os-demo-highlighting.yaml` (creates SageMaker endpoint, registers highlighting model in OpenSearch ML Commons)

---

 ## Scripts
  
  | Script                             | Purpose                                                                                                              |
  |------------------------------------|---------------------------------------------------------------------------------------------------------------------|
  | `scripts/create-deployer-role.sh`  | Creates a least-privilege IAM deployer role scoped to `os-demo-*` resources (used by the optional Claude Code path) |
  | `scripts/generate_synthetic_contracts.py` | Generates the synthetic contract sample data used by the demo                                               |
  | `scripts/script_1.sh`              | Post-Stack 1: maps roles, creates the Bedrock Titan V2 connector and embedding model and pipeline,index creation|
  | `scripts/script_2.sh`              | Post-Stack 2: deploys the highlighting model, sets `MODEL_ID` on the query Lambda, and verifies highlighting |
  | `scripts/test-highlighting.sh`     | Tests semantic highlighting against the deployed endpoint                                                           |
  | `scripts/cleanup.sh`               | Tears down all stacks and resources                                                                                 |
  | `scripts/highlight-viewer.html`    | Local HTML viewer for highlighting results 

---

## Sample Data

- `sample-data/contracts.json` — Structured contract metadata

---

## Context

- **Type**: Blog post demo (not production deployable)
- **AWS Services**: OpenSearch Service, SageMaker, S3, Lambda, OSI (OpenSearch Ingestion), IAM
- **Region**: Parameterized (default us-east-1)

---

## Disclaimer

This is sample code for demonstration and educational purposes only. You should not use this in your production accounts, or on production or other critical data. You are responsible for testing, securing, and optimizing the content as appropriate for production grade use based on your specific quality control practices and standards. Deploying this content may incur AWS charges for creating or using AWS chargeable resources.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.
