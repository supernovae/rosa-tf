#------------------------------------------------------------------------------
# OpenShift AI Example Configuration
#
# Enables Red Hat OpenShift AI 3.5 with GPU and Kueue support.
# Requires OpenShift 4.19.9+, a GPU machine pool, cert-manager, and GitOps.
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

# Sub-toggles
# openshift_ai_install_nfd            = true    # Disable if NFD already installed
# openshift_ai_install_gpu_operator   = true    # Disable for CPU-only AI workloads
# openshift_ai_install_kueue          = true    # Disable if Kueue operator already installed
# openshift_ai_kueue_auto_create_queues = true  # Set false to manage queue resources yourself
# openshift_ai_create_s3              = false   # Enable only if using AI Pipelines (default: false)
# openshift_ai_kserve_raw_deployment_service_config = "Headless" # Use Headed when a routable ClusterIP is required

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
# RHOAI 3.5 DSC API v2 top-level components:
#   aigateway, dashboard, workbenches, aipipelines, kserve, kueue,
#   trainingoperator, trainer, ray, trustyai, modelregistry, feastoperator,
#   llamastackoperator (deprecated), ogx, mlflowoperator, sparkoperator,
#   mcplifecycleoperator
# Subcomponent override keys:
#   models_as_a_service, batch_gateway, argo_workflows_controllers, nim, wva
#
# Default-Managed: dashboard, workbenches, aipipelines, kserve, ray, modelregistry
# Default-Unmanaged: kueue (integrates with external Red Hat build of Kueue Operator)
# Default-Removed: all other components and subcomponents, except KServe NIM and
#   the bundled Argo Workflows controllers, which are Managed when their parents are enabled
#------------------------------------------------------------------------------

# openshift_ai_components = {
#   # Enable MLflow for experiment tracking (requires external DB/S3)
#   mlflowoperator = "Managed"
#
#   # Enable feature store (requires external infra)
#   feastoperator = "Managed"
#
#   # Enable OGX (the RHOAI 3.5 replacement for Llama Stack)
#   # Requires Service Mesh 3, cert-manager, GPU nodes, and S3-compatible storage.
#   ogx = "Managed"
#
#   # Enable Kubeflow Trainer v2 (requires the JobSet Operator)
#   trainer = "Managed"
#
#   # Enable Models-as-a-Service through the new AI Gateway component
#   # aigateway           = "Managed"
#   # models_as_a_service = "Managed"
#
#   # Disable KServe if not serving models
#   # kserve = "Removed"
#
#   # Disable pipelines if not using them (avoids S3 requirement)
#   # aipipelines = "Removed"
#
#   # Disable Kueue integration (set to Removed if Kueue operator not installed)
#   # kueue = "Removed"
# }

#------------------------------------------------------------------------------
# Storage Integration (optional)
#
# RHOAI 3.5 model serving uses OCI images or PVC — S3 is NOT required for
# serving models. S3 is only needed for AI Pipelines artifact storage.
#
# To enable pipelines with S3:
#   openshift_ai_create_s3  = true
#   openshift_ai_components = { aipipelines = "Managed" }  # (Managed by default)
#
# For shared notebook datasets, consider enabling the NetApp Storage layer
# which provides RWX (NFS) storage.
#------------------------------------------------------------------------------

# openshift_ai_create_s3      = true   # Only for AI Pipelines
# enable_layer_netapp_storage  = true
# fsx_admin_password           = "YourSecurePassword123!"
