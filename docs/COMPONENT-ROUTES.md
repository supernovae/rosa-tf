# Native ROSA component routes

The 2.0 development branch pins RHCS `1.7.8` and uses its native
default-ingress resources. Classic accepts `console`, `downloads`, `oauth`;
HCP accepts **console and downloads only**. These are platform component routes,
not the cert-manager layer's separate scoped application IngressController.
See the exact [HCP](https://github.com/terraform-redhat/terraform-provider-rhcs/blob/v1.7.8/docs/resources/hcp_default_ingress.md)
and [Classic](https://github.com/terraform-redhat/terraform-provider-rhcs/blob/v1.7.8/docs/resources/default_ingress.md) schemas.

Use [component-routes.tfvars](../examples/component-routes.tfvars) in Phase 2
after the cluster and selected platform layers are ready. The map contains
hostname and TLS Secret **references**, not PEM/private keys. Provision trusted
TLS Secrets in the platform-required `openshift-config` namespace through an
approved secret/certificate workflow. Verify certificates cover each hostname,
include the necessary chain, and remain renewable. Never reuse the ACME staging
issuer for trusted production console access.

Create approved DNS records pointing to the correct private ingress destination.
Confirm the actual target/region supports the feature and that no other tool owns
native default-ingress configuration. Only then set `component_routes_ready=true`.
Terraform cannot prove DNS, certificate validity or regional eligibility from
the Secret name. An internal HCP ingress remains internal; Classic keeps Strict
namespace ownership and disallows wildcard routes.

The provider owns the complete supplied component-route map. Review omitted keys
and deletion/reset behavior before changing it. This does not change the API
endpoint or HCP OAuth endpoint. Test authentication, console, downloads, private
DNS reachability and certificate rotation; retain a separate API login/recovery
path before modifying user-facing endpoints. No secrets are created by this module.

The [Red Hat Classic tutorial](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws_classic_architecture/4/html/tutorials/cloud-experts-update-component-routes) documents the Secret namespace. Public HCP support guidance can lag the provider schema; verify actual HCP/GovCloud service eligibility rather than inferring it from the schema.
