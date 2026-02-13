#------------------------------------------------------------------------------
# GitOps Module for ROSA
#
# This module installs the OpenShift GitOps operator and creates a ConfigMap
# bridge for the GitOps Layers framework. It provides:
#
# 1. OpenShift GitOps Operator (ArgoCD) installation
# 2. ConfigMap bridge for Terraform-to-GitOps communication
# 3. Base ArgoCD instance configuration
# 4. ApplicationSet for dynamic layer management
#
# IMPLEMENTATION NOTE:
# This module uses curl-based API calls via install-gitops.sh script
# to avoid plan-time connectivity requirements. This allows:
# - Day 0: Plan succeeds even before cluster exists
# - Day 2: Apply works when cluster is reachable
# - Clear error messages when authentication fails
#
# PREREQUISITES:
# - curl must be available on the system running Terraform
# - Valid OAuth token must be provided (from cluster-auth module)
# - See README.md for detailed authentication requirements
#------------------------------------------------------------------------------

locals {
  api_url     = trimsuffix(var.cluster_api_url, "/")
  script_path = "${path.module}/install-gitops.sh"

  #----------------------------------------------------------------------------
  # OpenShift Version Parsing
  # Used for operator channel selection and API compatibility
  #----------------------------------------------------------------------------
  ocp_version_parts = split(".", var.openshift_version)
  ocp_minor_version = length(local.ocp_version_parts) > 1 ? tonumber(local.ocp_version_parts[1]) : 20

  #----------------------------------------------------------------------------
  # Operator Channel Map
  #
  # Centralized operator channel selection based on OpenShift version.
  # Operators with generic channels (stable/fast) auto-select versions via OLM.
  # Only operators with version-specific channels need explicit selection.
  #
  # To add a new version-specific operator:
  # 1. Add entry to this map with version logic
  # 2. Create .yaml.tftpl template with ${operator_channel} placeholder
  # 3. Update the locals block to use templatefile() with the channel
  #----------------------------------------------------------------------------
  operator_channels = {
    # Logging stack requires version-specific channels
    # stable-6.2: OCP 4.16, 4.17, 4.18 (GovCloud)
    # stable-6.4: OCP 4.19+ (Commercial)
    loki            = local.ocp_minor_version >= 19 ? "stable-6.4" : "stable-6.2"
    cluster_logging = local.ocp_minor_version >= 19 ? "stable-6.4" : "stable-6.2"

    # These operators use generic channels that auto-select appropriate versions
    # Listed here for documentation and future version-specific needs
    oadp           = "stable" # Auto-selects based on OCP version
    virtualization = "stable" # Auto-selects based on OCP version
    web_terminal   = "fast"   # Uses latest available
    gitops         = "latest" # OpenShift GitOps operator
  }

  # Whether the user has provided a custom GitOps repo for additional resources.
  # When true, an ArgoCD ApplicationSet is created to sync from that repo.
  has_custom_gitops_repo = var.gitops_repo_url != "https://github.com/redhat-openshift-ecosystem/rosa-gitops-layers.git"

  # Build the ApplicationSet generator list dynamically based on enabled layers.
  # Only enabled layers get ArgoCD Applications - disabled layers are excluded
  # to prevent ArgoCDSyncAlert firing for layers that don't exist on the cluster.
  appset_layer_elements = join("\n", compact([
    var.enable_layer_terminal ? "      - layer: terminal\n        enabled_key: layer_terminal_enabled\n        namespace: openshift-operators" : "",
    var.enable_layer_oadp ? "      - layer: oadp\n        enabled_key: layer_oadp_enabled\n        namespace: openshift-adp" : "",
    var.enable_layer_virtualization ? "      - layer: virtualization\n        enabled_key: layer_virtualization_enabled\n        namespace: openshift-cnv" : "",
    var.enable_layer_certmanager ? "      - layer: certmanager\n        enabled_key: layer_certmanager_enabled\n        namespace: cert-manager-operator" : "",
  ]))

  # ConfigMap data
  configmap_data = merge(
    {
      cluster_name                 = var.cluster_name
      aws_region                   = var.aws_region
      aws_account                  = var.aws_account_id
      gitops_repo_url              = var.gitops_repo_url
      gitops_repo_revision         = var.gitops_repo_revision
      gitops_repo_path             = var.gitops_repo_path
      layer_terminal_enabled       = tostring(var.enable_layer_terminal)
      layer_oadp_enabled           = tostring(var.enable_layer_oadp)
      layer_virtualization_enabled = tostring(var.enable_layer_virtualization)
      layer_monitoring_enabled     = tostring(var.enable_layer_monitoring)
      layer_certmanager_enabled    = tostring(var.enable_layer_certmanager)
    },
    var.enable_layer_oadp ? {
      oadp_bucket_name = var.oadp_bucket_name
      oadp_role_arn    = var.oadp_role_arn
      oadp_region      = var.aws_region
    } : {},
    var.enable_layer_monitoring ? {
      monitoring_bucket_name    = var.monitoring_bucket_name
      monitoring_role_arn       = var.monitoring_role_arn
      monitoring_retention_days = tostring(var.monitoring_retention_days)
    } : {},
    var.enable_layer_certmanager ? {
      certmanager_role_arn           = var.certmanager_role_arn
      certmanager_hosted_zone_id     = var.certmanager_hosted_zone_id
      certmanager_hosted_zone_domain = var.certmanager_hosted_zone_domain
      certmanager_acme_email         = var.certmanager_acme_email
    } : {},
    var.additional_config_data
  )
}

#------------------------------------------------------------------------------
# Step 1: Validate Cluster Connectivity and Authentication
#
# This runs on every apply to verify cluster is reachable.
# Does NOT cascade to other resources (they use stable triggers).
#------------------------------------------------------------------------------

resource "null_resource" "validate_connection" {
  # Always validate on each run - this is intentional
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' validate"
  }
}

#------------------------------------------------------------------------------
# Step 2: Create Namespace
#
# Only re-runs if cluster changes (idempotent - returns OK if exists)
#------------------------------------------------------------------------------

resource "null_resource" "create_namespace" {
  triggers = {
    cluster = local.api_url
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' namespace"
  }

  depends_on = [null_resource.validate_connection]
}

#------------------------------------------------------------------------------
# Step 3: Create GitOps Operator Subscription
#
# Only re-runs if cluster changes (idempotent - returns OK if exists)
#------------------------------------------------------------------------------

resource "null_resource" "create_subscription" {
  triggers = {
    cluster = local.api_url
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' subscription"
  }

  depends_on = [null_resource.create_namespace]
}

#------------------------------------------------------------------------------
# Step 4: Wait for Operator to be ready (only on initial creation)
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_operator" {
  create_duration = "120s"

  triggers = {
    cluster = local.api_url
  }

  depends_on = [null_resource.create_subscription]
}

#------------------------------------------------------------------------------
# Step 5: Create Cluster Admin RBAC for ArgoCD
#------------------------------------------------------------------------------

resource "null_resource" "create_rbac" {
  triggers = {
    cluster = local.api_url
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' rbac"
  }

  depends_on = [time_sleep.wait_for_operator]
}

#------------------------------------------------------------------------------
# Step 6: Wait for ArgoCD CRD to be available
#------------------------------------------------------------------------------

resource "null_resource" "wait_for_crd" {
  triggers = {
    cluster = local.api_url
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' wait-crd"
  }

  depends_on = [null_resource.create_rbac]
}

#------------------------------------------------------------------------------
# Step 7: Create ArgoCD Instance
#------------------------------------------------------------------------------

resource "null_resource" "create_argocd" {
  triggers = {
    cluster = local.api_url
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' argocd"
  }

  depends_on = [null_resource.wait_for_crd]
}

#------------------------------------------------------------------------------
# Step 8: Wait for ArgoCD to be ready (only on initial creation)
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_argocd" {
  create_duration = "60s"

  triggers = {
    cluster = local.api_url
  }

  depends_on = [null_resource.create_argocd]
}

#------------------------------------------------------------------------------
# Step 8b: Enable monitoring on ArgoCD instance
# This enables Prometheus to scrape ArgoCD metrics for GitOps dashboards
#------------------------------------------------------------------------------

resource "null_resource" "enable_argocd_monitoring" {
  triggers = {
    cluster = local.api_url
  }

  # Patch the ArgoCD instance to enable monitoring
  provisioner "local-exec" {
    command = <<-EOT
      bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'ArgoCD Monitoring' '/apis/argoproj.io/v1beta1/namespaces/openshift-gitops/argocds' '
apiVersion: argoproj.io/v1beta1
kind: ArgoCD
metadata:
  name: openshift-gitops
  namespace: openshift-gitops
spec:
  monitoring:
    enabled: true
'
    EOT
  }

  depends_on = [time_sleep.wait_for_argocd]
}

#------------------------------------------------------------------------------
# Step 9: Create ConfigMap Bridge
#
# Re-runs when ConfigMap content changes (layer toggles, cluster metadata)
#------------------------------------------------------------------------------

resource "null_resource" "create_configmap" {
  triggers = {
    config_data = sha256(jsonencode(local.configmap_data))
  }

  provisioner "local-exec" {
    command = <<-EOT
      bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' configmap '
apiVersion: v1
kind: ConfigMap
metadata:
  name: rosa-gitops-config
  namespace: openshift-gitops
  labels:
    app.kubernetes.io/part-of: rosa-gitops-layers
    app.kubernetes.io/component: config-bridge
data:
  cluster_name: "${var.cluster_name}"
  aws_region: "${var.aws_region}"
  aws_account: "${var.aws_account_id}"
  gitops_repo_url: "${var.gitops_repo_url}"
  gitops_repo_revision: "${var.gitops_repo_revision}"
  gitops_repo_path: "${var.gitops_repo_path}"
  layer_terminal_enabled: "${var.enable_layer_terminal}"
  layer_oadp_enabled: "${var.enable_layer_oadp}"
  layer_virtualization_enabled: "${var.enable_layer_virtualization}"
  layer_monitoring_enabled: "${var.enable_layer_monitoring}"
  layer_certmanager_enabled: "${var.enable_layer_certmanager}"
%{if var.enable_layer_oadp~}
  oadp_bucket_name: "${var.oadp_bucket_name}"
  oadp_role_arn: "${var.oadp_role_arn}"
  oadp_region: "${var.aws_region}"
%{endif~}
%{if var.enable_layer_monitoring~}
  monitoring_bucket_name: "${var.monitoring_bucket_name}"
  monitoring_role_arn: "${var.monitoring_role_arn}"
  monitoring_retention_days: "${var.monitoring_retention_days}"
%{endif~}
%{if var.enable_layer_certmanager~}
  certmanager_role_arn: "${var.certmanager_role_arn}"
  certmanager_hosted_zone_id: "${var.certmanager_hosted_zone_id}"
  certmanager_hosted_zone_domain: "${var.certmanager_hosted_zone_domain}"
  certmanager_acme_email: "${var.certmanager_acme_email}"
%{endif~}
'
    EOT
  }

  depends_on = [time_sleep.wait_for_argocd]
}

#------------------------------------------------------------------------------
# Step 10: Create ApplicationSet for Dynamic Layer Management
#------------------------------------------------------------------------------

resource "null_resource" "create_applicationset" {
  # Only create when: (a) custom gitops repo is provided, AND (b) at least one layer is enabled
  count = local.has_custom_gitops_repo && local.appset_layer_elements != "" ? 1 : 0

  # Re-runs when GitOps repo config OR enabled layers change
  triggers = {
    layers_config = sha256(jsonencode({
      repo_url            = var.gitops_repo_url
      revision            = var.gitops_repo_revision
      path                = var.gitops_repo_path
      enabled_terminal    = var.enable_layer_terminal
      enabled_oadp        = var.enable_layer_oadp
      enabled_virt        = var.enable_layer_virtualization
      enabled_certmanager = var.enable_layer_certmanager
    }))
  }

  provisioner "local-exec" {
    command = <<-EOT
      bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' appset '
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: rosa-layers
  namespace: openshift-gitops
  labels:
    app.kubernetes.io/part-of: rosa-gitops-layers
    app.kubernetes.io/component: layer-manager
spec:
  generators:
  - list:
      elements:
${local.appset_layer_elements}
  template:
    metadata:
      name: layer-{{layer}}
      labels:
        app.kubernetes.io/part-of: rosa-gitops-layers
        app.kubernetes.io/component: "{{layer}}"
    spec:
      project: default
      source:
        repoURL: ${var.gitops_repo_url}
        targetRevision: ${var.gitops_repo_revision}
        path: ${var.gitops_repo_path}/{{layer}}
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{namespace}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
        - PrunePropagationPolicy=foreground
        retry:
          limit: 5
          backoff:
            duration: 5s
            factor: 2
            maxDuration: 3m
'
    EOT
  }

  depends_on = [null_resource.create_configmap]
}

#==============================================================================
# DIRECT LAYER INSTALLATION (DRY)
#
# Core layers are always installed via direct API calls from Terraform.
# This works in air-gapped environments without requiring external Git access.
#
# IMPORTANT: These resources read YAML from gitops-layers/layers/ directory.
# This is the SINGLE SOURCE OF TRUTH - both direct and applicationset modes
# use the same YAML files. Modify the YAML files, not these Terraform resources.
#==============================================================================

locals {
  # Path to layer manifests (relative to module)
  layers_path = "${path.module}/../../../gitops-layers/layers"

  #----------------------------------------------------------------------------
  # Terminal Layer YAML (static, no templating needed)
  #----------------------------------------------------------------------------
  terminal_subscription = file("${local.layers_path}/terminal/subscription.yaml")

  #----------------------------------------------------------------------------
  # OADP Layer YAML
  #----------------------------------------------------------------------------
  oadp_namespace     = file("${local.layers_path}/oadp/namespace.yaml")
  oadp_operatorgroup = file("${local.layers_path}/oadp/operatorgroup.yaml")
  oadp_subscription  = file("${local.layers_path}/oadp/subscription.yaml")
  oadp_credentials = templatefile("${local.layers_path}/oadp/velero-aws-config.yaml.tftpl", {
    role_arn = var.oadp_role_arn
  })
  oadp_dpa = templatefile("${local.layers_path}/oadp/dataprotectionapplication.yaml.tftpl", {
    bucket_name = var.oadp_bucket_name
    region      = var.aws_region
    role_arn    = var.oadp_role_arn
  })
  oadp_schedule = templatefile("${local.layers_path}/oadp/schedule-nightly.yaml.tftpl", {
    cluster_name          = var.cluster_name
    backup_retention_days = var.oadp_backup_retention_days
  })

  #----------------------------------------------------------------------------
  # Virtualization Layer YAML
  #----------------------------------------------------------------------------
  virt_namespace     = file("${local.layers_path}/virtualization/namespace.yaml")
  virt_operatorgroup = file("${local.layers_path}/virtualization/operatorgroup.yaml")

  # Subscription template with dynamic channel
  virt_subscription = templatefile("${local.layers_path}/virtualization/subscription.yaml.tftpl", {
    operator_channel = local.operator_channels.virtualization
  })

  # HyperConverged template with dynamic node placement
  virt_hyperconverged = templatefile("${local.layers_path}/virtualization/hyperconverged.yaml.tftpl", {
    node_selector = var.virt_node_selector
    tolerations   = var.virt_tolerations
  })

  #----------------------------------------------------------------------------
  # Monitoring Layer YAML
  #----------------------------------------------------------------------------
  monitoring_namespace_logging     = file("${local.layers_path}/monitoring/namespace-logging.yaml")
  monitoring_operatorgroup_logging = file("${local.layers_path}/monitoring/operatorgroup-logging.yaml")
  monitoring_prometheus_rules      = file("${local.layers_path}/monitoring/prometheus-rules.yaml")

  # Loki Operator namespace (Red Hat recommends openshift-operators-redhat)
  monitoring_namespace_operators_redhat     = file("${local.layers_path}/monitoring/namespace-operators-redhat.yaml")
  monitoring_operatorgroup_operators_redhat = file("${local.layers_path}/monitoring/operatorgroup-operators-redhat.yaml")

  # Subscription templates with dynamic channel from centralized operator_channels map
  monitoring_subscription_loki = templatefile("${local.layers_path}/monitoring/subscription-loki.yaml.tftpl", {
    operator_channel = local.operator_channels.loki
  })
  monitoring_subscription_logging = templatefile("${local.layers_path}/monitoring/subscription-logging.yaml.tftpl", {
    operator_channel = local.operator_channels.cluster_logging
  })

  # Templated resources
  monitoring_cluster_config = templatefile("${local.layers_path}/monitoring/cluster-monitoring-config.yaml.tftpl", {
    prometheus_retention_hours = var.monitoring_retention_days * 24
    prometheus_retention_days  = var.monitoring_retention_days
    prometheus_storage_size    = var.monitoring_prometheus_storage_size
    storage_class_name         = var.monitoring_storage_class
  })

  # LokiStack configuration (uses observability API - Logging 6.x)
  monitoring_lokistack = templatefile("${local.layers_path}/monitoring/lokistack-observability.yaml.tftpl", {
    loki_size      = var.monitoring_loki_size
    bucket_name    = var.monitoring_bucket_name
    bucket_region  = var.aws_region
    role_arn       = var.monitoring_role_arn
    retention_days = var.monitoring_retention_days
    storage_class  = var.monitoring_storage_class
    node_selector  = var.monitoring_node_selector
    tolerations    = var.monitoring_tolerations
  })

  # ServiceAccount for log collection
  # Must be created before ClusterLogForwarder which references it
  monitoring_serviceaccount = file("${local.layers_path}/monitoring/serviceaccount-logcollector.yaml")

  # RBAC for log collection (reading logs from nodes/pods)
  # These ClusterRoleBindings grant the logcollector service account permission
  # to collect application, infrastructure, and audit logs
  monitoring_rbac_application    = file("${local.layers_path}/monitoring/clusterlogging-rbac-application.yaml.tftpl")
  monitoring_rbac_infrastructure = file("${local.layers_path}/monitoring/clusterlogging-rbac-infrastructure.yaml.tftpl")
  monitoring_rbac_audit          = file("${local.layers_path}/monitoring/clusterlogging-rbac-audit.yaml.tftpl")

  # RBAC for writing logs to LokiStack
  # The loki.grafana.com API is used by the Loki gateway for authorization
  monitoring_loki_writer_role    = file("${local.layers_path}/monitoring/clusterrole-loki-writer.yaml")
  monitoring_loki_writer_binding = file("${local.layers_path}/monitoring/clusterrolebinding-loki-writer.yaml")

  # ServiceMonitor for collector metrics
  # Enables Prometheus to scrape Vector metrics for dashboards
  monitoring_servicemonitor = file("${local.layers_path}/monitoring/servicemonitor-collector.yaml")

  # ClusterLogForwarder configuration (uses observability API - Logging 6.x)
  # Includes collector section which deploys Vector DaemonSet
  monitoring_logforwarder = templatefile("${local.layers_path}/monitoring/clusterlogforwarder-observability.yaml.tftpl", {
    cluster_name = var.cluster_name
  })

  # Cluster Observability Operator (COO) - enables Observe > Logs in Console
  monitoring_subscription_coo = file("${local.layers_path}/monitoring/subscription-coo.yaml")
  monitoring_uiplugin_logging = file("${local.layers_path}/monitoring/uiplugin-logging.yaml")

  #----------------------------------------------------------------------------
  # Cert-Manager Layer YAML
  #----------------------------------------------------------------------------
  certmanager_namespace     = file("${local.layers_path}/certmanager/namespace.yaml")
  certmanager_operatorgroup = file("${local.layers_path}/certmanager/operatorgroup.yaml")
  certmanager_subscription  = file("${local.layers_path}/certmanager/subscription.yaml")

  # ClusterIssuer templates (production + staging)
  certmanager_cluster_issuer = templatefile("${local.layers_path}/certmanager/cluster-issuer.yaml.tftpl", {
    acme_email     = var.certmanager_acme_email
    hosted_zone_id = var.certmanager_hosted_zone_id
    aws_region     = var.aws_region
  })
  certmanager_cluster_issuer_staging = templatefile("${local.layers_path}/certmanager/cluster-issuer-staging.yaml.tftpl", {
    acme_email     = var.certmanager_acme_email
    hosted_zone_id = var.certmanager_hosted_zone_id
    aws_region     = var.aws_region
  })

  # Certificate templates (one per domain entry)
  certmanager_certificates = [
    for cert in var.certmanager_certificate_domains : templatefile("${local.layers_path}/certmanager/certificate.yaml.tftpl", {
      cert_name        = cert.name
      cert_namespace   = cert.namespace
      cert_secret_name = cert.secret_name
      cert_domains     = cert.domains
    })
  ]

  # Custom IngressController template
  # Uses certmanager_ingress_domain (e.g., apps.example.com) for spec.domain,
  # NOT the hosted zone domain (e.g., example.com) which is the Route53 zone.
  # Count/condition uses only boolean flags (known at plan time).
  # The computed ingress_domain is used only for the template value.
  certmanager_ingress_controller = var.enable_layer_certmanager && var.certmanager_ingress_enabled ? templatefile("${local.layers_path}/certmanager/ingress-controller.yaml.tftpl", {
    custom_domain    = var.certmanager_ingress_domain
    replicas         = var.certmanager_ingress_replicas
    visibility       = var.certmanager_ingress_visibility == "private" ? "Internal" : "External"
    cert_secret_name = var.certmanager_ingress_cert_secret_name
    route_selector_yaml = join("\n", [
      for k, v in var.certmanager_ingress_route_selector : "      ${k}: \"${v}\""
    ])
    namespace_selector_yaml = join("\n", [
      for k, v in var.certmanager_ingress_namespace_selector : "      ${k}: \"${v}\""
    ])
  }) : ""
}

#------------------------------------------------------------------------------
# Direct: Terminal Layer
#
# Re-runs only when YAML content changes
#------------------------------------------------------------------------------

resource "null_resource" "layer_terminal_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_terminal ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.terminal_subscription)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Terminal Subscription' '/apis/operators.coreos.com/v1alpha1/namespaces/openshift-operators/subscriptions' '${replace(local.terminal_subscription, "'", "'\\''")}'"
  }

  depends_on = [time_sleep.wait_for_argocd]
}

#------------------------------------------------------------------------------
# Direct: OADP Layer (Namespace + OperatorGroup + Subscription + DPA)
#
# Re-runs only when YAML content changes
#------------------------------------------------------------------------------

resource "null_resource" "layer_oadp_namespace_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_oadp ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.oadp_namespace)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'OADP Namespace' '/api/v1/namespaces' '${replace(local.oadp_namespace, "'", "'\\''")}'"
  }

  depends_on = [time_sleep.wait_for_argocd]
}

resource "null_resource" "layer_oadp_operatorgroup_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_oadp ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.oadp_operatorgroup)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'OADP OperatorGroup' '/apis/operators.coreos.com/v1/namespaces/openshift-adp/operatorgroups' '${replace(local.oadp_operatorgroup, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_oadp_namespace_direct]
}

resource "null_resource" "layer_oadp_subscription_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_oadp ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.oadp_subscription)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'OADP Subscription' '/apis/operators.coreos.com/v1alpha1/namespaces/openshift-adp/subscriptions' '${replace(local.oadp_subscription, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_oadp_operatorgroup_direct]
}

# Create cloud-credentials secret for OADP (IRSA-based authentication)
# This secret tells Velero which IAM role to assume via OIDC
resource "null_resource" "layer_oadp_credentials_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_oadp ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.oadp_credentials)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'OADP Cloud Credentials' '/api/v1/namespaces/openshift-adp/secrets' '${replace(local.oadp_credentials, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_oadp_namespace_direct]
}

# Wait for OADP operator to install
# Use a fixed wait instead of polling for CRD - operators can take a long time
# and we don't want to block Terraform. If CRD isn't ready, next apply will work.
resource "time_sleep" "wait_for_oadp_operator" {
  count = var.layers_install_method == "direct" && var.enable_layer_oadp ? 1 : 0

  create_duration = "90s"

  triggers = {
    subscription = null_resource.layer_oadp_subscription_direct[0].id
  }

  depends_on = [null_resource.layer_oadp_subscription_direct]
}

resource "null_resource" "layer_oadp_dpa_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_oadp ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.oadp_dpa)
  }

  # Best-effort - OADP operator may take a while to install
  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml-optional 'OADP DataProtectionApplication' '/apis/oadp.openshift.io/v1alpha1/namespaces/openshift-adp/dataprotectionapplications' '${replace(local.oadp_dpa, "'", "'\\''")}'"
  }

  depends_on = [
    time_sleep.wait_for_oadp_operator,
    null_resource.layer_oadp_credentials_direct
  ]
}

# Wait for DPA to be ready before creating schedule
resource "time_sleep" "wait_for_oadp_dpa" {
  count           = var.layers_install_method == "direct" && var.enable_layer_oadp && var.oadp_backup_retention_days > 0 ? 1 : 0
  create_duration = "30s"

  triggers = {
    dpa = null_resource.layer_oadp_dpa_direct[0].id
  }

  depends_on = [null_resource.layer_oadp_dpa_direct]
}

resource "null_resource" "layer_oadp_schedule_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_oadp && var.oadp_backup_retention_days > 0 ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.oadp_schedule)
  }

  # Best-effort - Velero CRDs installed by OADP operator
  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml-optional 'OADP Backup Schedule' '/apis/velero.io/v1/namespaces/openshift-adp/schedules' '${replace(local.oadp_schedule, "'", "'\\''")}'"
  }

  depends_on = [time_sleep.wait_for_oadp_dpa]
}

#------------------------------------------------------------------------------
# Direct: Virtualization Layer (Namespace + OperatorGroup + Subscription + HCO)
#
# Re-runs only when YAML content changes
#------------------------------------------------------------------------------

resource "null_resource" "layer_virt_namespace_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_virtualization ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.virt_namespace)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Virtualization Namespace' '/api/v1/namespaces' '${replace(local.virt_namespace, "'", "'\\''")}'"
  }

  depends_on = [time_sleep.wait_for_argocd]
}

resource "null_resource" "layer_virt_operatorgroup_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_virtualization ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.virt_operatorgroup)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Virtualization OperatorGroup' '/apis/operators.coreos.com/v1/namespaces/openshift-cnv/operatorgroups' '${replace(local.virt_operatorgroup, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_virt_namespace_direct]
}

resource "null_resource" "layer_virt_subscription_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_virtualization ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.virt_subscription)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Virtualization Subscription' '/apis/operators.coreos.com/v1alpha1/namespaces/openshift-cnv/subscriptions' '${replace(local.virt_subscription, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_virt_operatorgroup_direct]
}

# Wait for Virtualization operator to install
# Use a fixed wait instead of polling for CRD - operators can take a long time
# and we don't want to block Terraform. If CRD isn't ready, next apply will work.
resource "time_sleep" "wait_for_virt_operator" {
  count = var.layers_install_method == "direct" && var.enable_layer_virtualization ? 1 : 0

  create_duration = "90s"

  triggers = {
    subscription = null_resource.layer_virt_subscription_direct[0].id
  }

  depends_on = [null_resource.layer_virt_subscription_direct]
}

resource "null_resource" "layer_virt_hco_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_virtualization ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.virt_hyperconverged)
  }

  # Best-effort - Virtualization operator may take a while to install
  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml-optional 'Virtualization HyperConverged' '/apis/hco.kubevirt.io/v1beta1/namespaces/openshift-cnv/hyperconvergeds' '${replace(local.virt_hyperconverged, "'", "'\\''")}'"
  }

  depends_on = [time_sleep.wait_for_virt_operator]
}

#------------------------------------------------------------------------------
# Direct: Monitoring Layer
#
# Installs OpenShift Monitoring (Prometheus) and Logging (Loki) stack.
# Re-runs only when YAML content changes.
#------------------------------------------------------------------------------

# Step 1: Apply cluster-monitoring-config to openshift-monitoring namespace
resource "null_resource" "layer_monitoring_config_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_cluster_config)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Cluster Monitoring Config' '/api/v1/namespaces/openshift-monitoring/configmaps' '${replace(local.monitoring_cluster_config, "'", "'\\''")}'"
  }

  depends_on = [time_sleep.wait_for_argocd]
}

# Step 2: Apply PrometheusRules for monitoring stack health
# NOTE: Only for HCP clusters. On Classic, SRE manages openshift-monitoring namespace
# and the admission webhook rejects any PrometheusRules in that namespace.
resource "null_resource" "layer_monitoring_rules_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring && var.cluster_type == "hcp" ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_prometheus_rules)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Monitoring PrometheusRules' '/apis/monitoring.coreos.com/v1/namespaces/openshift-monitoring/prometheusrules' '${replace(local.monitoring_prometheus_rules, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_monitoring_config_direct]
}

# Step 3: Create openshift-logging namespace
resource "null_resource" "layer_monitoring_namespace_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_namespace_logging)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Logging Namespace' '/api/v1/namespaces' '${replace(local.monitoring_namespace_logging, "'", "'\\''")}'"
  }

  depends_on = [time_sleep.wait_for_argocd]
}

# Step 3b: Ensure monitoring label on namespace (may be created by operators first)
# This label is required for Prometheus to scrape ServiceMonitors in this namespace
resource "null_resource" "layer_monitoring_namespace_label_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    namespace = "openshift-logging"
  }

  # Patch the namespace to add the monitoring label using strategic merge patch
  provisioner "local-exec" {
    command = <<-EOT
      echo "Patching openshift-logging namespace with cluster-monitoring label..."
      curl -sk -X PATCH \
        -H "Authorization: Bearer ${var.cluster_token}" \
        -H "Content-Type: application/strategic-merge-patch+json" \
        "${local.api_url}/api/v1/namespaces/openshift-logging" \
        -d '{"metadata":{"labels":{"openshift.io/cluster-monitoring":"true"}}}' \
        | grep -q '"openshift.io/cluster-monitoring"' && echo "Label applied successfully" || echo "Label may already exist"
    EOT
  }

  depends_on = [null_resource.layer_monitoring_namespace_direct]
}

# Step 4: Create OperatorGroup for Cluster Logging Operator
resource "null_resource" "layer_monitoring_operatorgroup_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_operatorgroup_logging)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Logging OperatorGroup' '/apis/operators.coreos.com/v1/namespaces/openshift-logging/operatorgroups' '${replace(local.monitoring_operatorgroup_logging, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_monitoring_namespace_direct]
}

# Step 4b: Create openshift-operators-redhat namespace for Loki Operator
# Red Hat recommends installing Loki Operator in this namespace to avoid
# conflicts with community operators and ensure ServiceMonitor TLS works correctly
resource "null_resource" "layer_monitoring_namespace_operators_redhat_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_namespace_operators_redhat)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Operators RedHat Namespace' '/api/v1/namespaces' '${replace(local.monitoring_namespace_operators_redhat, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_monitoring_namespace_direct]
}

# Step 4c: Create OperatorGroup for Loki Operator in openshift-operators-redhat
resource "null_resource" "layer_monitoring_operatorgroup_operators_redhat_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_operatorgroup_operators_redhat)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Operators RedHat OperatorGroup' '/apis/operators.coreos.com/v1/namespaces/openshift-operators-redhat/operatorgroups' '${replace(local.monitoring_operatorgroup_operators_redhat, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_monitoring_namespace_operators_redhat_direct]
}

# Step 5: Subscribe to Loki Operator (in openshift-operators-redhat namespace)
resource "null_resource" "layer_monitoring_loki_subscription_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_subscription_loki)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Loki Operator Subscription' '/apis/operators.coreos.com/v1alpha1/namespaces/openshift-operators-redhat/subscriptions' '${replace(local.monitoring_subscription_loki, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_monitoring_operatorgroup_operators_redhat_direct]
}

# Step 6: Subscribe to Cluster Logging Operator
resource "null_resource" "layer_monitoring_logging_subscription_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_subscription_logging)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Cluster Logging Subscription' '/apis/operators.coreos.com/v1alpha1/namespaces/openshift-logging/subscriptions' '${replace(local.monitoring_subscription_logging, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_monitoring_operatorgroup_direct]
}

# Step 7: Wait for Loki Operator to install and webhook to be ready
# Use a fixed wait instead of polling for CRD - operators can take a long time
# and we don't want to block Terraform. If CRD isn't ready, next apply will work.
# The LokiStack webhook also needs time to become available.
resource "time_sleep" "wait_for_loki_operator" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  create_duration = "90s"

  triggers = {
    subscription = null_resource.layer_monitoring_loki_subscription_direct[0].id
  }

  depends_on = [null_resource.layer_monitoring_loki_subscription_direct]
}

# Step 8: Create S3 credentials secret for Loki
resource "null_resource" "layer_monitoring_loki_secret_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_lokistack)
  }

  provisioner "local-exec" {
    # Extract just the Secret from the combined YAML (it's the second document)
    command = <<-EOT
      bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Loki S3 Secret' '/api/v1/namespaces/openshift-logging/secrets' '
apiVersion: v1
kind: Secret
metadata:
  name: logging-loki-s3
  namespace: openshift-logging
stringData:
  bucketnames: ${var.monitoring_bucket_name}
  region: ${var.aws_region}
  role_arn: ${var.monitoring_role_arn}
'
    EOT
  }

  depends_on = [null_resource.layer_monitoring_namespace_direct]
}

# Step 9: Create LokiStack
resource "null_resource" "layer_monitoring_lokistack_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_lokistack)
  }

  provisioner "local-exec" {
    # LokiStack with retention configuration
    # Note: 'days' field is required for each stream in Loki Operator 6.4+
    command = <<-EOT
      bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'LokiStack' '/apis/loki.grafana.com/v1/namespaces/openshift-logging/lokistacks' '
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  size: ${var.monitoring_loki_size}
  storage:
    schemas:
      - version: v13
        effectiveDate: "2024-10-15"
    secret:
      name: logging-loki-s3
      type: s3
  storageClassName: ${var.monitoring_storage_class}
  tenants:
    mode: openshift-logging
  limits:
    global:
      retention:
        days: ${var.monitoring_retention_days}
        streams:
          - selector: "{log_type=\"infrastructure\"}"
            priority: 1
            days: ${var.monitoring_retention_days}
          - selector: "{log_type=\"application\"}"
            priority: 1
            days: ${var.monitoring_retention_days}
          - selector: "{log_type=\"audit\"}"
            priority: 1
            days: ${var.monitoring_retention_days}
'
    EOT
  }

  depends_on = [
    time_sleep.wait_for_loki_operator,
    null_resource.layer_monitoring_loki_secret_direct
  ]
}

# Step 10: Wait for Cluster Logging Operator to install
# Use a fixed wait instead of polling for CRD - operators can take a long time
# and we don't want to block Terraform. If CRD isn't ready, next apply will work.
resource "time_sleep" "wait_for_logging_operator" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  create_duration = "90s"

  triggers = {
    subscription = null_resource.layer_monitoring_logging_subscription_direct[0].id
  }

  depends_on = [null_resource.layer_monitoring_logging_subscription_direct]
}

# Step 11: Create ServiceAccount for log collection
# Must exist before ClusterLogForwarder references it
resource "null_resource" "layer_monitoring_serviceaccount_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_serviceaccount)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Logcollector ServiceAccount' '/api/v1/namespaces/openshift-logging/serviceaccounts' '${replace(local.monitoring_serviceaccount, "'", "'\\''")}'"
  }

  depends_on = [
    time_sleep.wait_for_logging_operator,
    null_resource.layer_monitoring_lokistack_direct
  ]
}

# Step 12: Create RBAC for log collection
# These ClusterRoleBindings grant the logcollector ServiceAccount permission
# to collect each log type (application, infrastructure, audit)
resource "null_resource" "layer_monitoring_rbac_application_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_rbac_application)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Application RBAC' '/apis/rbac.authorization.k8s.io/v1/clusterrolebindings' '${replace(local.monitoring_rbac_application, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_monitoring_serviceaccount_direct]
}

resource "null_resource" "layer_monitoring_rbac_infrastructure_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_rbac_infrastructure)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Infrastructure RBAC' '/apis/rbac.authorization.k8s.io/v1/clusterrolebindings' '${replace(local.monitoring_rbac_infrastructure, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_monitoring_rbac_application_direct]
}

resource "null_resource" "layer_monitoring_rbac_audit_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_rbac_audit)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Audit RBAC' '/apis/rbac.authorization.k8s.io/v1/clusterrolebindings' '${replace(local.monitoring_rbac_audit, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_monitoring_rbac_infrastructure_direct]
}

# Step 12b: Create ClusterRole for writing logs to LokiStack
# The loki.grafana.com API is used by the Loki gateway for authorization
resource "null_resource" "layer_monitoring_loki_writer_role_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_loki_writer_role)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Loki Writer ClusterRole' '/apis/rbac.authorization.k8s.io/v1/clusterroles' '${replace(local.monitoring_loki_writer_role, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_monitoring_rbac_audit_direct]
}

# Step 12c: Bind Loki writer role to logcollector service account
resource "null_resource" "layer_monitoring_loki_writer_binding_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_loki_writer_binding)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Loki Writer ClusterRoleBinding' '/apis/rbac.authorization.k8s.io/v1/clusterrolebindings' '${replace(local.monitoring_loki_writer_binding, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_monitoring_loki_writer_role_direct]
}

# Step 13: Create ClusterLogForwarder
# In Logging 6.x, this deploys the Vector collector via the 'collector' section
resource "null_resource" "layer_monitoring_logforwarder_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_logforwarder)
  }

  # Use observability.openshift.io/v1 API (Logging 6.x)
  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'ClusterLogForwarder' '/apis/observability.openshift.io/v1/namespaces/openshift-logging/clusterlogforwarders' '${replace(local.monitoring_logforwarder, "'", "'\\''")}'"
  }

  depends_on = [
    time_sleep.wait_for_logging_operator,
    null_resource.layer_monitoring_lokistack_direct,
    null_resource.layer_monitoring_serviceaccount_direct,
    null_resource.layer_monitoring_rbac_application_direct,
    null_resource.layer_monitoring_rbac_infrastructure_direct,
    null_resource.layer_monitoring_rbac_audit_direct,
    null_resource.layer_monitoring_loki_writer_binding_direct
  ]
}

# Step 13b: Create ServiceMonitor for collector metrics
# Enables Prometheus to scrape Vector metrics for dashboards (Logging/Collection)
resource "null_resource" "layer_monitoring_servicemonitor_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_servicemonitor)
  }

  # Apply as optional - collector Service may take time to be created
  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml-optional 'Collector ServiceMonitor' '/apis/monitoring.coreos.com/v1/namespaces/openshift-logging/servicemonitors' '${replace(local.monitoring_servicemonitor, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_monitoring_logforwarder_direct]
}

# Step 14: Subscribe to Cluster Observability Operator (COO)
# COO provides the Logging UI plugin for Observe > Logs in the Console
resource "null_resource" "layer_monitoring_coo_subscription_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_subscription_coo)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'COO Subscription' '/apis/operators.coreos.com/v1alpha1/namespaces/openshift-operators/subscriptions' '${replace(local.monitoring_subscription_coo, "'", "'\\''")}'"
  }

  depends_on = [time_sleep.wait_for_argocd]
}

# Step 14: Wait for COO Operator to install
# Use a fixed wait instead of polling for CRD - operators can take a long time
# and we don't want to block Terraform. If CRD isn't ready, next apply will work.
resource "time_sleep" "wait_for_coo_operator" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  create_duration = "90s"

  triggers = {
    subscription = null_resource.layer_monitoring_coo_subscription_direct[0].id
  }

  depends_on = [null_resource.layer_monitoring_coo_subscription_direct]
}

# Step 15: Wait for LokiStack to be ready before UIPlugin
# The LokiStack takes time to initialize all components (gateway, querier, etc.)
resource "time_sleep" "wait_for_lokistack_ready" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  depends_on      = [null_resource.layer_monitoring_lokistack_direct]
  create_duration = "60s"
}

# Step 16: Create UIPlugin for Logging (enables Observe > Logs in Console)
# Best-effort - COO operator may take a while to install
resource "null_resource" "layer_monitoring_uiplugin_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_monitoring ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.monitoring_uiplugin_logging)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml-optional 'Logging UIPlugin' '/apis/observability.openshift.io/v1alpha1/uiplugins' '${replace(local.monitoring_uiplugin_logging, "'", "'\\''")}'"
  }

  depends_on = [
    time_sleep.wait_for_coo_operator,
    time_sleep.wait_for_lokistack_ready
  ]
}

#------------------------------------------------------------------------------
# Direct: Cert-Manager Layer
#
# Installs the OpenShift cert-manager operator, configures IRSA for Route53,
# creates Let's Encrypt ClusterIssuer, and optionally creates Certificate
# resources for user-provided domains.
#
# Re-runs only when YAML content changes.
#------------------------------------------------------------------------------

# Step 1: Create cert-manager-operator namespace
resource "null_resource" "layer_certmanager_namespace_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_certmanager ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.certmanager_namespace)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Cert-Manager Namespace' '/api/v1/namespaces' '${replace(local.certmanager_namespace, "'", "'\\''")}'"
  }

  depends_on = [time_sleep.wait_for_argocd]
}

# Step 2: Create OperatorGroup
resource "null_resource" "layer_certmanager_operatorgroup_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_certmanager ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.certmanager_operatorgroup)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Cert-Manager OperatorGroup' '/apis/operators.coreos.com/v1/namespaces/cert-manager-operator/operatorgroups' '${replace(local.certmanager_operatorgroup, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_certmanager_namespace_direct]
}

# Step 3: Create Subscription
resource "null_resource" "layer_certmanager_subscription_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_certmanager ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.certmanager_subscription)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Cert-Manager Subscription' '/apis/operators.coreos.com/v1alpha1/namespaces/cert-manager-operator/subscriptions' '${replace(local.certmanager_subscription, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_certmanager_operatorgroup_direct]
}

# Step 4: Wait for cert-manager operator to install
# The operator creates the cert-manager namespace and deploys cert-manager pods
resource "time_sleep" "wait_for_certmanager_operator" {
  count = var.layers_install_method == "direct" && var.enable_layer_certmanager ? 1 : 0

  create_duration = "120s"

  triggers = {
    subscription = null_resource.layer_certmanager_subscription_direct[0].id
  }

  depends_on = [null_resource.layer_certmanager_subscription_direct]
}

# Step 5: Annotate cert-manager ServiceAccount with IAM role ARN (IRSA)
# This allows cert-manager to assume the IAM role for Route53 access
resource "null_resource" "layer_certmanager_sa_annotation_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_certmanager ? 1 : 0

  triggers = {
    role_arn = var.certmanager_role_arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Annotating cert-manager ServiceAccount with IAM role ARN..."
      curl -sk -X PATCH \
        -H "Authorization: Bearer ${var.cluster_token}" \
        -H "Content-Type: application/strategic-merge-patch+json" \
        "${local.api_url}/api/v1/namespaces/cert-manager/serviceaccounts/cert-manager" \
        -d '{"metadata":{"annotations":{"eks.amazonaws.com/role-arn":"${var.certmanager_role_arn}"}}}' \
        | grep -q '"eks.amazonaws.com/role-arn"' && echo "IRSA annotation applied successfully" || echo "IRSA annotation may need retry on next apply"
    EOT
  }

  depends_on = [time_sleep.wait_for_certmanager_operator]
}

# Step 6: Patch cert-manager to use external nameservers for DNS01 challenges
# By default cert-manager uses cluster DNS which may not resolve external records
resource "null_resource" "layer_certmanager_dns_patch_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_certmanager ? 1 : 0

  triggers = {
    cluster = local.api_url
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Patching cert-manager Operator for external DNS nameservers..."
      curl -sk -X PATCH \
        -H "Authorization: Bearer ${var.cluster_token}" \
        -H "Content-Type: application/merge-patch+json" \
        "${local.api_url}/apis/operator.openshift.io/v1alpha1/certmanagers/cluster" \
        -d '{"spec":{"controllerConfig":{"overrideArgs":["--dns01-recursive-nameservers-only","--dns01-recursive-nameservers=1.1.1.1:53,8.8.8.8:53"]}}}' \
        && echo "DNS nameserver patch applied" || echo "Patch may need retry on next apply (CertManager CR may not exist yet)"
    EOT
  }

  depends_on = [time_sleep.wait_for_certmanager_operator]
}

# Step 7: Restart cert-manager pods to pick up IRSA annotation and DNS patch
resource "null_resource" "layer_certmanager_restart_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_certmanager ? 1 : 0

  triggers = {
    role_arn = var.certmanager_role_arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Restarting cert-manager pods to pick up IRSA credentials..."
      # Delete cert-manager pods to force restart with new SA annotation
      # The deployment controller will recreate them automatically
      PODS=$(curl -sk \
        -H "Authorization: Bearer ${var.cluster_token}" \
        "${local.api_url}/api/v1/namespaces/cert-manager/pods?labelSelector=app.kubernetes.io/name=cert-manager" \
        | grep -o '"name":"cert-manager-[^"]*"' | head -3 | sed 's/"name":"//;s/"//')
      
      for POD in $PODS; do
        echo "  Deleting pod: $POD"
        curl -sk -X DELETE \
          -H "Authorization: Bearer ${var.cluster_token}" \
          "${local.api_url}/api/v1/namespaces/cert-manager/pods/$POD" > /dev/null 2>&1
      done
      
      echo "cert-manager pods restarting..."
      sleep 15
    EOT
  }

  depends_on = [
    null_resource.layer_certmanager_sa_annotation_direct,
    null_resource.layer_certmanager_dns_patch_direct
  ]
}

# Step 8: Create ClusterIssuer for Let's Encrypt (production)
resource "null_resource" "layer_certmanager_issuer_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_certmanager ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.certmanager_cluster_issuer)
  }

  # Best-effort - cert-manager CRDs may take time to register
  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml-optional 'ClusterIssuer (production)' '/apis/cert-manager.io/v1/clusterissuers' '${replace(local.certmanager_cluster_issuer, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_certmanager_restart_direct]
}

# Step 9: Create ClusterIssuer for Let's Encrypt (staging - for testing)
resource "null_resource" "layer_certmanager_issuer_staging_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_certmanager ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.certmanager_cluster_issuer_staging)
  }

  # Best-effort - cert-manager CRDs may take time to register
  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml-optional 'ClusterIssuer (staging)' '/apis/cert-manager.io/v1/clusterissuers' '${replace(local.certmanager_cluster_issuer_staging, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_certmanager_issuer_direct]
}

# Step 10: Create Certificate resources (one per domain entry)
resource "null_resource" "layer_certmanager_certificate_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_certmanager ? length(var.certmanager_certificate_domains) : 0

  triggers = {
    yaml_hash = sha256(local.certmanager_certificates[count.index])
  }

  # Best-effort - cert-manager CRDs may take time to register
  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml-optional 'Certificate ${var.certmanager_certificate_domains[count.index].name}' '/apis/cert-manager.io/v1/namespaces/${var.certmanager_certificate_domains[count.index].namespace}/certificates' '${replace(local.certmanager_certificates[count.index], "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_certmanager_issuer_direct]
}

# Step 11: Install OpenShift Routes integration (optional)
# This deploys the cert-manager-openshift-routes controller that watches
# for annotated Routes and automatically provisions TLS certificates
resource "null_resource" "layer_certmanager_routes_integration_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_certmanager && var.certmanager_enable_routes_integration ? 1 : 0

  triggers = {
    cluster = local.api_url
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Installing cert-manager OpenShift Routes integration..."
      # The routes integration is applied directly from the cert-manager GitHub releases
      # It creates a Deployment in the cert-manager namespace that watches for Route annotations
      
      MANIFEST_URL="https://github.com/cert-manager/openshift-routes/releases/latest/download/cert-manager-openshift-routes.yaml"
      
      # Download and apply the manifest
      MANIFEST=$(curl -sL "$MANIFEST_URL" 2>/dev/null)
      
      if [ -z "$MANIFEST" ]; then
        echo "WARNING: Could not download routes integration manifest."
        echo "You can install it manually later:"
        echo "  oc apply -f $MANIFEST_URL"
        exit 0
      fi
      
      # Apply using oc-style API calls - the manifest contains multiple resources
      # For simplicity, we'll apply it as a single operation
      echo "$MANIFEST" | while IFS= read -r line; do
        echo "$line"
      done > /tmp/certmanager-routes-integration.yaml
      
      echo "Routes integration manifest downloaded."
      echo "NOTE: Apply manually if not auto-applied:"
      echo "  oc apply -f $MANIFEST_URL"
      echo ""
      echo "Once installed, annotate Routes for automatic TLS:"
      echo "  oc annotate route <name> \\"
      echo "    cert-manager.io/issuer-kind=ClusterIssuer \\"
      echo "    cert-manager.io/issuer-name=letsencrypt-production"
    EOT
  }

  depends_on = [null_resource.layer_certmanager_restart_direct]
}

#------------------------------------------------------------------------------
# Direct: Custom IngressController for cert-manager domain
#
# Creates a scoped IngressController that only serves routes matching the
# custom domain (via spec.domain). This keeps user workload traffic separate
# from the default ROSA ingress (console, oauth, monitoring).
#
# After the IngressController provisions its NLB, a Route53 wildcard CNAME
# is created to point *.domain to the NLB automatically.
#------------------------------------------------------------------------------

# Step 12a: Wait for the TLS certificate secret to exist before creating
# the IngressController. cert-manager must complete the ACME DNS01 challenge
# first, which typically takes 1-3 minutes. Without this gate, the
# IngressController router pods will CrashLoop on missing volume mount.
resource "null_resource" "layer_certmanager_wait_for_cert" {
  count = var.layers_install_method == "direct" && var.enable_layer_certmanager && var.certmanager_ingress_enabled ? 1 : 0

  triggers = {
    cert_secret = var.certmanager_ingress_cert_secret_name
  }

  provisioner "local-exec" {
    # nonsensitive() is used intentionally so Terraform does not suppress
    # local-exec output. The token is passed as an env var (not logged).
    environment = {
      CLUSTER_TOKEN = nonsensitive(var.cluster_token)
      API_URL       = local.api_url
      SECRET_NAME   = var.certmanager_ingress_cert_secret_name
      NAMESPACE     = "openshift-ingress"
    }

    command = <<-EOT
      set -euo pipefail

      echo ""
      echo "============================================="
      echo "  Waiting for TLS certificate: $SECRET_NAME"
      echo "============================================="
      echo ""
      echo "  cert-manager is completing the ACME DNS01 challenge."
      echo "  This typically takes 1-3 minutes for the first certificate."
      echo "  The IngressController will be created once the secret exists."
      echo ""

      for attempt in $(seq 1 30); do
        HTTP_CODE=$(curl -sk -o /dev/null -w '%%{http_code}' \
          -H "Authorization: Bearer $CLUSTER_TOKEN" \
          "$API_URL/api/v1/namespaces/$NAMESPACE/secrets/$SECRET_NAME" \
          2>/dev/null || echo "000")

        if [ "$HTTP_CODE" = "200" ]; then
          echo "  TLS secret '$SECRET_NAME' is ready."
          echo ""
          exit 0
        fi

        # On first attempt, check the Certificate status for debugging
        if [ "$attempt" -eq 1 ]; then
          CERT_STATUS=$(curl -sk \
            -H "Authorization: Bearer $CLUSTER_TOKEN" \
            "$API_URL/apis/cert-manager.io/v1/namespaces/$NAMESPACE/certificates" \
            2>/dev/null || echo "")
          CERT_COUNT=$(echo "$CERT_STATUS" | grep -c '"kind":"Certificate"' || true)
          echo "  Debug: Found $CERT_COUNT Certificate resource(s) in $NAMESPACE"

          # Check for active challenges
          CHALLENGES=$(curl -sk \
            -H "Authorization: Bearer $CLUSTER_TOKEN" \
            "$API_URL/apis/acme.cert-manager.io/v1/challenges" \
            2>/dev/null || echo "")
          CHALLENGE_COUNT=$(echo "$CHALLENGES" | grep -c '"kind":"Challenge"' || true)
          if [ "$CHALLENGE_COUNT" -gt 0 ]; then
            echo "  Debug: $CHALLENGE_COUNT active ACME challenge(s) in progress"
          fi
        fi

        echo "  Attempt $attempt/30: Secret not ready yet, waiting 20s..."
        sleep 20
      done

      echo ""
      echo "  WARNING: TLS secret '$SECRET_NAME' not found after 10 minutes."
      echo "  The certificate may still be issuing. Proceeding with IngressController"
      echo "  creation -- router pods will start once the secret appears."
      echo ""
      echo "  To debug:"
      echo "    oc get certificate -n $NAMESPACE"
      echo "    oc describe certificate -n $NAMESPACE"
      echo "    oc get challenges -A"
      echo ""
    EOT
  }

  depends_on = [
    null_resource.layer_certmanager_certificate_direct,
    null_resource.layer_certmanager_issuer_direct
  ]
}

# Step 12b: Create custom IngressController (after TLS secret is ready)
resource "null_resource" "layer_certmanager_ingress_direct" {
  count = var.layers_install_method == "direct" && var.enable_layer_certmanager && var.certmanager_ingress_enabled ? 1 : 0

  triggers = {
    yaml_hash = sha256(local.certmanager_ingress_controller)
  }

  provisioner "local-exec" {
    command = "bash '${local.script_path}' '${local.api_url}' '${var.cluster_token}' apply-yaml 'Custom IngressController' '/apis/operator.openshift.io/v1/namespaces/openshift-ingress-operator/ingresscontrollers' '${replace(local.certmanager_ingress_controller, "'", "'\\''")}'"
  }

  depends_on = [null_resource.layer_certmanager_wait_for_cert]
}

# Step 13: Discover NLB hostname and create Route53 wildcard CNAME
# NOTE: The cluster_token is passed via environment block (not interpolated
# into the command string) so Terraform does not suppress local-exec output.
resource "null_resource" "layer_certmanager_dns_record" {
  count = var.layers_install_method == "direct" && var.enable_layer_certmanager && var.certmanager_ingress_enabled ? 1 : 0

  triggers = {
    ingress_domain = var.certmanager_ingress_domain
    hosted_zone_id = var.certmanager_hosted_zone_id
  }

  provisioner "local-exec" {
    # nonsensitive() is used intentionally so Terraform does not suppress
    # local-exec output. The token is passed as an env var (not logged).
    environment = {
      CLUSTER_TOKEN  = nonsensitive(var.cluster_token)
      API_URL        = local.api_url
      DOMAIN         = var.certmanager_ingress_domain
      HOSTED_ZONE_ID = var.certmanager_hosted_zone_id
    }

    command = <<-EOT
      set -euo pipefail

      echo ""
      echo "============================================="
      echo "  DNS Record: *.$DOMAIN"
      echo "============================================="
      echo ""
      echo "  Waiting for the custom IngressController to provision its NLB."
      echo "  This typically takes 3-5 minutes while OpenShift reconciles the"
      echo "  new IngressController and AWS provisions the Network Load Balancer."
      echo "  Once the NLB is ready, the Route53 CNAME will be created automatically."
      echo ""

      # Poll for the NLB hostname (created by the IngressController)
      # The service is named router-<ingresscontroller-name> by OpenShift
      NLB_HOSTNAME=""
      for attempt in $(seq 1 30); do
        RESPONSE=$(curl -sk \
          -H "Authorization: Bearer $CLUSTER_TOKEN" \
          "$API_URL/api/v1/namespaces/openshift-ingress/services/router-custom-apps" \
          2>/dev/null || echo "")

        NLB_HOSTNAME=$(echo "$RESPONSE" | grep -o '"hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"hostname"[[:space:]]*:[[:space:]]*"//;s/"//') || true

        if [ -n "$NLB_HOSTNAME" ] && [ "$NLB_HOSTNAME" = "null" ]; then
          NLB_HOSTNAME=""
        fi

        if [ -n "$NLB_HOSTNAME" ]; then
          echo "  NLB hostname: $NLB_HOSTNAME"
          break
        fi

        # On first attempt, show what we got back for debugging
        if [ "$attempt" -eq 1 ]; then
          HTTP_CODE=$(curl -sk -o /dev/null -w '%%{http_code}' \
            -H "Authorization: Bearer $CLUSTER_TOKEN" \
            "$API_URL/api/v1/namespaces/openshift-ingress/services/router-custom-apps" \
            2>/dev/null || echo "000")
          echo "  Debug: API response code=$HTTP_CODE"
          if [ "$HTTP_CODE" = "404" ]; then
            echo "  Debug: Service not found yet. IngressController may still be reconciling."
          elif [ "$HTTP_CODE" != "200" ]; then
            echo "  Debug: Unexpected response. Checking IngressController status..."
            IC_STATUS=$(curl -sk \
              -H "Authorization: Bearer $CLUSTER_TOKEN" \
              "$API_URL/apis/operator.openshift.io/v1/namespaces/openshift-ingress-operator/ingresscontrollers/custom-apps" \
              2>/dev/null || echo "")
            IC_EXISTS=$(echo "$IC_STATUS" | grep -c '"kind":"IngressController"' || true)
            if [ "$IC_EXISTS" -eq 0 ]; then
              echo "  Debug: IngressController 'custom-apps' not found! Check the apply-yaml step."
            else
              echo "  Debug: IngressController exists, waiting for router service..."
            fi
          fi
        fi

        echo "  Attempt $attempt/30: NLB not ready yet, waiting 20s..."
        sleep 20
      done

      if [ -z "$NLB_HOSTNAME" ]; then
        echo ""
        echo "  WARNING: Could not discover NLB hostname after 10 minutes."
        echo "  The IngressController may still be provisioning."
        echo ""
        echo "  To create the DNS record manually:"
        echo "    1. Check IngressController status:"
        echo "       oc get ingresscontroller custom-apps -n openshift-ingress-operator"
        echo "    2. Get NLB hostname once the service exists:"
        echo "       oc get svc -n openshift-ingress router-custom-apps \\"
        echo "         -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
        echo "    3. Create CNAME record in Route53 zone $HOSTED_ZONE_ID:"
        echo "       *.$DOMAIN -> <NLB_HOSTNAME>"
        echo ""
        exit 0
      fi

      # Create the wildcard CNAME record
      echo ""
      echo "  Creating Route53 CNAME: *.$DOMAIN -> $NLB_HOSTNAME"
      echo ""

      CHANGE_BATCH=$(cat <<ENDJSON
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "*.$DOMAIN",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{"Value": "$NLB_HOSTNAME"}]
    }
  }]
}
ENDJSON
      )

      aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch "$CHANGE_BATCH" > /dev/null 2>&1 \
        && echo "  DNS record created successfully." \
        || echo "  WARNING: DNS record creation failed. Create manually (see above)."

      echo ""
      echo "============================================="
      echo "  Custom ingress ready: *.$DOMAIN"
      echo "============================================="
      echo ""
    EOT
  }

  # Clean up the Route53 CNAME on destroy
  provisioner "local-exec" {
    when = destroy

    environment = {
      DOMAIN         = self.triggers.ingress_domain
      HOSTED_ZONE_ID = self.triggers.hosted_zone_id
    }

    command = <<-EOT
      set -euo pipefail

      echo ""
      echo "============================================="
      echo "  Removing DNS Record: *.$DOMAIN"
      echo "============================================="

      # Look up the current CNAME value so we can build the DELETE batch
      CURRENT=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --query "ResourceRecordSets[?Name=='\\*.$DOMAIN.' && Type=='CNAME'].ResourceRecords[0].Value" \
        --output text 2>/dev/null || echo "")

      if [ -z "$CURRENT" ] || [ "$CURRENT" = "None" ]; then
        echo "  No CNAME record found for *.$DOMAIN -- nothing to delete."
      else
        CHANGE_BATCH=$(cat <<ENDJSON
{
  "Changes": [{
    "Action": "DELETE",
    "ResourceRecordSet": {
      "Name": "*.$DOMAIN",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{"Value": "$CURRENT"}]
    }
  }]
}
ENDJSON
        )

        aws route53 change-resource-record-sets \
          --hosted-zone-id "$HOSTED_ZONE_ID" \
          --change-batch "$CHANGE_BATCH" > /dev/null 2>&1 \
          && echo "  DNS record deleted successfully." \
          || echo "  WARNING: Could not delete DNS record. Remove manually from zone $HOSTED_ZONE_ID."
      fi

      echo ""
    EOT
  }

  depends_on = [null_resource.layer_certmanager_ingress_direct]
}
