# OpenShift AI Layer

Provisions the full Red Hat OpenShift AI (RHOAI) stack with GPU support:

- **Node Feature Discovery (NFD)** -- auto-detects GPU hardware on nodes
- **NVIDIA GPU Operator** -- installs drivers, device plugin, container toolkit
- **Red Hat OpenShift AI** -- DataScienceCluster with ML/AI components
- **S3 Data Storage** -- bucket for model artifacts and pipeline data (optional)

## Quick Start

```bash
# Phase 1: Create cluster with GPU machine pool
terraform apply -var-file=cluster-dev.tfvars

# Phase 2: Enable OpenShift AI
terraform apply -var-file=cluster-dev.tfvars -var-file=gitops-dev.tfvars
```

Minimal `gitops-dev.tfvars`:

```hcl
install_gitops             = true
enable_layer_openshift_ai  = true
```

GPU machine pool in `cluster-dev.tfvars`:

```hcl
machine_pools = [
  {
    name          = "gpu"
    instance_type = "g6.xlarge"
    replicas      = 1
    labels        = { "node-role.kubernetes.io/gpu" = "" }
    taints        = [{ key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" }]
  }
]
```

## Architecture

```
+-------------------------------------------------------------+
|  Phase 2: Kubernetes Operators                              |
|                                                             |
|  openshift-nfd          nvidia-gpu-operator                 |
|  +------------------+   +-----------------------------+     |
|  | NFD Operator     |   | NVIDIA GPU Operator         |     |
|  | NodeFeature      |-->| ClusterPolicy               |     |
|  | Discovery CR     |   | (drivers, device plugin,    |     |
|  +------------------+   |  toolkit, DCGM exporter)    |     |
|                         +-----------------------------+     |
|                                    |                        |
|  redhat-ods-operator               v                        |
|  +------------------+   redhat-ods-applications             |
|  | RHOAI Operator   |   +-----------------------------+     |
|  | DSCInitialization|-->| DataScienceCluster          |     |
|  +------------------+   | Dashboard, Workbenches,     |     |
|                         | Pipelines, KServe, Ray,     |     |
|                         | CodeFlare, Kueue            |     |
|                         +-----------------------------+     |
+-------------------------------------------------------------+
```

## Inputs

| Name                               | Type        | Default   | Description                                    |
|------------------------------------|-------------|-----------|------------------------------------------------|
| `enable_layer_openshift_ai`        | bool        | `false`   | Enable the OpenShift AI layer                  |
| `openshift_ai_install_nfd`         | bool        | `true`    | Install NFD operator (disable if already present)|
| `openshift_ai_install_gpu_operator`| bool        | `true`    | Install NVIDIA GPU Operator (disable for CPU-only)|
| `openshift_ai_create_s3`           | bool        | `true`    | Create S3 bucket for data connections          |
| `openshift_ai_enable_fips`         | bool        | GovCloud: `true` | FIPS mode for GPU operator             |
| `openshift_ai_components`          | map(string) | `{}`      | Override DataScienceCluster component states    |
| `openshift_ai_data_retention_days` | number      | `0`       | S3 lifecycle expiration (0 = no expiration)    |

## DataScienceCluster Components

Default component states (override via `openshift_ai_components`):

| Component            | Default   | Description                           |
|----------------------|-----------|---------------------------------------|
| `dashboard`          | Managed   | OpenShift AI web dashboard            |
| `workbenches`        | Managed   | JupyterLab notebook environments      |
| `datasciencepipelines` | Managed | Kubeflow Pipelines 2.0 for ML workflows |
| `modelmeshserving`   | Managed   | Multi-model serving (ModelMesh)       |
| `kserve`             | Managed   | Single-model serving (KNative)        |
| `ray`                | Managed   | Distributed computing (Ray clusters)  |
| `codeflare`          | Managed   | Distributed workload orchestration    |
| `kueue`              | Managed   | Job queue and quota management        |
| `trustyai`           | Removed   | AI model explainability (opt-in)      |
| `trainingoperator`   | Removed   | Distributed training (opt-in)         |
| `modelregistry`      | Removed   | Model versioning registry (opt-in)    |

Example override to disable KServe and enable model registry:

```hcl
openshift_ai_components = {
  kserve        = "Removed"
  modelregistry = "Managed"
}
```

## AWS GPU Instance Type Reference

All AWS GPU instances use NVIDIA GPUs. NFD auto-discovers the hardware and
the NVIDIA GPU Operator handles driver installation automatically.

### Inference Tier (Cost-Effective)

Best for model serving, inference endpoints, and light fine-tuning.

| Instance      | GPUs | GPU Model   | GPU Mem | vCPU | Approx $/hr | Spot   | GovCloud |
|---------------|------|-------------|---------|------|-------------|--------|----------|
| g4dn.xlarge   | 1    | NVIDIA T4   | 16 GB   | 4    | $0.53       | Good   | Yes      |
| g4dn.2xlarge  | 1    | NVIDIA T4   | 16 GB   | 8    | $0.75       | Good   | Yes      |
| g4dn.12xlarge | 4    | NVIDIA T4   | 64 GB   | 48   | $3.91       | Good   | Yes      |
| g6.xlarge     | 1    | NVIDIA L4   | 24 GB   | 4    | $0.80       | Good   | us-gov-east |
| g6.2xlarge    | 1    | NVIDIA L4   | 24 GB   | 8    | $0.98       | Good   | us-gov-east |
| g6.12xlarge   | 4    | NVIDIA L4   | 96 GB   | 48   | $4.60       | Fair   | us-gov-east |
| g6e.xlarge    | 1    | NVIDIA L40S | 48 GB   | 4    | $1.86       | Fair   | No       |
| g6e.12xlarge  | 4    | NVIDIA L40S | 192 GB  | 48   | $9.69       | Fair   | No       |

### Training Tier (High Performance)

Best for model training, fine-tuning, and distributed workloads.

| Instance       | GPUs | GPU Model    | GPU Mem  | vCPU | Approx $/hr | Spot    | GovCloud  |
|----------------|------|--------------|----------|------|-------------|---------|-----------|
| p3.2xlarge     | 1    | NVIDIA V100  | 16 GB    | 8    | $3.06       | Limited | Limited   |
| p3.8xlarge     | 4    | NVIDIA V100  | 64 GB    | 32   | $12.24      | Limited | Limited   |
| p3.16xlarge    | 8    | NVIDIA V100  | 128 GB   | 64   | $24.48      | Rare    | Limited   |
| p4d.24xlarge   | 8    | NVIDIA A100  | 320 GB   | 96   | $32.77      | Rare    | No        |
| p5.48xlarge    | 8    | NVIDIA H100  | 640 GB   | 192  | $98.32      | No      | No        |

### AWS Custom Accelerators (No GPU Operator Needed)

These use AWS-designed chips, not NVIDIA GPUs. They do NOT require the
NVIDIA GPU Operator. Set `openshift_ai_install_gpu_operator = false` and
use the Neuron SDK container images instead.

| Instance      | Chips | Chip Type     | Accelerator Mem | Use Case              |
|---------------|-------|---------------|------------------|-----------------------|
| inf2.xlarge   | 2     | Inferentia2   | 32 GB            | Cost-optimized inference |
| trn1.2xlarge  | 1     | Trainium      | 32 GB            | Cost-optimized training  |

## GovCloud GPU Availability

GovCloud has limited GPU instance availability:

| Instance Family | us-gov-west-1 | us-gov-east-1 |
|-----------------|---------------|---------------|
| g4dn            | Yes           | Yes           |
| g6              | No            | Yes           |
| g6e             | No            | No            |
| p3              | Limited       | Limited       |
| p4d / p5        | No            | No            |
| inf2 / trn1     | No            | No            |

**Recommendation for GovCloud**: Start with `g4dn.xlarge` for dev/test. For
production inference, request `g6` capacity in `us-gov-east-1`. For training
workloads, use `p3.2xlarge` or `p3.8xlarge` where available.

## Spot Instance Guidance

GPU Spot instances offer 60-90% savings but can be reclaimed at any time.

| Instance Family | Spot Reliability | Recommended Use                       |
|-----------------|-----------------|---------------------------------------|
| g4dn            | High            | Dev notebooks, batch inference        |
| g6              | High            | Dev notebooks, batch inference        |
| g6e             | Medium          | Non-critical fine-tuning              |
| p3              | Low-Medium      | Checkpointed training only            |
| p4d / p5        | Very Low        | Not recommended for Spot              |

Example Spot GPU machine pool:

```hcl
machine_pools = [
  {
    name          = "gpu-spot"
    instance_type = "g4dn.xlarge"
    autoscaling   = { enabled = true, min = 0, max = 4 }
    spot          = { enabled = true, max_price = "0.25" }
    labels = {
      "node-role.kubernetes.io/gpu" = ""
      "spot"                        = "true"
    }
    taints = [
      { key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" },
      { key = "spot", value = "true", schedule_type = "PreferNoSchedule" }
    ]
  }
]
```

## Driver Mapping

NFD discovers hardware features on each node and labels them. The NVIDIA
GPU Operator reads these labels and automatically installs the correct
driver version for the detected GPU model.

```
Node boots --> NFD discovers GPU (PCI vendor 10de = NVIDIA)
          --> NFD labels node: feature.node.kubernetes.io/pci-10de.present=true
          --> GPU Operator detects label
          --> Installs matching NVIDIA driver via DaemonSet
          --> Device plugin registers nvidia.com/gpu resource
          --> Pods can request: resources.limits.nvidia.com/gpu: 1
```

No manual driver management is needed. The GPU Operator handles driver
lifecycle including upgrades (controlled by `ClusterPolicy.spec.driver.upgradePolicy`).

## AMD GPU Support (On-Premises Only)

AWS does not offer AMD GPU instances. AMD GPU support applies to on-premises
or hybrid deployments with AMD Instinct accelerators.

**Supported hardware**: MI210, MI250, MI300X, MI325X, MI350X, MI355X

**Required operators** (from certified-operators catalog):
1. Node Feature Discovery (NFD) -- same as NVIDIA path
2. Kernel Module Management (KMM) -- required for AMD driver compilation
3. AMD GPU Operator -- manages ROCm drivers and device plugin

**To use AMD GPUs**:
1. Set `openshift_ai_install_gpu_operator = false` (skips NVIDIA operator)
2. Install the AMD GPU Operator and KMM manually or via a custom GitOps layer
3. See [AMD GPU Operator docs](https://instinct.docs.amd.com/projects/gpu-operator/en/main/installation/openshift-olm.html)

## Storage Integration

OpenShift AI workbenches and pipelines need persistent storage:

- **Workbenches**: RWO storage for notebook data (default `gp3-csi` works)
- **Pipelines**: RWO for pipeline metadata
- **Model serving**: S3 for model artifacts (this module creates the bucket)
- **Shared datasets**: RWX storage if multiple notebooks share data

For shared datasets, enable the [NetApp Storage layer](../netapp-storage/README.md)
which provides `fsx-ontap-nfs-rwx` (RWX via NFS).

## FedRAMP / GovCloud Notes

- `openshift_ai_enable_fips = true` (default in GovCloud) configures the
  GPU Operator's ClusterPolicy for FIPS-compliant mode
- S3 bucket uses KMS encryption when `kms_key_arn` is provided
- IAM roles use `data.aws_partition.current.partition` for GovCloud ARNs
- All operators install from Red Hat's certified catalog (no third-party)
- Bucket is created via CloudFormation with `DeletionPolicy: Retain`
