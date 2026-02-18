# NetApp Storage (FSx ONTAP + Astra Trident)

Provisions AWS FSx for NetApp ONTAP and configures Astra Trident CSI for persistent
storage on ROSA clusters. Provides NFS (RWX), iSCSI (block), and VolumeSnapshot
capabilities as a GitOps layer.

## Architecture

```
┌───────────────────────────────────────────────────────────┐
│  AWS Infrastructure (this module)                         │
│  ┌──────────────────┐  ┌───────────────────────────────┐  │
│  │ FSx ONTAP        │  │ Security Group                │  │
│  │ File System      │  │ 443  (ONTAP mgmt)             │  │
│  │  └─ SVM          │  │ 2049 (NFS)                    │  │
│  │     └─ vsadmin   │  │ 3260 (iSCSI)                  │  │
│  └──────────────────┘  │ 111  (portmapper)             │  │
│                        └───────────────────────────────┘  │
│  ┌──────────────────┐  ┌───────────────────────────────┐  │
│  │ IAM Role (IRSA)  │  │ Dedicated Subnets (optional)  │  │
│  │ trident-csi      │  │ /28 per AZ                    │  │
│  └──────────────────┘  └───────────────────────────────┘  │
└───────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────┐
│  Kubernetes (operator/layer-netapp-storage.tf)            │
│  ┌──────────────────┐  ┌───────────────────────────────┐  │
│  │ Trident Operator │  │ TridentOrchestrator CR        │  │
│  │ (OLM)            │  │ (CSI driver deployment)       │  │
│  └──────────────────┘  └───────────────────────────────┘  │
│  ┌──────────────────┐  ┌───────────────────────────────┐  │
│  │ NAS Backend      │  │ SAN Backend                   │  │
│  │ (ontap-nas)      │  │ (ontap-san)                   │  │
│  └──────────────────┘  └───────────────────────────────┘  │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ StorageClasses                                      │  │
│  │  fsx-ontap-nfs-rwx     (NFS, RWX, Dev Spaces)       │  │
│  │  fsx-ontap-iscsi-block (iSCSI, RWO, VMs/DBs)        │  │
│  │  fsx-ontap-snapshots   (VolumeSnapshotClass)        │  │
│  └─────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Set the admin password

```bash
export TF_VAR_fsx_admin_password="YourSecurePassword123"
```

### 2. Enable in gitops tfvars

```hcl
enable_layer_netapp_storage = true
fsx_deployment_type         = "SINGLE_AZ_1"  # or MULTI_AZ_1 for production
```

### 3. Apply (Phase 2)

```bash
terraform apply -var-file="cluster-dev.tfvars" -var-file="gitops-dev.tfvars"
```

## Inputs

| Name                         | Type         | Default          | Description                       |
| ---------------------------- | ------------ | ---------------- | --------------------------------- |
| `cluster_name`               | string       | required         | ROSA cluster name                 |
| `vpc_id`                     | string       | required         | VPC ID                            |
| `vpc_cidr`                   | string       | required         | VPC CIDR for security group rules |
| `private_subnet_ids`         | list(string) | required         | ROSA private subnet IDs           |
| `oidc_endpoint_url`          | string       | required         | OIDC provider endpoint for IRSA   |
| `aws_account_id`             | string       | required         | AWS account ID                    |
| `fsx_admin_password`         | string       | required         | SVM admin password (sensitive)    |
| `deployment_type`            | string       | `"SINGLE_AZ_1"` | `SINGLE_AZ_1` or `MULTI_AZ_1`    |
| `storage_capacity_gb`        | number       | `1024`           | SSD capacity in GiB (min 1024)    |
| `throughput_capacity_mbps`   | number       | `128`            | Throughput: 128-4096 MBps         |
| `create_dedicated_subnets`   | bool         | `false`          | Create isolated FSxN subnets      |
| `dedicated_subnet_cidrs`     | list(string) | `[]`             | CIDRs for dedicated subnets       |
| `kms_key_arn`                | string       | `null`           | KMS key for encryption at rest    |
| `tags`                       | map(string)  | `{}`             | Resource tags                     |

## Outputs

| Name                      | Description                       |
| ------------------------- | --------------------------------- |
| `filesystem_id`           | FSx ONTAP file system ID          |
| `filesystem_dns_name`     | Management endpoint DNS           |
| `svm_id`                  | Storage Virtual Machine ID        |
| `svm_management_endpoint` | SVM management IPs (for Trident)  |
| `svm_nfs_endpoint`        | SVM NFS IPs                       |
| `svm_iscsi_endpoint`      | SVM iSCSI IPs                     |
| `security_group_id`       | FSxN security group ID            |
| `trident_role_arn`        | Trident CSI IAM role ARN          |
| `dedicated_subnet_ids`    | Created subnet IDs (if any)       |

## StorageClasses

### fsx-ontap-nfs-rwx

NFS-based, ReadWriteMany. Optimized for:
- OpenShift Dev Spaces (shared workspace volumes)
- CI/CD shared caches
- Any RWX workload

### fsx-ontap-iscsi-block

iSCSI block, ReadWriteOnce. Optimized for:
- OpenShift Virtualization VM disks
- Database workloads (PostgreSQL, MySQL)
- High-performance single-writer workloads

### fsx-ontap-snapshots

VolumeSnapshotClass using ONTAP's native copy-on-write snapshots:
- Pre-upgrade PVC backups
- Clone volumes for dev/test from production
- OADP integration (labeled `velero.io/csi-volumesnapshot-class: "true"`)

## Subnet Strategy

| Mode                 | `create_dedicated_subnets` | Use Case                                              |
| -------------------- | -------------------------- | ----------------------------------------------------- |
| Co-located (default) | `false`                    | Dev/test. FSxN endpoints share ROSA subnets.          |
| Dedicated            | `true`                     | Production. Isolated /28 subnets for FSxN endpoints.  |

When `create_dedicated_subnets = true`:
- Auto-creates /28 subnets from the last available CIDR blocks in the VPC
- Associates with the same route tables as the ROSA private subnets
- Override with `dedicated_subnet_cidrs` for explicit CIDR control

## GovCloud / FedRAMP

- All ARNs use `data.aws_partition.current.partition` (no hardcoded `arn:aws:`)
- Set `kms_key_arn` for customer-managed encryption (required for FedRAMP)
- Set `netapp_enable_fips = true` for FIPS 140-2 mode (defaults to `true` in GovCloud environments)
- For air-gapped deployments, set `netapp_trident_image` to your mirrored Trident image

## Security

### Credential Management

The SVM admin password is:
- Passed as a sensitive Terraform variable (`fsx_admin_password`)
- Stored in a Kubernetes Secret (`backend-fsx-ontap-secret` in `trident` namespace)
- Present only in encrypted Terraform state (S3 SSE)
- Never logged or printed in plan output

### Advanced: External Secrets Operator

For production environments that require runtime secret rotation without Terraform:

1. Store the password in AWS Secrets Manager
2. Install the External Secrets Operator
3. Create an `ExternalSecret` resource that syncs to the `backend-fsx-ontap-secret` K8s Secret
4. Remove the `fsx_admin_password` variable (Trident reads the K8s Secret directly)

This decouples password rotation from Terraform state.

### Security Group

The FSxN security group allows:
- Ingress from VPC CIDR only (no 0.0.0.0/0)
- Only required ports: 443, 2049, 3260, 111
- Egress to VPC CIDR only
