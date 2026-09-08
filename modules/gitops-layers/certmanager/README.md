# cert-manager layer

## Supported baseline

Verified September 8, 2026: Red Hat cert-manager Operator **1.19.1**, based on
upstream **1.19.6**. The default `stable-v1` subscription follows the latest
supported release offered by the selected catalog. Do not substitute an upstream
Helm chart or assume the operator and operand have identical version numbers.
Check the [Red Hat release notes and channels](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/security_and_compliance/cert-manager-operator-for-red-hat-openshift)
and [support matrix](https://access.redhat.com/support/policy/updates/openshift_operators).

Terraform configures the subscription; it cannot prove a live cluster upgraded.
Verify the installed CSV and operands:

```bash
oc get subscription openshift-cert-manager-operator -n cert-manager-operator -o yaml
oc get csv -n cert-manager-operator
oc get certmanager cluster -o yaml
oc get deployments -n cert-manager
```

## Preferred deployment

Use the Red Hat operator with short-lived STS credentials, explicit Certificate
resources, and a scoped IngressController consuming the wildcard Secret.
The optional community Routes controller is disabled by default. OpenShift 4.18
Route external-certificate support is documented as Technology Preview; this layer
does not enable feature gates or represent that path as production-supported.

1. Create the cluster and infrastructure using the cluster tfvars.
2. Establish private API connectivity and approved outbound ACME/DNS/AWS access.
3. Prefer an existing, publicly delegated Route53 zone. If creating one, provision
   the zone before requesting certificates; verify delegation first.
4. Apply the GitOps overlay with staging issuance and confirm Certificate readiness.
5. Switch staging off, review the plan, and verify the production certificate.

See [the full scenario example](../../../examples/certmanager.tfvars).
For a certificate-only setup, set `certmanager_ingress_enabled = false`; this
avoids creating another router/NLB.

```hcl
install_gitops                      = true
enable_layer_certmanager            = true
certmanager_create_hosted_zone      = false
certmanager_hosted_zone_id          = "Z0123456789ABCDEF"
certmanager_hosted_zone_domain      = "example.com"
certmanager_acme_email              = "platform-team@example.com"
certmanager_use_staging_issuer      = true
certmanager_enable_routes_integration = false
certmanager_ingress_enabled         = true
certmanager_ingress_visibility      = "private"

certmanager_certificate_domains = [{
  name        = "apps-wildcard"
  namespace   = "openshift-ingress"
  secret_name = "custom-apps-default-cert"
  domains     = ["*.apps.example.com"]
}]
```

Staging certificates are intentionally untrusted. ACME account email is not an
expiry-monitoring strategy: monitor Certificate status, renewal time and expiry.

## Operator configuration

```hcl
certmanager_operator_config = {
  channel               = "stable-v1"
  source                = "redhat-operators"
  source_namespace      = "openshift-marketplace"
  install_plan_approval = "Automatic"
  controller_replicas   = 2
  webhook_replicas      = 3
  cainjector_replicas    = 2
}
```

Use a mirrored catalog name/namespace for restricted deployments. A versioned
channel such as `stable-v1.19` holds the minor line when available in your catalog.
Manual approval requires an administrator to approve the relevant InstallPlan;
a first apply can stop while waiting. Do not blindly approve every plan.

Controller/webhook/CA injector replica settings are applied through the supported
`CertManager` CR, not by replacing the operator-managed Deployments. Schedule
replicas across failure domains in your platform policy; counts alone do not
guarantee availability.

## DNS and credentials

By default, DNS01 self-checks use cluster DNS. If split-horizon DNS requires
different resolvers, supply approved addresses rather than silently opening
public resolver access:

```hcl
certmanager_dns01_recursive_nameservers      = ["10.0.0.2:53"]
certmanager_dns01_recursive_nameservers_only = true
```

The IAM trust policy binds the cert-manager ServiceAccount subject and STS
audience. DNS writes are TXT-only in the configured zone; discovery of all zones
is not granted because the solver specifies `hostedZoneID`. See the
[upstream Route53 guidance](https://cert-manager.io/docs/configuration/acme/dns01/route53/).

After first installation or a role change, confirm controller pods received the
web-identity environment and token mount. An SA annotation does not retroactively
inject credentials into existing pods. If needed, perform a controlled rollout:

```bash
oc rollout restart deployment/cert-manager -n cert-manager
oc rollout status deployment/cert-manager -n cert-manager --timeout=5m
```

No static AWS keys are supplied by this layer. Do not add unsupported AWS
environment overrides to the CertManager CR; the operator validates allowed
override fields. Do not print token files or private key Secrets into logs.

## Certificate lifecycle and readiness

Certificates use `cert-manager.io/v1`, RSA-2048, explicit
`privateKey.rotationPolicy: Always`, `revisionHistoryLimit: 1`, and
`renewBeforePercentage: 33`. Renewal uses the actual issued lifetime, which can
differ from the requested 90 days. Workloads must reload renewed Secrets.
See [Certificate lifecycle guidance](https://cert-manager.io/docs/usage/certificate/).

Terraform waits up to 20 minutes for Certificate `Ready=True` before connecting
its Secret to the custom router. Missing delegation, denied DNS/ACME access or
bad credentials now produce a failure instead of a successful fixed sleep.
Operator-installation and NLB provisioning still have bounded staging delays;
check actual readiness if a slow installation requires another apply.

```bash
oc get clusterissuers
oc get certificates,certificaterequests,orders,challenges -A
oc describe certificate apps-wildcard -n openshift-ingress
# After fixing the underlying problem, request renewal explicitly:
cmctl renew apps-wildcard -n openshift-ingress
```

Do not delete TLS Secrets as a routine renewal mechanism. There is no supported
`cert-manager.io/manual-trigger` annotation in this workflow.

## Custom ingress and DNS delegation

The custom router is named `custom-apps`; it does not replace the ROSA router.
Its domain defaults to `apps.<hosted-zone-domain>`. The Certificate must cover
that domain and reside in `openshift-ingress`, with Secret name
`custom-apps-default-cert`. Use a dedicated domain and review wildcard DNS
ownership before applying. New records cannot overwrite existing DNS records;
import only an approved dedicated-domain record. Do not take over ROSA-owned domains.

`certmanager_ingress_route_selector` and
`certmanager_ingress_namespace_selector` further restrict router selection.
Routes relying on its wildcard certificate should not carry stale inline
certificates. Per-route custom certificates require a separately designed
renewal workflow.

For a new zone, obtain `certmanager_hosted_zone_nameservers` and delegate from the
parent/registrar. When DNSSEC is enabled, publish the generated
`certmanager_dnssec_ds_record` only after confirming signing is healthy.
DNSSEC and public DNS query logging have AWS region/partition constraints; do not
assume a commercial DNS configuration can be copied to GovCloud.

## GovCloud and zero-egress

This Terraform layer includes public Let's Encrypt ACME issuance. It is therefore
blocked for zero-egress HCP even though cert-manager itself supports private CA
and other issuers. Do not disable zero-egress merely to install the operator for
an internal PKI. Use a separately managed operator/private issuer design instead;
this layer does not yet expose an internal-PKI-only mode.

GovCloud public DNS may require a separately approved commercial DNS account and
cross-account credential architecture. This module uses its configured AWS
provider account/partition for Route53; do not assume it implements that split.
Validate the issuer, DNS hosting, cryptographic requirements and endpoint paths
before enabling public ACME. FIPS mode is not automatic FedRAMP authorization.

## Upgrade and migration cautions

Maintainers: run `terraform -chdir=tests/certmanager test` and
`uv run scripts/check-certmanager-schemas.py`. The schema check uses upstream
1.19.6 CRDs and a pinned Red Hat 1.19 operator commit; it does not emulate
admission webhooks, OLM upgrades or real DNS issuance.

- Existing community Routes users must explicitly retain
  `certmanager_enable_routes_integration = true` and supply
  `certmanager_routes_image` as an approved `@sha256:` image until migration is
  complete. Changing to the new default removes that controller and stops its
  renewals; migrate dependent Routes first.
- Removing forced public resolvers can expose split-DNS issues. Preserve your
  approved resolver list explicitly when needed.
- Key rotation and Certificate spec changes can trigger reissuance. Test staging,
  account for CA rate limits, and verify reload behavior.
- Review InstallPlans and mirrored catalog availability before upgrade. Do not
  delete/recreate the operator or its CRDs to upgrade: those CRDs own certificates.
