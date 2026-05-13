# Route53 Resolver Query Logging

Route53 Resolver query logging captures **every DNS query** originating from within a VPC. This is useful for:

- **Security auditing**: Identify unexpected outbound DNS lookups
- **Network dependency mapping**: Understand what internet endpoints a ROSA cluster needs
- **Troubleshooting**: Diagnose DNS resolution failures
- **Compliance**: Meet NIST 800-53 AU-3 (content of audit records) requirements

## How It Works

When enabled, the VPC module creates:

1. A CloudWatch Logs log group (KMS-encrypted)
2. A CloudWatch Logs resource policy allowing Route53 Resolver to write
3. A Route53 Resolver query log configuration
4. An association binding the configuration to the VPC

Every DNS query from any resource in the VPC (EC2 instances, pods, NAT gateways, etc.) is logged to CloudWatch with details including:

- Query name (e.g., `api.openshift.com`)
- Query type (A, AAAA, CNAME, etc.)
- Response code (NOERROR, NXDOMAIN, SERVFAIL)
- Source IP (the ENI making the request)
- VPC ID

## Enabling

Add to your `cluster-*.tfvars`:

```hcl
enable_route53_query_logging = true
```

### Optional Configuration

```hcl
# Custom retention (default: 30 days)
resolver_query_log_retention_days = 14

# Custom log group name (default: /aws/route53resolver/{cluster_name}-vpc)
resolver_query_log_group_name = "/custom/path/my-dns-logs"
```

## Log Group Naming

The default log group name follows the convention:

```
/aws/route53resolver/{cluster_name}-vpc
```

For example, a cluster named `dev-hcp-gov` produces:

```
/aws/route53resolver/dev-hcp-gov-vpc
```

## Querying Logs with CloudWatch Insights

Navigate to **CloudWatch > Logs Insights** in the AWS Console and select the resolver log group.

### All unique domains queried (top 50)

```
fields query_name
| stats count(*) as query_count by query_name
| sort query_count desc
| limit 50
```

### DNS failures (NXDOMAIN, SERVFAIL)

```
fields @timestamp, query_name, rcode, srcaddr
| filter rcode != "NOERROR"
| sort @timestamp desc
| limit 100
```

### Queries to external domains (excluding internal/AWS)

```
fields @timestamp, query_name, query_type, rcode
| filter query_name not like /\.internal$/
| filter query_name not like /\.amazonaws\.com$/
| filter query_name not like /\.compute\.internal$/
| stats count(*) as cnt by query_name
| sort cnt desc
| limit 100
```

### Identify all internet endpoints a cluster accesses

```
fields query_name, query_type
| filter rcode = "NOERROR"
| filter query_name not like /\.internal$/
| filter query_name not like /\.compute\.internal$/
| stats count(*) as cnt by query_name, query_type
| sort cnt desc
```

### Queries from a specific source IP

```
fields @timestamp, query_name, query_type, rcode
| filter srcaddr = "10.0.1.42"
| sort @timestamp desc
| limit 200
```

### Time-based analysis (queries per minute)

```
fields @timestamp, query_name
| stats count(*) as qps by bin(1m)
| sort @timestamp desc
```

## Commercial vs GovCloud

Route53 Resolver query logging works identically in both partitions. The Terraform module automatically handles partition-specific ARN construction using `data.aws_partition.current`.

| Aspect | Commercial | GovCloud |
|--------|-----------|----------|
| ARN prefix | `arn:aws:logs:...` | `arn:aws-us-gov:logs:...` |
| Region | Any region | `us-gov-west-1` or `us-gov-east-1` |
| KMS | Optional | Recommended (FedRAMP) |
| Behavior | Identical | Identical |

## Cost Considerations

Route53 Resolver query logging costs are based on CloudWatch Logs pricing:

- **Ingestion**: ~$0.50/GB ingested
- **Storage**: ~$0.03/GB/month (after retention period, automatically deleted)
- **Queries**: CloudWatch Insights queries are ~$0.005/GB scanned

A typical ROSA cluster generates approximately 1-10 GB/day of DNS query logs depending on workload. For development clusters, a 14-day retention keeps costs minimal (~$5-15/month).

Set `resolver_query_log_retention_days` to control storage costs. Lower values (7-14 days) are appropriate for temporary debugging; higher values (90+ days) for compliance.

## BYO-VPC

When using an existing VPC (`existing_vpc_id` is set), the VPC module is not created and Resolver query logging is **not** managed by this Terraform. You must configure Resolver query logging separately for BYO-VPC deployments.

## Disabling

Set `enable_route53_query_logging = false` in your tfvars and run `terraform apply`. This destroys the log configuration, association, and log group (existing logs are deleted after the retention period or immediately if the log group is removed).

## Relationship to Other Logging

| Feature | What it captures | Scope |
|---------|-----------------|-------|
| **VPC Flow Logs** (`enable_vpc_flow_logs`) | Network traffic metadata (IPs, ports, bytes) | VPC |
| **Route53 Resolver Query Logs** (`enable_route53_query_logging`) | DNS queries (domain names, types, responses) | VPC |
| **Route53 Hosted Zone Query Logs** (`certmanager_enable_query_logging`) | DNS queries to a specific public hosted zone | Hosted Zone |

These are complementary. Flow logs show _where_ traffic goes (IP level), Resolver logs show _what_ names are being resolved (DNS level), and hosted zone logs show inbound queries to your own domains.
