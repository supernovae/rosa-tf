#------------------------------------------------------------------------------
# Custom Ingress Module for ROSA Classic GovCloud
# Creates a secondary IngressController for custom domains
# (e.g., *.apps.mydomain.com)
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# NOTE: This module creates configuration for a secondary IngressController
# The actual IngressController creation requires the OpenShift API.
# This module provides:
# 1. The Kubernetes manifests to apply
# 2. Route53 hosted zone setup (optional)
# 3. Certificate resources (optional)
#
# After cluster creation, apply the generated manifests using:
#   oc apply -f <generated_manifest>
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Local Values
#------------------------------------------------------------------------------

locals {
  ingress_name = "custom"
}

#------------------------------------------------------------------------------
# Generate IngressController Manifest
# This should be applied after cluster creation
#------------------------------------------------------------------------------

resource "local_file" "ingress_controller_manifest" {
  filename = "${path.module}/manifests/ingress-controller-${local.ingress_name}.yaml"
  content  = <<-YAML
    # Custom IngressController for ${var.custom_domain}
    # Apply this manifest after cluster creation:
    #   oc apply -f ingress-controller-${local.ingress_name}.yaml
    #
    # This creates an internal (private) ingress controller for the custom domain.
    
    apiVersion: operator.openshift.io/v1
    kind: IngressController
    metadata:
      name: ${local.ingress_name}
      namespace: openshift-ingress-operator
    spec:
      # Domain for this ingress controller
      domain: ${var.custom_domain}
      
      # Number of replicas
      replicas: ${var.replicas}
      
      # Internal/Private load balancer for GovCloud
      endpointPublishingStrategy:
        type: LoadBalancerService
        loadBalancer:
          scope: Internal
          providerParameters:
            type: AWS
            aws:
              type: NLB
      
      # Node placement (optional - deploy to infra nodes if available)
      nodePlacement:
        nodeSelector:
          matchLabels:
            node-role.kubernetes.io/worker: ""
      
      %{if length(var.route_selector) > 0}
      # Route selector - only routes with these labels will use this ingress
      routeSelector:
        matchLabels:
          %{for key, value in var.route_selector}
          ${key}: "${value}"
          %{endfor}
      %{endif}
      
      # TLS configuration
      defaultCertificate:
        name: ${local.ingress_name}-default-cert
      
      # HTTP/2 support
      httpHeaders:
        forwardedHeaderPolicy: Append
      
      # Logging
      logging:
        access:
          destination:
            type: Container
  YAML

  file_permission = "0644"
}

#------------------------------------------------------------------------------
# Generate Certificate Secret Placeholder
# Replace with your actual certificate
#------------------------------------------------------------------------------

resource "local_file" "certificate_secret_template" {
  filename = "${path.module}/manifests/certificate-secret-${local.ingress_name}.yaml"
  content  = <<-YAML
    # TLS Certificate Secret for Custom Ingress
    # Replace the placeholders with your actual certificate and key
    #
    # For production, consider using:
    # - AWS Certificate Manager (ACM) with external-dns
    # - cert-manager with Let's Encrypt or your CA
    # - Manual certificate from your PKI
    
    apiVersion: v1
    kind: Secret
    metadata:
      name: ${local.ingress_name}-default-cert
      namespace: openshift-ingress
    type: kubernetes.io/tls
    data:
      # Base64 encoded TLS certificate (replace with your certificate)
      tls.crt: |
        # cat your-cert.pem | base64 -w0
        REPLACE_WITH_BASE64_ENCODED_CERTIFICATE
      
      # Base64 encoded TLS private key (replace with your private key)
      tls.key: |
        # cat your-key.pem | base64 -w0
        REPLACE_WITH_BASE64_ENCODED_PRIVATE_KEY
    
    ---
    # Alternative: Using cert-manager (if installed)
    # 
    # apiVersion: cert-manager.io/v1
    # kind: Certificate
    # metadata:
    #   name: ${local.ingress_name}-cert
    #   namespace: openshift-ingress
    # spec:
    #   secretName: ${local.ingress_name}-default-cert
    #   issuerRef:
    #     name: your-cluster-issuer
    #     kind: ClusterIssuer
    #   dnsNames:
    #     - "*.${var.custom_domain}"
  YAML

  file_permission = "0644"
}

#------------------------------------------------------------------------------
# Generate Sample Route Manifest
#------------------------------------------------------------------------------

resource "local_file" "sample_route_manifest" {
  filename = "${path.module}/manifests/sample-route-${local.ingress_name}.yaml"
  content  = <<-YAML
    # Sample Route using the Custom IngressController
    # This demonstrates how to create a route that uses the custom domain
    
    apiVersion: route.openshift.io/v1
    kind: Route
    metadata:
      name: sample-app
      namespace: default
      labels:
        %{for key, value in var.route_selector}
        ${key}: "${value}"
        %{endfor}
    spec:
      host: sample-app.${var.custom_domain}
      to:
        kind: Service
        name: your-service-name
        weight: 100
      port:
        targetPort: 8080
      tls:
        termination: edge
        insecureEdgeTerminationPolicy: Redirect
      wildcardPolicy: None
  YAML

  file_permission = "0644"
}

#------------------------------------------------------------------------------
# Generate DNS Configuration Guide
#------------------------------------------------------------------------------

resource "local_file" "dns_configuration_guide" {
  filename = "${path.module}/manifests/dns-configuration.md"
  content  = <<-MARKDOWN
    # DNS Configuration for Custom Ingress: ${var.custom_domain}
    
    ## Overview
    
    After deploying the custom IngressController, you need to configure DNS
    to point your custom domain to the internal load balancer.
    
    ## Steps
    
    ### 1. Get the Load Balancer Hostname
    
    After the IngressController is created, get the load balancer hostname:
    
    ```bash
    oc get svc -n openshift-ingress router-${local.ingress_name} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
    ```
    
    ### 2. Create DNS Records
    
    #### Option A: Route 53 (Same Account)
    
    Create a wildcard CNAME or ALIAS record:
    
    ```hcl
    resource "aws_route53_record" "custom_ingress" {
      zone_id = "<your-hosted-zone-id>"
      name    = "*.${var.custom_domain}"
      type    = "CNAME"
      ttl     = 300
      records = ["<load-balancer-hostname>"]
    }
    ```
    
    #### Option B: External DNS Operator
    
    If using external-dns operator, it will automatically create DNS records.
    
    #### Option C: Manual DNS
    
    Add a CNAME record in your DNS provider:
    
    | Record Type | Name | Value |
    |------------|------|-------|
    | CNAME | *.${var.custom_domain} | <load-balancer-hostname> |
    
    ### 3. Verify DNS Resolution
    
    ```bash
    # Test DNS resolution
    dig +short test.${var.custom_domain}
    
    # Should return the internal load balancer IPs
    ```
    
    ## TLS Certificates
    
    For TLS, you have several options:
    
    1. **AWS ACM**: Use AWS Certificate Manager with the load balancer
    2. **cert-manager**: Install cert-manager and configure a ClusterIssuer
    3. **Manual**: Provide your own certificate from your PKI
    
    See `certificate-secret-${local.ingress_name}.yaml` for the secret template.
    
    ## Verification
    
    After DNS is configured:
    
    ```bash
    # Check IngressController status
    oc get ingresscontroller -n openshift-ingress-operator ${local.ingress_name}
    
    # Check the router pods
    oc get pods -n openshift-ingress -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=${local.ingress_name}
    
    # Test a sample route
    curl -k https://sample-app.${var.custom_domain}
    ```
  MARKDOWN

  file_permission = "0644"
}

#------------------------------------------------------------------------------
# Create manifests directory
#------------------------------------------------------------------------------

resource "null_resource" "create_manifests_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/manifests"
  }

  triggers = {
    always_run = timestamp()
  }
}
