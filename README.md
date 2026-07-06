# Contract Compliance Demo — Security Review Package

## Purpose

This repository contains CloudFormation templates and supporting scripts for a blog post demo showcasing **semantic search and highlighting** on contract documents using Amazon OpenSearch Service, Amazon Titan V2 embeddings, and a SageMaker-hosted highlighting model.


---

## CloudFormation Templates

| Template | Description |
|----------|-------------|
| `cfn-templates/neural-search-complete.yaml` | OpenSearch domain, OSI ingestion pipeline, Titan V2 embedding connector, IAM roles, S3 contracts bucket |
| `cfn-templates/integrations_stack.yaml` | SageMaker endpoint for semantic highlighting model, Lambda helpers for OpenSearch ML Commons connector/model registration, IAM roles |

### Deployment Order

1. **Stack 1** — `neural-search-complete.yaml` (creates OpenSearch domain, S3 bucket, ingestion pipeline)
2. **Stack 2** — `integrations_stack.yaml` (creates SageMaker endpoint, registers highlighting model in OpenSearch ML Commons)

---

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/script_1.sh` | Uploads sample contract data to S3 and triggers OSI ingestion |
| `scripts/script_2.sh` | Queries OpenSearch to verify ingested data |
| `scripts/cleanup.sh` | Tears down all stacks and resources |
| `scripts/test-highlighting.sh` | Tests semantic highlighting against the deployed endpoint |
| `scripts/highlight-viewer.html` | Local HTML viewer for highlighting results |

---

## Sample Data

- `sample-data/contracts.json` — Structured contract metadata
- `sample-data/cobranding_agreements.json` — Co-branding agreement embeddings
- `sample-data/affiliate_agreements.json` — Affiliate agreement embeddings

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
