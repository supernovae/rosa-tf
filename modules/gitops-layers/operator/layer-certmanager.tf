#------------------------------------------------------------------------------
# Layer: cert-manager
#
# Installs the OpenShift cert-manager operator, configures IRSA for Route53
# DNS01 challenges, creates Let's Encrypt ClusterIssuers, and optionally
# provisions Certificate resources and a custom IngressController with
# wildcard DNS.
#
# Dependencies:
#   - IAM role with OIDC trust for Route53 (from gitops-layers/certmanager module)
#   - Route53 hosted zone (from gitops-layers/certmanager module)
#------------------------------------------------------------------------------

locals {
  # Map user-friendly visibility values to OpenShift IngressController scope values.
  # The OpenShift API expects "Internal" or "External", not "private" or "public".
  certmanager_ingress_scope = var.certmanager_ingress_visibility == "public" ? "External" : "Internal"

  # Cert-Manager templates
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
  # Select issuer: staging has much higher rate limits for dev/test
  certmanager_issuer_name = var.certmanager_use_staging_issuer ? "letsencrypt-staging" : "letsencrypt-production"

  certmanager_certificates = [
    for cert in var.certmanager_certificate_domains : templatefile("${local.layers_path}/certmanager/certificate.yaml.tftpl", {
      cert_name        = cert.name
      cert_namespace   = cert.namespace
      cert_secret_name = cert.secret_name
      cert_domains     = cert.domains
      issuer_name      = local.certmanager_issuer_name
    })
  ]
  certmanager_ingress_controller = var.enable_layer_certmanager && var.certmanager_ingress_enabled ? templatefile("${local.layers_path}/certmanager/ingress-controller.yaml.tftpl", {
    custom_domain           = var.certmanager_ingress_domain
    replicas                = var.certmanager_ingress_replicas
    visibility              = local.certmanager_ingress_scope
    cert_secret_name        = var.certmanager_ingress_cert_secret_name
    route_selector_yaml     = join("\n", [for k, v in var.certmanager_ingress_route_selector : "      ${k}: \"${v}\""])
    namespace_selector_yaml = join("\n", [for k, v in var.certmanager_ingress_namespace_selector : "      ${k}: \"${v}\""])
  }) : ""
}

#------------------------------------------------------------------------------
# Step 1: Namespace
#------------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "certmanager" {
  count = var.enable_layer_certmanager ? 1 : 0

  metadata {
    name = "cert-manager-operator"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "rosa-gitops-layers"
      "app.kubernetes.io/component"  = "certmanager"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }

  depends_on = [time_sleep.wait_for_argocd_ready]
}

#------------------------------------------------------------------------------
# Step 2: OperatorGroup
#------------------------------------------------------------------------------

resource "kubectl_manifest" "certmanager_operatorgroup" {
  count = var.enable_layer_certmanager ? 1 : 0

  yaml_body = file("${local.layers_path}/certmanager/operatorgroup.yaml")

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubernetes_namespace_v1.certmanager]
}

#------------------------------------------------------------------------------
# Step 3: Subscription
#------------------------------------------------------------------------------

resource "kubectl_manifest" "certmanager_subscription" {
  count = var.enable_layer_certmanager ? 1 : 0

  yaml_body = templatefile("${local.layers_path}/certmanager/subscription.yaml.tftpl", { config = var.certmanager_operator_config })

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubectl_manifest.certmanager_operatorgroup]
}

#------------------------------------------------------------------------------
# Step 4: Wait for cert-manager operator
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_certmanager_operator" {
  count = var.enable_layer_certmanager ? 1 : 0

  create_duration = "120s"

  depends_on = [kubectl_manifest.certmanager_subscription]
}

#------------------------------------------------------------------------------
# Step 5: Annotate cert-manager ServiceAccount with IAM role ARN (IRSA)
#
# The cert-manager operator creates the SA in the cert-manager namespace.
# We patch it to add the IRSA annotation using server_side_apply.
#------------------------------------------------------------------------------

resource "kubectl_manifest" "certmanager_sa_irsa" {
  count = var.enable_layer_certmanager ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: cert-manager
      namespace: cert-manager
      annotations:
        eks.amazonaws.com/role-arn: "${var.certmanager_role_arn}"
  YAML

  server_side_apply = true
  force_conflicts   = false

  depends_on = [time_sleep.wait_for_certmanager_operator]
}

#------------------------------------------------------------------------------
# Step 6: Operator-managed HA and optional approved DNS resolver settings
#
# Cluster DNS is the default. Use explicit recursive resolvers only when needed
# for split-horizon DNS and approved by the network owner.
#------------------------------------------------------------------------------

resource "kubectl_manifest" "certmanager_dns_config" {
  count = var.enable_layer_certmanager ? 1 : 0

  yaml_body = templatefile("${local.layers_path}/certmanager/controller-config.yaml.tftpl", {
    config         = var.certmanager_operator_config
    nameservers    = var.certmanager_dns01_recursive_nameservers
    recursive_only = var.certmanager_dns01_recursive_nameservers_only
  })

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubectl_manifest.certmanager_sa_irsa]
}

#------------------------------------------------------------------------------
# Step 7: Wait for cert-manager pods to restart with new config
#
# After IRSA annotation and DNS config patches, cert-manager needs a moment
# to reconcile. The operator handles pod restarts automatically.
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_certmanager_restart" {
  count = var.enable_layer_certmanager ? 1 : 0

  create_duration = "30s"

  depends_on = [
    kubectl_manifest.certmanager_sa_irsa,
    kubectl_manifest.certmanager_dns_config,
  ]
}

#------------------------------------------------------------------------------
# Step 8: ClusterIssuer (production - Let's Encrypt)
#------------------------------------------------------------------------------

resource "kubectl_manifest" "certmanager_issuer_production" {
  count = var.enable_layer_certmanager ? 1 : 0

  yaml_body = local.certmanager_cluster_issuer

  server_side_apply = true
  force_conflicts   = false

  depends_on = [time_sleep.wait_for_certmanager_restart]
}

#------------------------------------------------------------------------------
# Step 9: ClusterIssuer (staging - Let's Encrypt, for testing)
#------------------------------------------------------------------------------

resource "kubectl_manifest" "certmanager_issuer_staging" {
  count = var.enable_layer_certmanager ? 1 : 0

  yaml_body = local.certmanager_cluster_issuer_staging

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubectl_manifest.certmanager_issuer_production]
}

#------------------------------------------------------------------------------
# Step 10: Certificate resources (one per domain entry)
#------------------------------------------------------------------------------

resource "kubectl_manifest" "certmanager_certificate" {
  count = var.enable_layer_certmanager ? length(var.certmanager_certificate_domains) : 0

  yaml_body = local.certmanager_certificates[count.index]

  server_side_apply = true
  force_conflicts   = false

  wait_for {
    condition {
      type   = "Ready"
      status = "True"
    }
  }
  timeouts {
    create = "20m"
    update = "20m"
  }
  depends_on = [kubectl_manifest.certmanager_issuer_production, kubectl_manifest.certmanager_issuer_staging]
}

# Certificate Ready is checked before attaching its Secret to the router.
#------------------------------------------------------------------------------
# Step 11: Routes integration (optional)
#
# Installs the cert-manager-openshift-routes controller that watches for
# annotated Routes and automatically provisions TLS certificates.
#------------------------------------------------------------------------------

# Leader election requires lease access for the routes controller SA
resource "kubectl_manifest" "certmanager_routes_leader_election_role" {
  count = var.enable_layer_certmanager && var.certmanager_enable_routes_integration ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: Role
    metadata:
      name: cert-manager-openshift-routes-leader-election
      namespace: cert-manager
      labels:
        app.kubernetes.io/name: cert-manager-openshift-routes
        app.kubernetes.io/managed-by: terraform
    rules:
      - apiGroups: ["coordination.k8s.io"]
        resources: ["leases"]
        verbs: ["get", "create", "update", "patch"]
  YAML

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubectl_manifest.certmanager_issuer_production]
}

resource "kubectl_manifest" "certmanager_routes_leader_election_rolebinding" {
  count = var.enable_layer_certmanager && var.certmanager_enable_routes_integration ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: RoleBinding
    metadata:
      name: cert-manager-openshift-routes-leader-election
      namespace: cert-manager
      labels:
        app.kubernetes.io/name: cert-manager-openshift-routes
        app.kubernetes.io/managed-by: terraform
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: Role
      name: cert-manager-openshift-routes-leader-election
    subjects:
      - kind: ServiceAccount
        name: cert-manager
        namespace: cert-manager
  YAML

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubectl_manifest.certmanager_routes_leader_election_role]
}

resource "kubectl_manifest" "certmanager_routes_integration" {
  count = var.enable_layer_certmanager && var.certmanager_enable_routes_integration ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: cert-manager-openshift-routes
      namespace: cert-manager
      labels:
        app.kubernetes.io/name: cert-manager-openshift-routes
        app.kubernetes.io/managed-by: terraform
    spec:
      replicas: 1
      selector:
        matchLabels:
          app.kubernetes.io/name: cert-manager-openshift-routes
      template:
        metadata:
          labels:
            app.kubernetes.io/name: cert-manager-openshift-routes
        spec:
          serviceAccountName: cert-manager
          containers:
            - name: cert-manager-openshift-routes
              image: ${var.certmanager_routes_image}
              args:
                - --enable-leader-election
  YAML

  server_side_apply = true
  force_conflicts   = false

  depends_on = [kubectl_manifest.certmanager_routes_leader_election_rolebinding]
}

#------------------------------------------------------------------------------
# Step 12: Preserve the legacy wait address; Certificate Ready now gates progress
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_certmanager_cert" {
  count = var.enable_layer_certmanager && var.certmanager_ingress_enabled && length(var.certmanager_certificate_domains) > 0 ? 1 : 0

  # Preserve this state address for upgrades; readiness is enforced above.
  create_duration = "0s"

  depends_on = [kubectl_manifest.certmanager_certificate]
}

#------------------------------------------------------------------------------
# Step 13: Custom IngressController
#
# Creates a scoped IngressController that only serves routes matching the
# custom domain. Uses the TLS certificate from cert-manager.
#------------------------------------------------------------------------------

resource "kubectl_manifest" "certmanager_ingress_controller" {
  count = var.enable_layer_certmanager && var.certmanager_ingress_enabled ? 1 : 0

  yaml_body = local.certmanager_ingress_controller

  server_side_apply = true
  force_conflicts   = false

  depends_on = [time_sleep.wait_for_certmanager_cert]
}

#------------------------------------------------------------------------------
# Step 14: Wait for IngressController NLB provisioning
#
# After creating the IngressController, AWS needs time to provision the NLB.
# Typically 3-5 minutes.
#------------------------------------------------------------------------------

resource "time_sleep" "wait_for_ingress_nlb" {
  count = var.enable_layer_certmanager && var.certmanager_ingress_enabled ? 1 : 0

  create_duration = "300s"

  depends_on = [kubectl_manifest.certmanager_ingress_controller]
}

#------------------------------------------------------------------------------
# Step 15: Read NLB hostname from router service
#
# The IngressController creates a LoadBalancer service named
# router-custom-apps in openshift-ingress. We read its external hostname.
#------------------------------------------------------------------------------

data "kubernetes_service_v1" "custom_apps_router" {
  count = var.enable_layer_certmanager && var.certmanager_ingress_enabled ? 1 : 0

  metadata {
    name      = "router-custom-apps"
    namespace = "openshift-ingress"
  }

  depends_on = [time_sleep.wait_for_ingress_nlb]
}

#------------------------------------------------------------------------------
# Step 16: Route53 wildcard CNAME record
#
# Points *.domain to the NLB hostname. Managed by Terraform for full
# lifecycle (created on apply, removed on destroy).
#------------------------------------------------------------------------------

resource "aws_route53_record" "certmanager_wildcard" {
  count = var.enable_layer_certmanager && var.certmanager_ingress_enabled ? 1 : 0

  zone_id = var.certmanager_hosted_zone_id
  name    = "*.${var.certmanager_ingress_domain}"
  type    = "CNAME"
  ttl     = 300
  records = [data.kubernetes_service_v1.custom_apps_router[0].status[0].load_balancer[0].ingress[0].hostname]

  # Never silently take ownership of an existing (possibly ROSA-managed) record.
  # Import an approved dedicated-domain record explicitly before managing it.
  allow_overwrite = false
}
