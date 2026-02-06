#------------------------------------------------------------------------------
# ROSA HCP IAM Roles Module
#
# Creates IAM roles for ROSA with Hosted Control Planes (HCP).
# Based on official terraform-rhcs-rosa-hcp module implementation.
#
# IAM Architecture:
#   - Account Roles (3): Shared across clusters, can be created here or discovered
#   - Operator Roles (8): Per-cluster, tied to OIDC config
#   - OIDC Config: Per-cluster
#
# Account Role Modes:
#   1. Create (default): create_account_roles = true
#   2. Discover: create_account_roles = false (auto-discovers by prefix)
#   3. Explicit: create_account_roles = false + provide role ARNs
#
# See docs/IAM-LIFECYCLE.md for architecture details.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "rhcs_info" "current" {}
data "rhcs_hcp_policies" "all_policies" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  path       = coalesce(var.path, "/")

  # Role prefixes
  account_role_prefix  = var.account_role_prefix
  operator_role_prefix = coalesce(var.operator_role_prefix, var.cluster_name)

  # Expected role names (for discovery)
  installer_role_name = "${var.account_role_prefix}-HCP-ROSA-Installer-Role"
  support_role_name   = "${var.account_role_prefix}-HCP-ROSA-Support-Role"
  worker_role_name    = "${var.account_role_prefix}-HCP-ROSA-Worker-Role"
}

#------------------------------------------------------------------------------
# Account Role Discovery
#
# Auto-discover existing account roles by naming convention.
# Roles created via ROSA CLI or environments/account-hcp will be found.
#
# Used for:
# 1. When create_account_roles = false: find existing roles to use
# 2. When create_account_roles = true: detect conflicts before creation
#------------------------------------------------------------------------------

# Check if roles already exist and validate their policies
data "external" "check_existing_roles" {
  count = var.create_account_roles ? 1 : 0

  program = ["bash", "-c", <<-EOF
    # Check if HCP account roles already exist and their policy status
    installer_exists="false"
    support_exists="false"
    worker_exists="false"
    installer_policy_ok="false"
    support_policy_ok="false"
    worker_policy_ok="false"

    # Check installer role
    if aws iam get-role --role-name "${local.installer_role_name}" >/dev/null 2>&1; then
      installer_exists="true"
      # Check if correct policy is attached
      if aws iam list-attached-role-policies --role-name "${local.installer_role_name}" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null | grep -q "ROSAInstallerPolicy"; then
        installer_policy_ok="true"
      fi
    fi

    # Check support role
    if aws iam get-role --role-name "${local.support_role_name}" >/dev/null 2>&1; then
      support_exists="true"
      if aws iam list-attached-role-policies --role-name "${local.support_role_name}" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null | grep -q "ROSASRESupportPolicy"; then
        support_policy_ok="true"
      fi
    fi

    # Check worker role
    if aws iam get-role --role-name "${local.worker_role_name}" >/dev/null 2>&1; then
      worker_exists="true"
      if aws iam list-attached-role-policies --role-name "${local.worker_role_name}" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null | grep -q "ROSAWorkerInstancePolicy"; then
        worker_policy_ok="true"
      fi
    fi

    # Return JSON
    cat <<RESULT
{
  "installer_exists": "$installer_exists",
  "support_exists": "$support_exists",
  "worker_exists": "$worker_exists",
  "installer_policy_ok": "$installer_policy_ok",
  "support_policy_ok": "$support_policy_ok",
  "worker_policy_ok": "$worker_policy_ok"
}
RESULT
  EOF
  ]
}

locals {
  # Check if any roles already exist when trying to create
  existing_roles_detected = var.create_account_roles && try(
    data.external.check_existing_roles[0].result.installer_exists == "true" ||
    data.external.check_existing_roles[0].result.support_exists == "true" ||
    data.external.check_existing_roles[0].result.worker_exists == "true",
    false
  )

  # Check if existing roles have outdated policies
  existing_roles_need_upgrade = var.create_account_roles && local.existing_roles_detected && try(
    (data.external.check_existing_roles[0].result.installer_exists == "true" && data.external.check_existing_roles[0].result.installer_policy_ok != "true") ||
    (data.external.check_existing_roles[0].result.support_exists == "true" && data.external.check_existing_roles[0].result.support_policy_ok != "true") ||
    (data.external.check_existing_roles[0].result.worker_exists == "true" && data.external.check_existing_roles[0].result.worker_policy_ok != "true"),
    false
  )
}

# Try to discover existing installer role (when not creating)
data "aws_iam_role" "installer" {
  count = !var.create_account_roles && var.installer_role_arn == null ? 1 : 0
  name  = local.installer_role_name
}

# Try to discover existing support role (when not creating)
data "aws_iam_role" "support" {
  count = !var.create_account_roles && var.support_role_arn == null ? 1 : 0
  name  = local.support_role_name
}

# Try to discover existing worker role (when not creating)
data "aws_iam_role" "worker" {
  count = !var.create_account_roles && var.worker_role_arn == null ? 1 : 0
  name  = local.worker_role_name
}

#------------------------------------------------------------------------------
# Account Role ARN Resolution
#
# Priority: explicit ARN > discovered > created
#------------------------------------------------------------------------------

locals {
  # Resolve installer role ARN
  installer_role_arn = coalesce(
    var.installer_role_arn,
    try(data.aws_iam_role.installer[0].arn, null),
    try(aws_iam_role.account_role[0].arn, null)
  )

  # Resolve support role ARN
  support_role_arn = coalesce(
    var.support_role_arn,
    try(data.aws_iam_role.support[0].arn, null),
    try(aws_iam_role.account_role[1].arn, null)
  )

  # Resolve worker role ARN
  worker_role_arn = coalesce(
    var.worker_role_arn,
    try(data.aws_iam_role.worker[0].arn, null),
    try(aws_iam_role.account_role[2].arn, null)
  )

  # Check if all roles are available
  roles_available = (
    local.installer_role_arn != null &&
    local.support_role_arn != null &&
    local.worker_role_arn != null
  )
}

#------------------------------------------------------------------------------
# Input Validation
#------------------------------------------------------------------------------

# Check: Account roles already exist when trying to create
check "account_roles_already_exist" {
  assert {
    condition     = !local.existing_roles_detected || local.existing_roles_need_upgrade
    error_message = <<-EOT
      
      ══════════════════════════════════════════════════════════════════════════════
      HCP ACCOUNT ROLES ALREADY EXIST
      ══════════════════════════════════════════════════════════════════════════════
      
      The following roles already exist in this AWS account:
        - ${local.installer_role_name}
        - ${local.support_role_name}  
        - ${local.worker_role_name}
      
      HCP account roles are SHARED across all clusters in an account.
      You should reuse the existing roles instead of creating duplicates.
      
      ┌──────────────────────────────────────────────────────────────────────────┐
      │ FIX: Set create_account_roles = false in your tfvars file               │
      └──────────────────────────────────────────────────────────────────────────┘
      
      # In dev.tfvars (or your tfvars file):
      create_account_roles = false   # Use existing shared roles
      account_role_prefix  = "${var.account_role_prefix}"  # Must match existing roles
      
      See docs/IAM-LIFECYCLE.md for HCP multi-cluster architecture details.
      
      ══════════════════════════════════════════════════════════════════════════════
    EOT
  }
}

# Check: Existing roles have outdated policies
check "account_roles_need_upgrade" {
  assert {
    condition     = !local.existing_roles_need_upgrade
    error_message = <<-EOT
      
      ══════════════════════════════════════════════════════════════════════════════
      HCP ACCOUNT ROLES NEED UPGRADE
      ══════════════════════════════════════════════════════════════════════════════
      
      The existing account roles are missing expected AWS managed policies:
      
      Expected policies:
        - Installer: ROSAInstallerPolicy
        - Support:   ROSASRESupportPolicy
        - Worker:    ROSAWorkerInstancePolicy
      
      This can happen when roles were created with an older ROSA CLI version
      or the policies were manually modified.
      
      ┌──────────────────────────────────────────────────────────────────────────┐
      │ FIX: Upgrade the account roles                                          │
      └──────────────────────────────────────────────────────────────────────────┘
      
      Option 1 - Use ROSA CLI to upgrade:
        rosa upgrade account-roles --hosted-cp --prefix ${var.account_role_prefix}
      
      Option 2 - Delete and recreate via Terraform:
        # First, delete old roles manually or via ROSA CLI:
        rosa delete account-roles --hosted-cp --prefix ${var.account_role_prefix} --yes
        
        # Then run Terraform with create_account_roles = true
      
      Option 3 - Re-run Terraform account layer:
        cd environments/account-hcp
        terraform apply -var-file=account.tfvars
      
      See docs/IAM-LIFECYCLE.md for upgrade procedures.
      
      ══════════════════════════════════════════════════════════════════════════════
    EOT
  }
}

# Check: Account roles don't exist when trying to discover
check "account_roles_exist" {
  assert {
    condition     = var.create_account_roles || local.roles_available
    error_message = <<-EOT
      
      ══════════════════════════════════════════════════════════════════════════════
      HCP ACCOUNT ROLES NOT FOUND
      ══════════════════════════════════════════════════════════════════════════════
      
      HCP clusters require account-level IAM roles that must exist before deployment.
      
      Expected roles (with prefix "${var.account_role_prefix}"):
        - ${local.installer_role_name}
        - ${local.support_role_name}
        - ${local.worker_role_name}
      
      ┌──────────────────────────────────────────────────────────────────────────┐
      │ CREATE THE ACCOUNT ROLES FIRST                                          │
      └──────────────────────────────────────────────────────────────────────────┘
      
      Option 1 - Use Terraform (recommended):
        cd environments/account-hcp
        terraform init
        terraform apply -var-file=commercial.tfvars   # For Commercial AWS
        terraform apply -var-file=govcloud.tfvars     # For GovCloud
      
      Option 2 - Use ROSA CLI:
        rosa create account-roles --hosted-cp --prefix ${var.account_role_prefix} --mode auto
      
      Option 3 - Provide explicit ARNs (if using custom role names):
        installer_role_arn = "arn:aws:iam::ACCOUNT:role/Your-Installer-Role"
        support_role_arn   = "arn:aws:iam::ACCOUNT:role/Your-Support-Role"
        worker_role_arn    = "arn:aws:iam::ACCOUNT:role/Your-Worker-Role"
      
      These roles are shared across all HCP clusters in your AWS account.
      See docs/IAM-LIFECYCLE.md for architecture details.
      
      ══════════════════════════════════════════════════════════════════════════════
    EOT
  }
}

check "oidc_config_validation" {
  assert {
    condition     = var.create_oidc_config || (var.oidc_config_id != null && var.oidc_endpoint_url != null)
    error_message = <<-EOT
      When create_oidc_config = false, both oidc_config_id and oidc_endpoint_url are required.
      
      Obtain these values from:
      - Previous Terraform apply output
      - rosa list oidc-config
      - OpenShift Cluster Manager
    EOT
  }
}

check "unmanaged_oidc_validation" {
  assert {
    condition     = var.managed_oidc || !var.create_oidc_config || (var.oidc_private_key_secret_arn != null && var.installer_role_arn_for_oidc != null)
    error_message = <<-EOT
      Unmanaged OIDC (managed_oidc = false) requires:
      - oidc_private_key_secret_arn: ARN of Secrets Manager secret with private key
      - installer_role_arn_for_oidc: ARN of installer role for OIDC creation
      
      See docs/OIDC.md for setup instructions.
    EOT
  }
}

#------------------------------------------------------------------------------
# OIDC Configuration (Per-Cluster)
#------------------------------------------------------------------------------

locals {
  # OIDC configuration - resolve from created resource or provided variables
  oidc_config_id    = var.create_oidc_config ? rhcs_rosa_oidc_config.this[0].id : var.oidc_config_id
  oidc_endpoint_url = var.create_oidc_config ? rhcs_rosa_oidc_config.this[0].oidc_endpoint_url : var.oidc_endpoint_url
  oidc_thumbprint   = var.create_oidc_config ? rhcs_rosa_oidc_config.this[0].thumbprint : null
}

resource "rhcs_rosa_oidc_config" "this" {
  count = var.create_oidc_config ? 1 : 0

  managed = var.managed_oidc

  # Unmanaged OIDC requires installer role and secret ARN
  installer_role_arn = var.managed_oidc ? null : var.installer_role_arn_for_oidc
  secret_arn         = var.managed_oidc ? null : var.oidc_private_key_secret_arn
}

# Look up existing OIDC provider when not creating new OIDC config
data "aws_iam_openid_connect_provider" "existing" {
  count = var.create_oidc_config ? 0 : 1
  url   = "https://${var.oidc_endpoint_url}"
}

resource "aws_iam_openid_connect_provider" "this" {
  count = var.create_oidc_config ? 1 : 0

  url             = "https://${rhcs_rosa_oidc_config.this[0].oidc_endpoint_url}"
  client_id_list  = ["openshift", "sts.amazonaws.com"]
  thumbprint_list = [rhcs_rosa_oidc_config.this[0].thumbprint]

  tags = merge(var.tags, {
    rosa_managed_policies = true
    rosa_hcp_policies     = true
    red-hat-managed       = true
    rosa_cluster_name     = var.cluster_name
  })
}

#------------------------------------------------------------------------------
# Account Roles (Conditional - only when create_account_roles = true)
#------------------------------------------------------------------------------

locals {
  # Account roles configuration (from official module)
  account_roles_properties = [
    {
      role_name            = "HCP-ROSA-Installer"
      role_type            = "installer"
      policy_arn           = "arn:${local.partition}:iam::aws:policy/service-role/ROSAInstallerPolicy"
      principal_type       = "AWS"
      principal_identifier = "arn:${local.partition}:iam::${data.rhcs_info.current.ocm_aws_account_id}:role/RH-Managed-OpenShift-Installer"
    },
    {
      role_name            = "HCP-ROSA-Support"
      role_type            = "support"
      policy_arn           = "arn:${local.partition}:iam::aws:policy/service-role/ROSASRESupportPolicy"
      principal_type       = "AWS"
      principal_identifier = data.rhcs_hcp_policies.all_policies.account_role_policies["sts_support_rh_sre_role"]
    },
    {
      role_name            = "HCP-ROSA-Worker"
      role_type            = "instance_worker"
      policy_arn           = "arn:${local.partition}:iam::aws:policy/service-role/ROSAWorkerInstancePolicy"
      principal_type       = "Service"
      principal_identifier = "ec2.amazonaws.com"
    },
  ]

  account_roles_count = var.create_account_roles ? length(local.account_roles_properties) : 0
}

# Trust policies for account roles
data "aws_iam_policy_document" "account_trust_policy" {
  count = local.account_roles_count

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = local.account_roles_properties[count.index].principal_type
      identifiers = [local.account_roles_properties[count.index].principal_identifier]
    }
  }
}

# Account roles - only create when create_account_roles = true
resource "aws_iam_role" "account_role" {
  count = local.account_roles_count

  name               = substr("${local.account_role_prefix}-${local.account_roles_properties[count.index].role_name}-Role", 0, 64)
  path               = local.path
  assume_role_policy = data.aws_iam_policy_document.account_trust_policy[count.index].json

  tags = merge(var.tags, {
    red-hat-managed       = true
    rosa_hcp_policies     = true
    rosa_managed_policies = true
    rosa_role_prefix      = local.account_role_prefix
    rosa_role_type        = local.account_roles_properties[count.index].role_type
    rosa_cluster_name     = var.cluster_name
  })
}

resource "aws_iam_role_policy_attachment" "account_role_policy" {
  count = local.account_roles_count

  role       = aws_iam_role.account_role[count.index].name
  policy_arn = local.account_roles_properties[count.index].policy_arn
}

# Worker Instance Profile - only create when creating account roles
resource "aws_iam_instance_profile" "worker" {
  count = var.create_account_roles ? 1 : 0

  name = "${local.account_role_prefix}-HCP-ROSA-Worker-Role"
  role = aws_iam_role.account_role[2].name # Worker is index 2

  tags = merge(var.tags, {
    rosa_managed_policies = true
    rosa_hcp_policies     = true
    rosa_cluster_name     = var.cluster_name
  })
}

#------------------------------------------------------------------------------
# ECR and KMS Policy Architecture Note
#------------------------------------------------------------------------------
#
# ECR Policy:
#   ECR access is NOT managed here because:
#   - Account-level Worker role is shared across clusters
#   - ECR policy should be attached per-machine-pool using the computed
#     instance_profile from rhcs_hcp_machine_pool.aws_node_pool.instance_profile
#   - See modules/cluster/machine-pools-hcp for per-pool ECR attachment
#
# KMS Policy:
#   KMS access is NOT managed via IAM role policies for HCP because:
#   - RHCS handles KMS integration when you pass kms_key_arn to the cluster
#   - KMS key policy (on the key itself) must grant access to operator roles:
#     * kube-system-kube-controller-manager
#     * kube-system-kms-provider  
#     * kube-system-capa-controller-manager
#   - See modules/security/kms for KMS key policy configuration
#   - Reference: https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/install_rosa_with_hcp_clusters/rosa-hcp-creating-cluster-with-aws-kms-key
#
# This differs from ROSA Classic where IAM role policies are required.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Operator Roles (Per-Cluster, always created)
#------------------------------------------------------------------------------

locals {
  operator_roles_properties = [
    {
      operator_name      = "installer-cloud-credentials"
      operator_namespace = "openshift-image-registry"
      policy_arn         = "arn:${local.partition}:iam::aws:policy/service-role/ROSAImageRegistryOperatorPolicy"
      service_accounts   = ["system:serviceaccount:openshift-image-registry:cluster-image-registry-operator", "system:serviceaccount:openshift-image-registry:registry"]
    },
    {
      operator_name      = "cloud-credentials"
      operator_namespace = "openshift-ingress-operator"
      policy_arn         = "arn:${local.partition}:iam::aws:policy/service-role/ROSAIngressOperatorPolicy"
      service_accounts   = ["system:serviceaccount:openshift-ingress-operator:ingress-operator"]
    },
    {
      operator_name      = "ebs-cloud-credentials"
      operator_namespace = "openshift-cluster-csi-drivers"
      policy_arn         = "arn:${local.partition}:iam::aws:policy/service-role/ROSAAmazonEBSCSIDriverOperatorPolicy"
      service_accounts   = ["system:serviceaccount:openshift-cluster-csi-drivers:aws-ebs-csi-driver-operator", "system:serviceaccount:openshift-cluster-csi-drivers:aws-ebs-csi-driver-controller-sa"]
    },
    {
      operator_name      = "cloud-credentials"
      operator_namespace = "openshift-cloud-network-config-controller"
      policy_arn         = "arn:${local.partition}:iam::aws:policy/service-role/ROSACloudNetworkConfigOperatorPolicy"
      service_accounts   = ["system:serviceaccount:openshift-cloud-network-config-controller:cloud-network-config-controller"]
    },
    {
      operator_name      = "kube-controller-manager"
      operator_namespace = "kube-system"
      policy_arn         = "arn:${local.partition}:iam::aws:policy/service-role/ROSAKubeControllerPolicy"
      service_accounts   = ["system:serviceaccount:kube-system:kube-controller-manager"]
    },
    {
      operator_name      = "capa-controller-manager"
      operator_namespace = "kube-system"
      policy_arn         = "arn:${local.partition}:iam::aws:policy/service-role/ROSANodePoolManagementPolicy"
      service_accounts   = ["system:serviceaccount:kube-system:capa-controller-manager"]
    },
    {
      operator_name      = "control-plane-operator"
      operator_namespace = "kube-system"
      policy_arn         = "arn:${local.partition}:iam::aws:policy/service-role/ROSAControlPlaneOperatorPolicy"
      service_accounts   = ["system:serviceaccount:kube-system:control-plane-operator"]
    },
    {
      operator_name      = "kms-provider"
      operator_namespace = "kube-system"
      policy_arn         = "arn:${local.partition}:iam::aws:policy/service-role/ROSAKMSProviderPolicy"
      service_accounts   = ["system:serviceaccount:kube-system:kms-provider"]
    },
  ]
}

data "aws_iam_policy_document" "operator_trust_policy" {
  count = length(local.operator_roles_properties)

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:oidc-provider/${local.oidc_endpoint_url}"]
    }
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "${local.oidc_endpoint_url}:sub"
      values   = local.operator_roles_properties[count.index].service_accounts
    }
  }
}

resource "aws_iam_role" "operator_role" {
  count = length(local.operator_roles_properties)

  name               = substr("${local.operator_role_prefix}-${local.operator_roles_properties[count.index].operator_namespace}-${local.operator_roles_properties[count.index].operator_name}", 0, 64)
  path               = local.path
  assume_role_policy = data.aws_iam_policy_document.operator_trust_policy[count.index].json

  tags = merge(var.tags, {
    rosa_managed_policies = true
    rosa_hcp_policies     = true
    red-hat-managed       = true
    operator_namespace    = local.operator_roles_properties[count.index].operator_namespace
    operator_name         = local.operator_roles_properties[count.index].operator_name
    rosa_cluster_name     = var.cluster_name
  })
}

resource "aws_iam_role_policy_attachment" "operator_role_policy" {
  count = length(local.operator_roles_properties)

  role       = aws_iam_role.operator_role[count.index].name
  policy_arn = local.operator_roles_properties[count.index].policy_arn
}

#------------------------------------------------------------------------------
# Wait for IAM propagation
#------------------------------------------------------------------------------

resource "time_sleep" "iam_propagation" {
  create_duration  = "30s"
  destroy_duration = "10s"

  triggers = {
    oidc_config_id     = local.oidc_config_id
    oidc_provider_arn  = var.create_oidc_config ? aws_iam_openid_connect_provider.this[0].arn : data.aws_iam_openid_connect_provider.existing[0].arn
    installer_role_arn = local.installer_role_arn
    support_role_arn   = local.support_role_arn
    worker_role_arn    = local.worker_role_arn
    operator_role_arns = jsonencode([for r in aws_iam_role.operator_role : r.arn])
  }

  depends_on = [
    rhcs_rosa_oidc_config.this,
    aws_iam_openid_connect_provider.this,
    data.aws_iam_openid_connect_provider.existing,
    aws_iam_role_policy_attachment.account_role_policy,
    aws_iam_role_policy_attachment.operator_role_policy,
    aws_iam_instance_profile.worker,
  ]
}
