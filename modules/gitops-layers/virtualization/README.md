# Virtualization Layer

OpenShift Virtualization is configured via the standard `machine_pools` variable and GitOps layer settings.

## Configuration

Add a bare metal machine pool in your tfvars:

```hcl
machine_pools = [
  {
    name          = "virt"
    instance_type = "m5.metal"    # Bare metal required
    replicas      = 2
    labels = {
      "node-role.kubernetes.io/virtualization" = ""
    }
    taints = [{
      key           = "virtualization"
      value         = "true"
      schedule_type = "PreferNoSchedule"
    }]
  }
]

enable_layer_virtualization = true

# HyperConverged CR uses these for node placement
virt_node_selector = { "node-role.kubernetes.io/virtualization" = "" }
virt_tolerations   = [{ key = "virtualization", value = "true", effect = "PreferNoSchedule", operator = "Equal" }]
```

> **Why `PreferNoSchedule`?** Non-virt workloads will avoid bare metal nodes
> when other nodes are available, but VMs can schedule without needing explicit
> tolerations in each VM spec. For strict isolation (no non-virt pods at all),
> change to `NoSchedule` -- but then every VM must include a matching toleration.

See `examples/ocpvirtualization.tfvars` for a complete working example.

## Instance Types

| Type | vCPU | Memory | Monthly Cost (approx) |
|------|------|--------|----------------------|
| m5.metal | 96 | 384 GB | ~$3,350 |
| m5zn.metal | 48 | 192 GB | ~$2,400 |
| r5.metal | 96 | 768 GB | ~$4,800 |
| c5.metal | 96 | 192 GB | ~$3,100 |

## What Gets Deployed

When `enable_layer_virtualization = true`, the GitOps operator module:

1. Creates the `openshift-cnv` namespace
2. Installs OpenShift Virtualization operator (Subscription)
3. Creates HyperConverged CR with your `virt_node_selector` and `virt_tolerations`

The HyperConverged CR configures:
- virt-controller placement
- virt-api placement  
- VM workload placement (infra and workloads sections)

### Reconciliation Timeline

The HyperConverged operator is a meta-operator that deploys several sub-components
in sequence. **Full reconciliation takes 15-30 minutes** on bare metal nodes. During
this time you will see these conditions in the operator status -- they are expected
and resolve automatically:

| Condition | Cause | Resolution |
|-----------|-------|------------|
| `ReconcileFailed: namespace "openshift-virtualization-os-images" not found` | HCO creates this namespace during reconciliation | Auto-resolves within minutes |
| `SSPNotAvailable: Required CRDs are missing` | KubeVirt/CDI haven't registered CRDs yet | Resolves once KubeVirt/CDI finish deploying |
| `KubeVirtProgressing: Deploying version...` | KubeVirt is actively installing | Normal progress indicator |

Monitor progress with:

```bash
# Watch operator conditions
oc get hyperconverged kubevirt-hyperconverged -n openshift-cnv \
  -o jsonpath='{.status.conditions}' | jq .

# Watch pods coming up
oc get pods -n openshift-cnv -w

# Check CRD registration
oc get crd | grep -E 'kubevirt|cdi'
```

### Expected Pods on Bare Metal Nodes

With taints and tolerations configured, your bare metal nodes will have these pods
and **no user workloads**:

**Cluster-critical DaemonSets** (run on ALL nodes by design, cannot be tainted away):
- `node-resolver` (openshift-dns) -- DNS resolution
- `ovnkube-node` (openshift-ovn-kubernetes) -- pod networking
- `tuned` (node-tuning-operator) -- kernel tuning

**Virtualization infrastructure** (placed by HyperConverged CR `infra.nodePlacement`):
- `virt-api` -- KubeVirt API server
- `virt-controller` -- VM lifecycle controller
- `virt-handler` -- DaemonSet that manages VMs on the node
- `virt-exportproxy`, `virt-template-validator` -- supporting services

**VM boot sources** (placed by DataImportCron):
- `poller-*-image-cron-*` -- imports OS images for VM templates

If you see application pods, monitoring components, or ArgoCD on these nodes,
your taints are not configured correctly. Check `oc describe node <node>` to
verify the taint is applied.

### Creating VMs

With the default `PreferNoSchedule` taint, **VMs can be created normally**
without any special scheduling configuration. The Kubernetes scheduler will
prefer bare metal nodes for all pods, including VM virt-launcher pods, because
the `nodeSelector` in the HyperConverged CR directs virt infrastructure there.

VMs created through the console or YAML will schedule on bare metal nodes
using the standard templates -- no tolerations needed in the VM spec.

#### Strict Isolation (NoSchedule)

If you change the taint to `NoSchedule` for strict isolation, individual VMs
will need explicit tolerations and a nodeSelector to schedule:

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: my-vm
spec:
  template:
    spec:
      nodeSelector:
        node-role.kubernetes.io/virtualization: ""
      tolerations:
        - key: virtualization
          operator: Equal
          value: "true"
          effect: NoSchedule
      domain:
        # ... CPU, memory, disks ...
```

**Using the OpenShift Console UI** (only needed with `NoSchedule`):

1. Navigate to **Virtualization > VirtualMachines > Create VirtualMachine**
2. Configure your VM as usual (name, OS, resources)
3. Go to the **Scheduling** tab (or click **Customize VirtualMachine** first)
4. Under **Node selector**, add:
   - Key: `node-role.kubernetes.io/virtualization`, Value: (leave empty)
5. Under **Tolerations**, add:
   - Key: `virtualization`, Value: `true`, Effect: `NoSchedule`, Operator: `Equal`
6. Alternatively, switch to the **YAML** tab and add the `nodeSelector` and
   `tolerations` fields directly under `spec.template.spec` as shown above

## Storage

On ROSA clusters (4.10+), the `gp3-csi` StorageClass is the default and is automatically
recognized by CDI (Containerized Data Importer). No additional storage configuration is needed.

### Expected Alerts During Initial Reconciliation

After the HyperConverged CR is first created, you may see these alerts for **10-15 minutes**
while the CDI operator initializes:

- **CDINoDefaultStorageClass** -- CDI has not yet discovered the default StorageClass
- **CDINotReady** -- CDI is still initializing (cascades from the above)

These alerts resolve automatically once CDI finishes discovering StorageClasses and
populating StorageProfiles. You can verify the state with:

```bash
# Confirm gp3-csi is marked as default
oc get sc

# Check CDI StorageProfile status
oc get storageprofile gp3-csi -o yaml

# Check overall CDI health
oc get cdi -A
```

### Live Migration Limitations

EBS-backed storage (`gp3-csi`) provides `ReadWriteOnce` (RWO) volumes that attach to a
single node. This means **live migration (vMotion-style) is not supported** with the default
storage. VMs using EBS disks must be shut down before moving to a different node.

For live migration support, you need shared storage with `ReadWriteMany` (RWX) access mode,
such as:
- **OpenShift Data Foundation (ODF)** -- Ceph-based, fully integrated
- **Amazon EFS** -- NFS-based, supported via the EFS CSI driver
- **Third-party CSI drivers** with RWX support

The default `gp3-csi` configuration is suitable for development, testing, and workloads
that tolerate cold migration (stop, move, start).
