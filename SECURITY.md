# Security Policy

## Disclaimer

This project is provided as sample code for demonstration and educational purposes only.
You should NOT use this in your production accounts, or on production or other critical data,
without additional security hardening. See "Production Hardening Recommendations" below.

## Reporting Vulnerabilities

If you discover a security vulnerability in this project, please report it by emailing
aws-security@amazon.com. Do not report security vulnerabilities through public GitHub issues.

## AWS Services Used

- **Amazon OpenSearch Service** — semantic search domain with k-NN and ML Commons
- **Amazon SageMaker** — hosts semantic highlighting model endpoint
- **AWS Lambda** — query function and CloudFormation custom resource helpers
- **Amazon S3** — stores contract documents and model artifacts
- **Amazon Bedrock** — Titan Text Embeddings V2 for vector generation
- **OpenSearch Ingestion (OSI)** — pipelines data from S3 to OpenSearch
- **AWS IAM** — role-based access control for all service interactions

## Prerequisites and Permissions

To deploy this solution, you need:

- An AWS account with permissions defined in `iam-deployer-policy.json`
- AWS CLI v2 configured with appropriate credentials
- Python 3.12+ (for post-deploy scripts)
- Sufficient service quotas for SageMaker GPU instances (ml.g5.xlarge)

## Known Security Considerations

| Item | Category | Rationale |
|------|----------|-----------|
| `es:*` in OpenSearch access policy | Security Debt | Scoped to specific domain and 5 named principals. Simplifies demo without broad blast radius. |
| SageMaker wildcard resource scope | Security Debt | Dynamic resource names prevent static ARN scoping. Region+account scoped. |
| S3 access logging not enabled | Security Debt | Adds deployment complexity for demo data. Bucket is not publicly accessible. |
| Lambda env vars use AWS-managed KMS | Security Debt | No secrets in env vars — only endpoints and ARNs. |
| CloudFront model download without checksum | Known Risk | Model artifacts are author-controlled. Add checksum verification for production use. |
| DeletionPolicy: Delete | Security Debt | Appropriate for demo — enables clean teardown. Use Retain for production. |

## Production Hardening Recommendations

Before using this code in a production environment:

1. **IAM**: Replace `es:*` with specific actions per role (e.g., `es:ESHttpGet` for query, `es:ESHttpPut` for ingest)
2. **IAM**: Scope SageMaker permissions to `arn:aws:sagemaker:REGION:ACCOUNT:model/semantic-highlighter-*`
3. **Encryption**: Use SSE-KMS with customer-managed key for S3 buckets storing sensitive data
4. **Encryption**: Add `KmsKeyArn` to Lambda function configurations if adding sensitive env vars
5. **S3**: Add bucket policy with `aws:SecureTransport` condition to enforce TLS
6. **S3**: Enable access logging to a dedicated logging bucket
7. **S3**: Enable versioning for data protection
8. **OpenSearch**: Enable audit logging and slow query logs
9. **OpenSearch**: Deploy in VPC for network-level isolation
10. **Supply chain**: Add SHA-256 checksum verification for all external downloads
11. **Deletion protection**: Change DeletionPolicy to Retain for OpenSearch and S3
12. **High availability**: Use multi-AZ OpenSearch cluster (2+ data nodes)
13. **Monitoring**: Add CloudWatch alarms for Lambda errors, OpenSearch cluster health

## Resource Cleanup

To remove all resources deployed by this project:

```bash
scripts/cleanup.sh [region]
```

The cleanup script:
1. Deletes Stack 2 (SageMaker, connector Lambda)
2. Empties the contracts S3 bucket
3. Removes the model staging S3 bucket
4. Deletes Stack 1 (OpenSearch, S3, Lambda, OSI pipeline)
5. Cleans up orphaned CloudWatch log groups

## Dependencies

| Dependency | Source | Notes |
|------------|--------|-------|
| boto3 | AWS SDK (Lambda runtime) | Standard AWS SDK — no known vulnerabilities |
| urllib3 | Python stdlib via Lambda runtime | Used for signed HTTP requests to OpenSearch |
| cfnresponse | CloudFormation helper (Lambda runtime) | Standard CFN custom resource helper |
| Semantic highlighter model | CloudFront CDN (author-hosted) | Downloaded at deploy time — verify integrity for production |

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.
