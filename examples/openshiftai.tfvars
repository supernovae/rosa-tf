#------------------------------------------------------------------------------
# OpenShift AI Example Configuration
#
# Enables Red Hat OpenShift AI with GPU support.
# Requires a GPU machine pool and the GitOps layer stack.
#
# Usage:
#   # Phase 1: Create cluster + GPU machine pool
#   terraform apply -var-file=cluster-dev.tfvars
#
#   # Phase 2: Enable OpenShift AI
#   terraform apply -var-file=cluster-dev.tfvars -var-file=gitops-dev.tfvars
#
# Where gitops-dev.tfvars includes install_gitops = true and the settings below.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Enable the OpenShift AI Layer
#------------------------------------------------------------------------------

enable_layer_openshift_ai = true

# Sub-toggles (all default to true)
# openshift_ai_install_nfd            = true    # Disable if NFD already installed
# openshift_ai_install_gpu_operator   = true    # Disable for CPU-only AI workloads
# openshift_ai_create_s3              = true    # Disable to skip S3 bucket creation

#------------------------------------------------------------------------------
# GPU Machine Pool (add to your cluster-*.tfvars)
#
# This machine pool should be in the cluster phase tfvars since it provisions
# EC2 instances. The OpenShift AI operators automatically detect GPUs on
# these nodes via NFD.
#------------------------------------------------------------------------------

# machine_pools = [
#   # On-demand GPU pool for inference workloads
#   {
#     name          = "gpu"
#     instance_type = "g6.xlarge"    # 1x NVIDIA L4 (24 GB), 4 vCPU
#     replicas      = 1
#     labels = {
#       "node-role.kubernetes.io/gpu"    = ""
#       "nvidia.com/gpu.workload.config" = "container"
#     }
#     taints = [{
#       key           = "nvidia.com/gpu"
#       value         = "true"
#       schedule_type = "NoSchedule"
#     }]
#   },
#
#   # (Optional) Spot GPU pool for dev notebooks and batch jobs
#   # Offers 60-90% cost savings; nodes may be reclaimed
#   {
#     name          = "gpu-spot"
#     instance_type = "g4dn.xlarge"  # 1x NVIDIA T4 (16 GB), 4 vCPU
#     autoscaling   = { enabled = true, min = 0, max = 4 }
#     spot          = { enabled = true, max_price = "0.25" }
#     labels = {
#       "node-role.kubernetes.io/gpu" = ""
#       "spot"                        = "true"
#     }
#     taints = [
#       { key = "nvidia.com/gpu", value = "true", schedule_type = "NoSchedule" },
#       { key = "spot", value = "true", schedule_type = "PreferNoSchedule" }
#     ]
#   }
# ]

#------------------------------------------------------------------------------
# DataScienceCluster Component Overrides (optional)
#
# By default, core components are Managed and optional ones are Removed.
# Override individual components here.
#------------------------------------------------------------------------------

# KServe is Managed by default, which auto-installs Service Mesh and Serverless
# as prerequisites. To disable KServe (saves ~5 min install time):
#   openshift_ai_components = { kserve = "Removed" }

# openshift_ai_components = {
#   # Enable model registry for model versioning
#   modelregistry = "Managed"
#
#   # Enable distributed training operator
#   trainingoperator = "Managed"
#
#   # Disable KServe if only using ModelMesh for serving
#   # kserve = "Removed"
# }

#------------------------------------------------------------------------------
# Storage Integration (optional)
#
# OpenShift AI uses S3 for model artifacts and pipeline data.
# For shared notebook datasets, consider enabling the NetApp Storage layer
# which provides RWX (NFS) storage.
#------------------------------------------------------------------------------

# enable_layer_netapp_storage = true
# fsx_admin_password          = "YourSecurePassword123!"
