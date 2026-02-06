# OADP Layer - Backup and Restore for ROSA

This layer installs and configures OpenShift API for Data Protection (OADP) for backing up and restoring **user workloads** on ROSA clusters.

## Important: Managed Service Context

ROSA is a **managed service** where Red Hat and AWS handle platform operations. OADP on ROSA is designed for **user application data**, not platform components.

### What OADP Backs Up (Your Responsibility)

- Application deployments, services, configmaps, secrets
- Persistent volume data (via CSI snapshots)
- Custom resources and operators you install
- Namespaces and RBAC you create

### What OADP Does NOT Back Up (Managed by Red Hat/AWS)

- Control plane (etcd, API server, controllers)
- OpenShift system operators and configurations
- Node configurations and machine sets
- Cluster infrastructure (VPC, subnets, IAM)

For the complete responsibility matrix, see:
- [ROSA Responsibilities Matrix](https://docs.openshift.com/rosa/rosa_architecture/rosa_policy_service_definition/rosa-policy-responsibility-matrix.html)
- [AWS ROSA Shared Responsibility](https://docs.aws.amazon.com/rosa/latest/userguide/security-shared-responsibility.html)

## Default Backup Behavior

When OADP is enabled, a **nightly backup schedule** is automatically created:

| Setting | Default | Description |
|---------|---------|-------------|
| Schedule | 2:00 AM UTC daily | Cron: `0 2 * * *` |
| Retention | 30 days | Configurable via `oadp_backup_retention_days` |
| Scope | All user namespaces | Excludes `openshift-*`, `kube-*`, `default` |
| Method | CSI snapshots + Kopia | For PVs and filesystem data |

### What Gets Backed Up

The nightly backup includes:
- All namespaces **except** OpenShift system namespaces
- All Kubernetes resources in those namespaces
- Persistent Volume data via CSI snapshots
- Secrets, ConfigMaps, and custom resources

### Excluded Namespaces

System namespaces are automatically excluded:
- `openshift-*` (all OpenShift system namespaces)
- `kube-system`, `kube-public`, `kube-node-lease`
- `default`
- `openshift-adp` (OADP's own namespace)
- `openshift-gitops` (ArgoCD namespace)

## Configuration

### Terraform Variables

```hcl
# Enable OADP layer
enable_layer_oadp = true

# Backup retention (applies to both S3 lifecycle and Velero TTL)
oadp_backup_retention_days = 30  # Default: 30

# Disable automatic backup schedule (OADP installed but no schedule)
# oadp_backup_retention_days = 0
```

### Customizing the Backup Schedule

To modify the backup behavior, edit `schedule-nightly.yaml.tftpl`:

**Change schedule time:**
```yaml
spec:
  # Run at 4:00 AM UTC instead of 2:00 AM
  schedule: "0 4 * * *"
```

**Back up specific namespaces only:**
```yaml
spec:
  template:
    includedNamespaces:
      - my-app-prod
      - my-app-staging
    excludedNamespaces: []  # Clear exclusions
```

**Exclude additional namespaces:**
```yaml
spec:
  template:
    excludedNamespaces:
      - openshift-*
      - kube-*
      - my-test-namespace  # Add your exclusion
```

## Manual Backup Operations

### Create an On-Demand Backup

```bash
# Backup a specific namespace
oc create -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: manual-backup-$(date +%Y%m%d-%H%M)
  namespace: openshift-adp
spec:
  includedNamespaces:
    - my-application
  ttl: 720h  # 30 days
  storageLocation: rosa-dpa-1
EOF
```

### Check Backup Status

```bash
# List all backups
oc get backups -n openshift-adp

# Describe a specific backup
oc describe backup <backup-name> -n openshift-adp

# Check backup logs
oc logs -n openshift-adp -l velero.io/backup-name=<backup-name>
```

### Restore from Backup

```bash
# List available backups
oc get backups -n openshift-adp

# Create a restore
oc create -f - <<EOF
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: restore-$(date +%Y%m%d-%H%M)
  namespace: openshift-adp
spec:
  backupName: <backup-name>
  includedNamespaces:
    - my-application
  restorePVs: true
EOF

# Monitor restore progress
oc get restore -n openshift-adp -w
```

## Storage Configuration

### S3 Bucket

Terraform creates an S3 bucket with:
- Versioning enabled
- Server-side encryption (KMS or AES256)
- Public access blocked
- Lifecycle rules matching retention period

### IAM Role

An IAM role with OIDC trust is created for:
- S3 read/write access
- EC2 snapshot operations
- Scoped to OADP service accounts only

## Troubleshooting

### Check OADP Operator Status

```bash
# Verify operator is running
oc get csv -n openshift-adp | grep oadp

# Check DPA status
oc get dataprotectionapplication -n openshift-adp

# Verify backup location is available
oc get backupstoragelocations -n openshift-adp
```

### Backup Fails with Permission Error

```bash
# Check cloud-credentials secret exists
oc get secret cloud-credentials -n openshift-adp

# Verify IAM role ARN in DPA
oc get dpa rosa-dpa -n openshift-adp -o yaml | grep -A5 credential
```

### Schedule Not Running

```bash
# Check schedule exists
oc get schedules -n openshift-adp

# Verify schedule is enabled
oc describe schedule nightly-user-backup -n openshift-adp
```

## References

- [OADP Documentation](https://docs.openshift.com/rosa/backup_and_restore/application_backup_and_restore/oadp-intro.html)
- [Velero Documentation](https://velero.io/docs/)
- [ROSA Backup Best Practices](https://docs.openshift.com/rosa/backup_and_restore/application_backup_and_restore/backing-up-applications.html)
- [ROSA Responsibility Matrix](https://docs.openshift.com/rosa/rosa_architecture/rosa_policy_service_definition/rosa-policy-responsibility-matrix.html)
