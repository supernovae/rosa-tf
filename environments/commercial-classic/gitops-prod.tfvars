# Phase 2 overlay on the SAME private cluster tfvars and state.
# Verify the endpoint/CA, credentials and regional operator catalogs first.
# Add reviewed layer overlays from examples/ explicitly; no layer is implicit.
install_gitops              = true
enable_layer_terminal       = false
enable_layer_oadp           = false
enable_layer_virtualization = false
enable_layer_monitoring     = false
enable_layer_certmanager    = false
enable_layer_netapp_storage = false
enable_layer_efs_storage    = false
