#------------------------------------------------------------------------------
# IAM Roles Module for ROSA Classic
#
# CLUSTER-SCOPED IAM Roles:
# This module creates IAM resources that are tied to a specific cluster.
# Each cluster owns its roles, and destroying the cluster removes its roles.
#
# Resources created:
#   - Account roles (Installer, Support, ControlPlane, Worker)
#   - ELB service-linked role (if needed)
#   - OIDC configuration and provider for STS authentication
#   - Operator roles for cluster operators
#
# Unlike ROSA HCP (which uses shared account-level roles), ROSA Classic
# uses cluster-scoped roles. This ensures clean teardown without affecting
# other clusters.
#
# See docs/IAM-LIFECYCLE.md for architecture details.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

# Verify RHCS API authentication
# This will fail with a clear error if the token is invalid
data "rhcs_info" "current" {}

# Get ROSA policies from RHCS provider
# Depends on rhcs_info to ensure authentication is working
data "rhcs_policies" "all_policies" {
  depends_on = [data.rhcs_info.current]
}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  path       = var.path

  # Role prefixes - default to cluster_name for cluster-scoped roles
  account_role_prefix  = coalesce(var.account_role_prefix, var.cluster_name)
  operator_role_prefix = coalesce(var.operator_role_prefix, var.cluster_name)

  # Trust principals for account roles (must match official RHCS module)
  # Installer: RH-Managed-OpenShift-Installer role in OCM AWS account
  installer_trust_principal = "arn:${local.partition}:iam::${data.rhcs_info.current.ocm_aws_account_id}:role/RH-Managed-OpenShift-Installer"
  # Support: Specific SRE role ARN from RHCS policies
  support_trust_principal = data.rhcs_policies.all_policies.account_role_policies["sts_support_rh_sre_role"]

  # Major version for policy paths (e.g., "4.16" from "4.16.50")
  major_version = join(".", slice(split(".", var.openshift_version), 0, 2))

  # Role names - cluster-scoped using account_role_prefix
  installer_role_name     = "${local.account_role_prefix}-Installer-Role"
  support_role_name       = "${local.account_role_prefix}-Support-Role"
  control_plane_role_name = "${local.account_role_prefix}-ControlPlane-Role"
  worker_role_name        = "${local.account_role_prefix}-Worker-Role"
}

#------------------------------------------------------------------------------
# Service-Linked Role for Elastic Load Balancing
# Required for ROSA to create load balancers
#------------------------------------------------------------------------------

# Check if the service-linked role exists
data "aws_iam_role" "elb_service_role" {
  count = 1
  name  = "AWSServiceRoleForElasticLoadBalancing"
}

# Create if it doesn't exist (this will fail gracefully if it already exists)
resource "aws_iam_service_linked_role" "elb" {
  count            = length(data.aws_iam_role.elb_service_role) == 0 ? 1 : 0
  aws_service_name = "elasticloadbalancing.amazonaws.com"
  description      = "Service-linked role for Elastic Load Balancing"
}

#------------------------------------------------------------------------------
# Account Roles (Cluster-Scoped)
#
# Creates the 4 account roles required for ROSA Classic:
#   - Installer Role: Used during cluster installation
#   - Support Role: Used by Red Hat SRE for support access
#   - ControlPlane Role: Used by control plane nodes
#   - Worker Role: Used by worker nodes
#
# Each cluster creates its own roles using cluster_name as the prefix.
# This ensures clean teardown - destroying a cluster removes its roles
# without affecting other clusters.
#------------------------------------------------------------------------------

# Installer Role Trust Policy
data "aws_iam_policy_document" "installer_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [local.installer_trust_principal]
    }
  }
}

# Installer Role
resource "aws_iam_role" "installer" {
  name                  = local.installer_role_name
  path                  = local.path
  assume_role_policy    = data.aws_iam_policy_document.installer_trust.json
  force_detach_policies = true

  tags = merge(var.tags, {
    "rosa_openshift_version" = local.major_version
    "rosa_role_prefix"       = local.account_role_prefix
    "rosa_role_type"         = "installer"
    "rosa_cluster_name"      = var.cluster_name
    "red-hat-managed"        = "true"
  })
}

resource "aws_iam_role_policy" "installer" {
  name   = "${local.account_role_prefix}-Installer-Role-Policy"
  role   = aws_iam_role.installer.id
  policy = data.rhcs_policies.all_policies.account_role_policies["sts_installer_permission_policy"]
}

# Support Role Trust Policy
data "aws_iam_policy_document" "support_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [local.support_trust_principal]
    }
  }
}

# Support Role
resource "aws_iam_role" "support" {
  name                  = local.support_role_name
  path                  = local.path
  assume_role_policy    = data.aws_iam_policy_document.support_trust.json
  force_detach_policies = true

  tags = merge(var.tags, {
    "rosa_openshift_version" = local.major_version
    "rosa_role_prefix"       = local.account_role_prefix
    "rosa_role_type"         = "support"
    "rosa_cluster_name"      = var.cluster_name
    "red-hat-managed"        = "true"
  })
}

resource "aws_iam_role_policy" "support" {
  name   = "${local.account_role_prefix}-Support-Role-Policy"
  role   = aws_iam_role.support.id
  policy = data.rhcs_policies.all_policies.account_role_policies["sts_support_permission_policy"]
}

# ControlPlane Role Trust Policy (EC2 service for instance profiles)
data "aws_iam_policy_document" "control_plane_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ControlPlane Role
resource "aws_iam_role" "control_plane" {
  name                  = local.control_plane_role_name
  path                  = local.path
  assume_role_policy    = data.aws_iam_policy_document.control_plane_trust.json
  force_detach_policies = true

  tags = merge(var.tags, {
    "rosa_openshift_version" = local.major_version
    "rosa_role_prefix"       = local.account_role_prefix
    "rosa_role_type"         = "control_plane"
    "rosa_cluster_name"      = var.cluster_name
    "red-hat-managed"        = "true"
  })
}

resource "aws_iam_role_policy" "control_plane" {
  name   = "${local.account_role_prefix}-ControlPlane-Role-Policy"
  role   = aws_iam_role.control_plane.id
  policy = data.rhcs_policies.all_policies.account_role_policies["sts_instance_controlplane_permission_policy"]
}

# Worker Role Trust Policy (EC2 service for instance profiles)
data "aws_iam_policy_document" "worker_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Worker Role
resource "aws_iam_role" "worker" {
  name                  = local.worker_role_name
  path                  = local.path
  assume_role_policy    = data.aws_iam_policy_document.worker_trust.json
  force_detach_policies = true

  tags = merge(var.tags, {
    "rosa_openshift_version" = local.major_version
    "rosa_role_prefix"       = local.account_role_prefix
    "rosa_role_type"         = "worker"
    "rosa_cluster_name"      = var.cluster_name
    "red-hat-managed"        = "true"
  })
}

resource "aws_iam_role_policy" "worker" {
  name   = "${local.account_role_prefix}-Worker-Role-Policy"
  role   = aws_iam_role.worker.id
  policy = data.rhcs_policies.all_policies.account_role_policies["sts_instance_worker_permission_policy"]
}

# Instance profiles for ControlPlane and Worker roles
resource "aws_iam_instance_profile" "control_plane" {
  name = local.control_plane_role_name
  path = local.path
  role = aws_iam_role.control_plane.name
  tags = var.tags
}

resource "aws_iam_instance_profile" "worker" {
  name = local.worker_role_name
  path = local.path
  role = aws_iam_role.worker.name
  tags = var.tags
}

#------------------------------------------------------------------------------
# ECR Policy (Optional - for ECR image pulls)
# Enables workers to pull from Amazon ECR repositories
#------------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "worker_ecr_readonly" {
  count = var.attach_ecr_policy ? 1 : 0

  role       = aws_iam_role.worker.id
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

#------------------------------------------------------------------------------
# OIDC Configuration
#
# Creates OIDC config based on the selected mode:
# - Managed: Red Hat hosts OIDC provider (default)
# - Unmanaged: Customer hosts OIDC in their AWS account
# - Pre-existing: Use provided OIDC config ID (no creation)
#------------------------------------------------------------------------------

# Validate OIDC configuration inputs
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

# OIDC configuration - resolve from created resource or provided variables
locals {
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

  # Depend on role ARNs being available (either existing or created)
  depends_on = [
    aws_iam_role_policy.installer,
    aws_iam_role_policy.support,
    aws_iam_role_policy.control_plane,
    aws_iam_role_policy.worker
  ]
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

  tags = merge(
    var.tags,
    {
      "rosa_cluster_id" = var.cluster_name
    }
  )
}

#------------------------------------------------------------------------------
# Operator Roles
# Creates operator roles required for ROSA Classic cluster operations.
#
# ROSA Classic requires:
# - Commercial: 6 operator roles
# - GovCloud: 7 operator roles (includes kube-controller-manager)
#
# Operators:
# 1. openshift-cloud-credential-operator - Manages cloud credentials
# 2. openshift-cluster-csi-drivers - EBS CSI driver for volume encryption
# 3. openshift-machine-api - Machine API for node management
# 4. openshift-ingress-operator - Load balancers and DNS
# 5. openshift-image-registry - Image registry storage
# 6. openshift-cloud-network-config-controller - Cloud network config
# 7. kube-system/kube-controller-manager - GovCloud only
#
# Set create_operator_roles = false to manage operator roles externally via CLI.
#------------------------------------------------------------------------------

locals {
  # GovCloud requires 7 operator roles, commercial requires 6
  # Reference: https://github.com/terraform-redhat/terraform-rhcs-rosa-classic
  is_govcloud          = local.partition == "aws-us-gov"
  operator_roles_count = var.create_operator_roles ? (local.is_govcloud ? 7 : 6) : 0

  # Map operator namespace/name to policy key in rhcs_policies
  # These keys MUST match what data.rhcs_policies.all_policies.operator_role_policies provides
  # Reference: terraform-redhat/terraform-rhcs-rosa-classic/modules/operator-policies
  operator_policy_key_map = {
    # Cloud network config controller - manages cloud network configuration
    "openshift-cloud-network-config-controller/cloud-credentials" = "openshift_cloud_network_config_controller_cloud_credentials_policy"

    # Machine API - manages cloud resources for machine provisioning
    "openshift-machine-api/aws-cloud-credentials" = "openshift_machine_api_aws_cloud_credentials_policy"

    # Cloud credential operator - manages IAM credentials (read-only creds version)
    "openshift-cloud-credential-operator/cloud-credential-operator-iam-ro-creds" = "openshift_cloud_credential_operator_cloud_credential_operator_iam_ro_creds_policy"

    # Image registry - manages S3 storage for the registry
    "openshift-image-registry/installer-cloud-credentials" = "openshift_image_registry_installer_cloud_credentials_policy"

    # Ingress operator - manages load balancers and DNS
    "openshift-ingress-operator/cloud-credentials" = "openshift_ingress_operator_cloud_credentials_policy"

    # CSI drivers - manages EBS volumes
    "openshift-cluster-csi-drivers/ebs-cloud-credentials" = "openshift_cluster_csi_drivers_ebs_cloud_credentials_policy"

    # GovCloud-specific: AWS VPC Endpoint operator
    "openshift-aws-vpce-operator/aws-vpce-operator" = "openshift_aws_vpce_operator_avo_aws_creds_policy"
  }
}

# Get operator role definitions from RHCS provider
data "rhcs_rosa_operator_roles" "operator_roles" {
  count = var.create_operator_roles ? 1 : 0

  operator_role_prefix = local.operator_role_prefix
  account_role_prefix  = local.account_role_prefix

  depends_on = [
    aws_iam_role_policy.installer,
    aws_iam_role_policy.support,
    aws_iam_role_policy.control_plane,
    aws_iam_role_policy.worker
  ]
}

# Trust policies for operator roles
data "aws_iam_policy_document" "operator_trust" {
  count = local.operator_roles_count

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
      values   = data.rhcs_rosa_operator_roles.operator_roles[0].operator_iam_roles[count.index].service_accounts
    }
  }
}

# Create operator roles - uses name_prefix to allow recreation
resource "aws_iam_role" "operator" {
  count = local.operator_roles_count

  name                  = data.rhcs_rosa_operator_roles.operator_roles[0].operator_iam_roles[count.index].role_name
  path                  = local.path
  assume_role_policy    = data.aws_iam_policy_document.operator_trust[count.index].json
  force_detach_policies = true

  tags = merge(
    var.tags,
    {
      "rosa_cluster_id"        = var.cluster_name
      "rosa_openshift_version" = local.major_version
      "red-hat-managed"        = "true"
      "operator_namespace"     = data.rhcs_rosa_operator_roles.operator_roles[0].operator_iam_roles[count.index].operator_namespace
      "operator_name"          = data.rhcs_rosa_operator_roles.operator_roles[0].operator_iam_roles[count.index].operator_name
    }
  )

  # Allow role to be replaced when policies change
  lifecycle {
    create_before_destroy = true
  }
}

# Operator policies - create managed policies first (matches official module approach)
# This creates customer-managed policies using policy content from rhcs_policies
resource "aws_iam_policy" "operator" {
  count = local.operator_roles_count

  name = data.rhcs_rosa_operator_roles.operator_roles[0].operator_iam_roles[count.index].policy_name
  path = local.path

  # Build the lookup key from namespace/name
  # Try multiple key formats since RHCS API may use different naming conventions
  policy = coalesce(
    # Try the mapped key first (namespace/name format)
    try(
      data.rhcs_policies.all_policies.operator_role_policies[
        lookup(
          local.operator_policy_key_map,
          "${data.rhcs_rosa_operator_roles.operator_roles[0].operator_iam_roles[count.index].operator_namespace}/${data.rhcs_rosa_operator_roles.operator_roles[0].operator_iam_roles[count.index].operator_name}",
          "___nonexistent___"
        )
      ],
      null
    ),
    # Try constructing the key from namespace_operator_name_policy format
    try(
      data.rhcs_policies.all_policies.operator_role_policies[
        "${replace(data.rhcs_rosa_operator_roles.operator_roles[0].operator_iam_roles[count.index].operator_namespace, "-", "_")}_${replace(data.rhcs_rosa_operator_roles.operator_roles[0].operator_iam_roles[count.index].operator_name, "-", "_")}_policy"
      ],
      null
    ),
    # Last resort: minimal policy (should never be needed if mapping is correct)
    jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "PlaceholderPolicyNeedsUpdate"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      }]
    })
  )

  tags = merge(
    var.tags,
    {
      "rosa_cluster_id"        = var.cluster_name
      "rosa_openshift_version" = local.major_version
      "red-hat-managed"        = "true"
      "operator_namespace"     = data.rhcs_rosa_operator_roles.operator_roles[0].operator_iam_roles[count.index].operator_namespace
      "operator_name"          = data.rhcs_rosa_operator_roles.operator_roles[0].operator_iam_roles[count.index].operator_name
    }
  )
}

# Attach managed policies to operator roles
resource "aws_iam_role_policy_attachment" "operator" {
  count = local.operator_roles_count

  role       = aws_iam_role.operator[count.index].name
  policy_arn = aws_iam_policy.operator[count.index].arn
}

# Wait for role propagation before cluster creation
resource "time_sleep" "role_propagation" {
  count = var.create_operator_roles ? 1 : 0

  create_duration = "20s"

  triggers = {
    operator_role_prefix = var.operator_role_prefix
    operator_role_arns   = jsonencode([for role in aws_iam_role.operator : role.arn])
    operator_policy_arns = jsonencode([for policy in aws_iam_policy.operator : policy.arn])
  }

  depends_on = [aws_iam_role_policy_attachment.operator]
}
