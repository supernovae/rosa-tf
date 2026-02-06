# Additional Security Groups for ROSA Clusters

This guide covers attaching additional security groups to ROSA clusters for custom network access control.

## Overview

ROSA clusters support attaching additional AWS security groups to nodes. This allows you to:

- Allow traffic from on-premises networks or peered VPCs
- Restrict egress to specific destinations
- Integrate with existing organizational security policies
- Implement defense-in-depth strategies

> **CRITICAL**: Security groups can only be attached at **cluster creation time**. They cannot be added, removed, or modified after the cluster is deployed. Plan your security group requirements before creating the cluster.

## Supported Configurations

| Cluster Type | Compute (Workers) | Control Plane | Infrastructure |
|--------------|-------------------|---------------|----------------|
| **HCP** | ✅ | ❌ (Red Hat managed) | ❌ (Red Hat managed) |
| **Classic** | ✅ | ✅ | ✅ |

For HCP clusters, the control plane runs in Red Hat's account, so only worker node security groups can be customized.

## Quick Start

### Enable Additional Security Groups

Add to your `tfvars` file:

```hcl
# Enable the feature
additional_security_groups_enabled = true

# Option 1: Use the intra-VPC template (allows all VPC traffic)
use_intra_vpc_security_group_template = true

# Option 2: Define custom rules
compute_security_group_rules = {
  ingress = [
    {
      description = "Allow HTTPS from corporate network"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["10.100.0.0/16"]
    }
  ]
  egress = []
}

# Option 3: Use existing security groups
existing_compute_security_group_ids = ["sg-abc123", "sg-def456"]
```

## Configuration Options

### Intra-VPC Template

The intra-VPC template creates security groups allowing all traffic within the VPC CIDR:

```hcl
additional_security_groups_enabled    = true
use_intra_vpc_security_group_template = true
```

This creates rules allowing:
- All TCP traffic (ports 0-65535) from VPC CIDR
- All UDP traffic (ports 0-65535) from VPC CIDR  
- All ICMP traffic from VPC CIDR

> **WARNING**: This template creates permissive rules. It's useful for development but consider more restrictive rules for production environments.

### Custom Security Group Rules

Define specific ingress/egress rules for each node type:

```hcl
# Compute (worker) nodes
compute_security_group_rules = {
  ingress = [
    {
      description = "Allow HTTPS from corporate network"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["10.100.0.0/16"]
    },
    {
      description = "Allow SSH from bastion"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["10.0.1.0/24"]
    }
  ]
  egress = [
    {
      description = "Allow HTTPS to internet"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

# Control plane nodes (Classic only)
control_plane_security_group_rules = {
  ingress = [
    {
      description = "Allow API access from monitoring"
      from_port   = 6443
      to_port     = 6443
      protocol    = "tcp"
      cidr_blocks = ["10.200.0.0/16"]
    }
  ]
  egress = []
}

# Infrastructure nodes (Classic only)
infra_security_group_rules = {
  ingress = [
    {
      description = "Allow router traffic from corporate LB"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["10.200.0.0/16"]
    }
  ]
  egress = []
}
```

### Using Existing Security Groups

Attach pre-created security groups:

```hcl
additional_security_groups_enabled = true

# For all cluster types
existing_compute_security_group_ids = ["sg-abc123", "sg-def456"]

# Classic only
existing_control_plane_security_group_ids = ["sg-controlplane1"]
existing_infra_security_group_ids         = ["sg-infra1"]
```

### Combined Approach

You can combine all options - existing SGs, custom rules, and the intra-VPC template:

```hcl
additional_security_groups_enabled    = true
use_intra_vpc_security_group_template = true

# Add existing SGs
existing_compute_security_group_ids = ["sg-monitoring123"]

# Add custom rules (creates additional SG)
compute_security_group_rules = {
  ingress = [
    {
      description = "Custom rule for metrics"
      from_port   = 9090
      to_port     = 9090
      protocol    = "tcp"
      cidr_blocks = ["10.200.0.0/16"]
    }
  ]
  egress = []
}
```

## Common Use Cases

### Allow Traffic from On-Premises Network

```hcl
additional_security_groups_enabled = true

compute_security_group_rules = {
  ingress = [
    {
      description = "Allow all traffic from on-prem"
      from_port   = 0
      to_port     = 65535
      protocol    = "tcp"
      cidr_blocks = ["10.100.0.0/8"]  # Your on-prem CIDR
    }
  ]
  egress = []
}
```

### Restrict Egress to Specific Destinations

```hcl
additional_security_groups_enabled = true

compute_security_group_rules = {
  ingress = []
  egress = [
    {
      description = "Allow HTTPS to approved endpoints only"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["52.94.0.0/16", "3.0.0.0/8"]  # AWS endpoints
    },
    {
      description = "Allow DNS"
      from_port   = 53
      to_port     = 53
      protocol    = "udp"
      cidr_blocks = ["10.0.0.0/16"]
    }
  ]
}
```

### Allow Access from Peered VPC

```hcl
additional_security_groups_enabled = true

compute_security_group_rules = {
  ingress = [
    {
      description = "Allow traffic from peered VPC"
      from_port   = 0
      to_port     = 65535
      protocol    = "-1"  # All protocols
      cidr_blocks = ["172.16.0.0/16"]  # Peered VPC CIDR
    }
  ]
  egress = []
}
```

### Classic: Restrict API Access

```hcl
additional_security_groups_enabled = true

control_plane_security_group_rules = {
  ingress = [
    {
      description = "Allow API access from jump host only"
      from_port   = 6443
      to_port     = 6443
      protocol    = "tcp"
      cidr_blocks = ["10.0.1.0/24"]  # Jump host subnet
    }
  ]
  egress = []
}
```

## Rule Schema Reference

Each rule object supports:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `description` | string | Yes | Human-readable description |
| `from_port` | number | Yes | Start of port range (use -1 for ICMP) |
| `to_port` | number | Yes | End of port range (use -1 for ICMP) |
| `protocol` | string | Yes | Protocol: `tcp`, `udp`, `icmp`, or `-1` for all |
| `cidr_blocks` | list(string) | No | List of CIDR blocks |
| `security_groups` | list(string) | No | List of source security group IDs |
| `self` | bool | No | Allow traffic from the same SG |

## Troubleshooting

### Security Groups Not Taking Effect

**Symptom**: Traffic is blocked despite security group rules.

**Diagnosis**:
```bash
# List security groups attached to cluster nodes
aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/<cluster-name>,Values=owned" \
  --query 'Reservations[*].Instances[*].[InstanceId,SecurityGroups[*].GroupId]' \
  --output table

# Verify your additional SG is in the list
aws ec2 describe-security-groups --group-ids sg-abc123
```

**Resolution**:
- Verify the security group was created in the correct VPC
- Check that the security group rules are correct
- Ensure traffic isn't blocked by Network ACLs

### "Cannot modify security groups" Error

**Symptom**: Error when trying to add security groups to existing cluster.

**Cause**: Security groups can only be attached at cluster creation time.

**Resolution**:
- Security groups cannot be added after cluster creation
- To add new security groups, you must destroy and recreate the cluster
- For existing clusters, consider using Network Policies instead

### Rules Not Matching Expected Behavior

**Symptom**: Traffic allowed/denied unexpectedly.

**Diagnosis**:
```bash
# Check effective security group rules
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=sg-abc123"

# Test connectivity from within the cluster
oc debug node/<node-name> -- chroot /host curl -v <target>
```

**Common issues**:
- Egress rules are evaluated separately from ingress
- Protocol must match exactly (`tcp` vs `-1`)
- CIDR blocks must cover the actual source IP

### Classic: Control Plane Not Accessible

**Symptom**: Cannot reach API server from expected network.

**Diagnosis**:
```bash
# Check control plane security groups
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*master*" \
            "Name=tag:kubernetes.io/cluster/<cluster>,Values=owned" \
  --query 'Reservations[*].Instances[*].SecurityGroups[*].GroupId'
```

**Resolution**:
- Verify `control_plane_security_group_rules` includes the required CIDR
- Port 6443 must be open for API access
- Check that source network can route to the VPC

## Security Best Practices

1. **Principle of Least Privilege**: Only allow necessary traffic
2. **Document Rules**: Use descriptive names for audit trails
3. **Avoid Wildcards**: Be specific about ports and protocols
4. **Review Regularly**: Audit security groups periodically
5. **Test Before Production**: Validate rules in dev environments

## Related Documentation

- [AWS Security Groups Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html)
- [ROSA Networking Guide](https://docs.openshift.com/rosa/networking/rosa-network-config.html)
- [OpenShift Network Policies](https://docs.openshift.com/container-platform/latest/networking/network_policy/about-network-policy.html)
