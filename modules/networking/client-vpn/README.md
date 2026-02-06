# AWS Client VPN Module

This module creates an AWS Client VPN endpoint for secure, direct network access to the ROSA cluster VPC. This is an **optional alternative** to SSM-based access.

## Overview

AWS Client VPN provides an OpenVPN-compatible managed VPN service that allows authorized users to connect directly to the VPC. Unlike SSM port forwarding, VPN provides full network connectivity including DNS resolution.

### Key Features

- **Direct Network Access**: Connect to any resource in the VPC without port forwarding
- **VPC DNS Resolution**: Resolve cluster endpoints (api.*, apps.*) natively
- **No Certificate Warnings**: Proper TLS works because DNS resolves correctly
- **OpenVPN Compatible**: Works with AWS VPN Client, OpenVPN, or Tunnelblick
- **Mutual TLS Authentication**: Certificate-based security
- **Split Tunneling**: Only VPC traffic goes through VPN (configurable)

## When to Use VPN vs SSM

| Use Case | Recommended | Why |
|----------|-------------|-----|
| Quick cluster access | SSM | No setup, instant access |
| Web console browsing | VPN | Native HTTPS, no cert warnings |
| Multiple services | VPN | No need to forward each port |
| Long development sessions | VPN | Persistent connection |
| Scripted/CI access | SSM | Easier automation |
| Cost-sensitive | SSM | Typically cheaper |
| DNS-dependent tools | VPN | Full DNS resolution |

## Cost Analysis: SSM vs VPN

### AWS Client VPN Pricing (GovCloud)

| Component | Cost | Notes |
|-----------|------|-------|
| **Endpoint Association** | ~$0.15/hour per subnet | Charged when VPN is associated with subnets |
| **Connection Hours** | ~$0.05/hour per connection | Charged when clients are connected |
| **Data Transfer** | Standard rates | ~$0.09/GB out |

**Example Monthly Costs (VPN):**

| Scenario | Calculation | Monthly Cost |
|----------|-------------|--------------|
| 1 subnet, 8h/day, 20 days | (1 × $0.15 × 24 × 30) + (8 × 20 × $0.05) | ~$116 |
| 3 subnets, 8h/day, 20 days | (3 × $0.15 × 24 × 30) + (8 × 20 × $0.05) | ~$332 |
| 1 subnet, always-on | (1 × $0.15 × 24 × 30) + (24 × 30 × $0.05) | ~$144 |

### SSM Pricing (GovCloud)

| Component | Cost | Notes |
|-----------|------|-------|
| **Session Manager** | Free | No charge for sessions |
| **Port Forwarding** | Free | No additional charge |
| **EC2 Jump Host** | ~$0.0208/hour (t3.micro) | Always running |
| **EBS Volume** | ~$0.10/GB/month | 20GB = $2/month |
| **CloudWatch Logs** | ~$0.50/GB ingested | Session logs |

**Example Monthly Costs (SSM):**

| Scenario | Calculation | Monthly Cost |
|----------|-------------|--------------|
| t3.micro always-on | ($0.0208 × 24 × 30) + $2 | ~$17 |
| t3.micro 8h/day, 20 days | ($0.0208 × 8 × 20) + $2 | ~$5.30 |

### Cost Comparison Summary

| Access Method | Typical Monthly Cost | Best For |
|---------------|---------------------|----------|
| **SSM Only** | $5-20 | Cost-sensitive, occasional access |
| **VPN (1 subnet)** | $100-150 | Development teams, daily use |
| **VPN (3 subnets, HA)** | $300-350 | Production access, high availability |
| **SSM + VPN** | $120-170 | Flexibility (VPN for dev, SSM for scripts) |

### Recommendation

- **Start with SSM**: It's included, cheap, and works well
- **Add VPN when**: You need native DNS, hate cert warnings, or multiple developers need access
- **Destroy VPN when not needed**: Use terraform to create/destroy on demand

## Usage

### Enable VPN in Root Module

```hcl
module "rosa_govcloud" {
  source = "github.com/supernovae/rosa-classic-govcloud"

  # ... other configuration ...

  # Enable Client VPN (optional)
  create_client_vpn     = true
  vpn_client_cidr_block = "10.100.0.0/22"  # Must not overlap with VPC CIDR
}
```

### Standalone Module Usage

```hcl
module "client_vpn" {
  source = "./modules/client-vpn"

  cluster_name   = "my-rosa-cluster"
  cluster_domain = "my-cluster.abc123.p1.openshiftapps.com"
  vpc_id         = module.vpc.vpc_id
  vpc_cidr       = "10.0.0.0/16"
  subnet_ids     = [module.vpc.private_subnet_ids[0]]  # One subnet for cost savings
  
  # Optional: Use infrastructure KMS key for log encryption
  kms_key_arn = module.kms.infrastructure_kms_key_arn

  tags = {
    Environment = "development"
  }
}
```

### Create VPN On-Demand

To minimize costs, create the VPN only when needed:

```bash
# Create VPN
terraform apply -target=module.client_vpn

# Use VPN for development...

# Destroy VPN when done
terraform destroy -target=module.client_vpn
```

> **Timing Note:** AWS Client VPN operations are slow:
> - **Create:** 5-15 minutes (endpoint creation + subnet association)
> - **Destroy:** 5-15 minutes (must disassociate subnets before deletion)
>
> Plan accordingly - this is an AWS limitation, not a Terraform issue.

## Connecting to the VPN

### 1. Install VPN Client

**AWS VPN Client (Recommended):**
- Download: https://aws.amazon.com/vpn/client-vpn-download/
- Available for Windows, macOS, Linux

**OpenVPN:**
```bash
# macOS
brew install openvpn

# Ubuntu/Debian
sudo apt install openvpn

# RHEL/CentOS
sudo dnf install openvpn
```

### 2. Import Configuration

After `terraform apply`, find the configuration file:

```bash
ls output/*.ovpn
# output/my-cluster-vpn-client.ovpn
```

**AWS VPN Client:**
1. File → Manage Profiles → Add Profile
2. Display Name: "ROSA Cluster"
3. VPN Configuration File: Browse to .ovpn file
4. Click "Add Profile"

**OpenVPN CLI:**
```bash
sudo openvpn --config output/my-cluster-vpn-client.ovpn
```

#### macOS DNS Configuration

Many OpenVPN clients on macOS ignore DHCP-pushed DNS settings. If DNS resolution fails after connecting:

**Option A: Use AWS VPN Client (Recommended)**

The AWS VPN Client handles DNS correctly on macOS. Download from https://aws.amazon.com/vpn/client-vpn-download/

**Option B: Manually Set DNS**

If using OpenVPN or another client, manually configure DNS to use the VPC DNS resolver:

```bash
# Set DNS to VPC resolver (10.0.0.2 for default VPC CIDR 10.0.0.0/16)
sudo networksetup -setdnsservers Wi-Fi 10.0.0.2

# Verify DNS is set
networksetup -getdnsservers Wi-Fi

# Test cluster DNS resolution
nslookup api.my-cluster.abc123.p1.openshiftapps.com

# When done with VPN, restore automatic DNS
sudo networksetup -setdnsservers Wi-Fi empty
```

> **Note**: Replace `Wi-Fi` with your network interface name (e.g., `Ethernet` for wired connections). The VPC DNS resolver is always at the VPC CIDR base + 2 (e.g., `10.0.0.2` for `10.0.0.0/16`).

### 3. Verify Connection

```bash
# Test VPC connectivity (replace with your VPC CIDR)
ping 10.0.0.1

# Test DNS resolution
nslookup api.my-cluster.abc123.p1.openshiftapps.com

# Test cluster API
curl -k https://api.my-cluster.abc123.p1.openshiftapps.com:6443/healthz

# Login with oc
oc login https://api.my-cluster.abc123.p1.openshiftapps.com:6443 -u cluster-admin
```

### 4. Access Web Console

Open in browser (no port forwarding needed!):
```
https://console-openshift-console.apps.my-cluster.abc123.p1.openshiftapps.com
```

## Benefits Over SSM Port Forwarding

### 1. Native DNS Resolution

**With SSM:**
```bash
# Must use localhost with port forwarding
oc login https://localhost:6443  # Cert warning: CN doesn't match

# Browser shows certificate warning for console
https://localhost:8443  # ⚠️ Certificate error
```

**With VPN:**
```bash
# Use actual cluster endpoint
oc login https://api.my-cluster.abc123.p1.openshiftapps.com:6443  # ✓ Valid cert

# Browser works normally
https://console-openshift-console.apps.my-cluster.abc123.p1.openshiftapps.com  # ✓ Valid cert
```

### 2. No Port Forwarding Management

**With SSM:**
```bash
# Need separate terminal for each service
aws ssm start-session --target i-xxx --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["api.cluster"],"portNumber":["6443"],"localPortNumber":["6443"]}'

# Another terminal for console
aws ssm start-session --target i-xxx --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["console.apps.cluster"],"portNumber":["443"],"localPortNumber":["8443"]}'

# Another for OAuth
aws ssm start-session --target i-xxx --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["oauth.apps.cluster"],"portNumber":["443"],"localPortNumber":["8444"]}'
```

**With VPN:**
```bash
# Just connect once
openvpn --config cluster.ovpn
# All services accessible directly
```

### 3. Full Network Access

**With SSM:**
- Only forwarded ports accessible
- Must know all services in advance
- New services require new forwards

**With VPN:**
- Any IP:port in VPC accessible
- Service discovery works
- kubectl port-forward works natively

## Security Considerations

### Authentication

- **Mutual TLS**: Both client and server present certificates
- **Self-signed CA**: Certificates generated by Terraform
- **No shared secrets**: Each deployment has unique certificates

### Certificate Management

Certificates are valid for 365 days by default. To rotate:

```bash
# Taint certificates to force regeneration
terraform taint 'module.client_vpn.tls_private_key.ca'
terraform apply
```

### Network Security

- VPN clients receive IPs from `client_cidr_block`
- Authorization rules limit access to VPC CIDR only
- Split tunneling ensures only VPC traffic uses VPN
- Connection logs stored in CloudWatch (encrypted with KMS)

## Cleanup

### Destroy VPN Only

```bash
terraform destroy -target=module.client_vpn
```

### Manual Cleanup

If terraform destroy fails, clean up manually:

```bash
# List Client VPN endpoints
aws ec2 describe-client-vpn-endpoints \
  --query 'ClientVpnEndpoints[*].[ClientVpnEndpointId,Tags[?Key==`Name`].Value|[0]]' \
  --region us-gov-west-1

# Disassociate subnets first
aws ec2 disassociate-client-vpn-target-network \
  --client-vpn-endpoint-id cvpn-endpoint-xxx \
  --association-id cvpn-assoc-xxx \
  --region us-gov-west-1

# Delete endpoint
aws ec2 delete-client-vpn-endpoint \
  --client-vpn-endpoint-id cvpn-endpoint-xxx \
  --region us-gov-west-1

# Delete ACM certificates
aws acm delete-certificate --certificate-arn arn:aws-us-gov:acm:... --region us-gov-west-1

# Delete CloudWatch log group
aws logs delete-log-group \
  --log-group-name "/aws/vpn/YOUR_CLUSTER_NAME-client-vpn" \
  --region us-gov-west-1
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `cluster_name` | Name of the ROSA cluster | `string` | n/a | yes |
| `cluster_domain` | Domain of the ROSA cluster | `string` | n/a | yes |
| `vpc_id` | VPC ID | `string` | n/a | yes |
| `vpc_cidr` | VPC CIDR block | `string` | n/a | yes |
| `subnet_ids` | Subnet IDs to associate | `list(string)` | n/a | yes |
| `client_cidr_block` | CIDR for VPN clients | `string` | `"10.100.0.0/22"` | no |
| `dns_servers` | DNS servers for VPN clients | `list(string)` | VPC DNS | no |
| `service_cidr` | Kubernetes service CIDR (for auth rule) | `string` | `null` | no |
| `split_tunnel` | Enable split tunneling | `bool` | `true` | no |
| `session_timeout_hours` | Session timeout (8-24) | `number` | `12` | no |
| `certificate_validity_days` | Certificate validity | `number` | `365` | no |
| `certificate_organization` | Organization for certificate subject | `string` | `"ROSA GovCloud"` | no |
| `kms_key_arn` | KMS key for log encryption | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| `vpn_endpoint_id` | Client VPN endpoint ID |
| `vpn_endpoint_arn` | Client VPN endpoint ARN |
| `vpn_endpoint_dns` | VPN endpoint DNS name |
| `security_group_id` | Security group ID for VPN endpoint |
| `log_group_name` | CloudWatch log group name |
| `client_config_path` | Path to .ovpn file |
| `connection_instructions` | How to connect |
| `certificate_expiry` | When certs expire |

## Troubleshooting

### Connection Fails

```bash
# Check VPN endpoint status
aws ec2 describe-client-vpn-endpoints \
  --client-vpn-endpoint-id cvpn-endpoint-xxx \
  --query 'ClientVpnEndpoints[0].Status' \
  --region us-gov-west-1

# Check associations
aws ec2 describe-client-vpn-target-networks \
  --client-vpn-endpoint-id cvpn-endpoint-xxx \
  --region us-gov-west-1
```

### DNS Not Resolving

Ensure VPC DNS is enabled:
```bash
aws ec2 describe-vpc-attribute \
  --vpc-id vpc-xxx \
  --attribute enableDnsSupport \
  --region us-gov-west-1
```

### Certificate Errors

Check certificate validity:
```bash
openssl x509 -in output/my-cluster-vpn-client.crt -noout -dates
```
