#!/usr/bin/env bash
#------------------------------------------------------------------------------
# mirror-operators.sh - Helper script for mirroring OpenShift operators to ECR
#
# This script generates ImageSetConfiguration files for oc-mirror and provides
# guidance for mirroring Red Hat operators to a private ECR registry.
#
# Usage:
#   ./mirror-operators.sh [profile] [options]
#
# Profiles:
#   layers    - All operators used by GitOps layers (DEFAULT - recommended)
#   minimal   - Essential operators only (GitOps, Web Terminal)
#   standard  - Common operators (minimal + OADP, Logging, Monitoring)
#   full      - All certified operators (WARNING: very large, ~100GB+)
#   custom    - Generate template for custom operator selection
#
# Options:
#   --ocp-version <version>  OpenShift version (default: 4.18)
#   --ecr-url <url>          ECR registry URL (required for mirror commands)
#   --output-dir <dir>       Output directory (default: ./mirror-workspace)
#   --dry-run                Generate config only, don't execute mirror
#   --help                   Show this help message
#
# Prerequisites:
#   - oc-mirror CLI: https://docs.openshift.com/container-platform/latest/installing/disconnected_install/installing-mirroring-disconnected.html
#   - AWS CLI configured with ECR access
#   - Pull secret from https://console.redhat.com/openshift/downloads
#
# Note: oc-mirror automatically resolves operator dependencies. If operator A
# depends on operator B, B will be included in the mirror automatically.
#
# See docs/ZERO-EGRESS.md for complete workflow documentation.
#------------------------------------------------------------------------------

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PROFILE="layers"
OCP_VERSION="4.18"
ECR_URL=""
OUTPUT_DIR="./mirror-workspace"
DRY_RUN=false

#------------------------------------------------------------------------------
# Helper functions
#------------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}INFO:${NC} $1"
}

log_success() {
    echo -e "${GREEN}SUCCESS:${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
}

show_help() {
    head -35 "$0" | tail -32 | sed 's/^# //' | sed 's/^#//'
    exit 0
}

check_prerequisites() {
    local missing=()
    
    if ! command -v oc-mirror &> /dev/null; then
        missing+=("oc-mirror")
    fi
    
    if ! command -v aws &> /dev/null; then
        missing+=("aws")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        echo ""
        echo "Install oc-mirror:"
        echo "  https://docs.openshift.com/container-platform/latest/installing/disconnected_install/installing-mirroring-disconnected.html"
        echo ""
        echo "Install AWS CLI:"
        echo "  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
}

#------------------------------------------------------------------------------
# Operator lists by profile
#
# Note: oc-mirror automatically resolves operator dependencies declared in
# the ClusterServiceVersion (CSV). If operator A depends on B, B is included.
#------------------------------------------------------------------------------

# Layers profile - All operators used by GitOps layers (RECOMMENDED)
# Includes: Terminal, Virtualization, Observability (COO, Loki, Logging), OADP
get_layers_operators() {
    cat <<EOF
    # GitOps (ArgoCD) - Required for GitOps layer management
    - name: openshift-gitops-operator
      channels:
        - name: latest

    # Web Terminal - enable_layer_terminal
    - name: web-terminal
      channels:
        - name: fast

    # OpenShift Virtualization - enable_layer_virtualization
    - name: kubevirt-hyperconverged
      channels:
        - name: stable

    # Cluster Observability Operator - enable_layer_monitoring
    - name: cluster-observability-operator
      channels:
        - name: stable

    # Loki Operator - enable_layer_monitoring (log storage)
    - name: loki-operator
      channels:
        - name: stable-6.0

    # Cluster Logging - enable_layer_monitoring (log collection)
    - name: cluster-logging
      channels:
        - name: stable-6.0

    # OADP (Velero) - enable_layer_oadp
    - name: oadp-operator
      channels:
        - name: stable-1.4
EOF
}

get_minimal_operators() {
    cat <<EOF
    - name: openshift-gitops-operator
      channels:
        - name: latest
    - name: web-terminal
      channels:
        - name: fast
EOF
}

get_standard_operators() {
    cat <<EOF
    - name: openshift-gitops-operator
      channels:
        - name: latest
    - name: web-terminal
      channels:
        - name: fast
    - name: oadp-operator
      channels:
        - name: stable-1.4
    - name: cluster-logging
      channels:
        - name: stable-6.0
    - name: loki-operator
      channels:
        - name: stable-6.0
    - name: openshift-cert-manager-operator
      channels:
        - name: stable-v1
EOF
}

get_full_operators() {
    # Returns empty - full mirrors the entire catalog
    echo ""
}

get_custom_template() {
    cat <<EOF
    # Add your operators here
    # Find available operators: oc-mirror list operators --catalog registry.redhat.io/redhat/redhat-operator-index:v${OCP_VERSION}
    #
    # Example:
    # - name: operator-name
    #   channels:
    #     - name: channel-name
    #       minVersion: 1.0.0  # Optional: minimum version
    #       maxVersion: 2.0.0  # Optional: maximum version
    - name: openshift-gitops-operator
      channels:
        - name: latest
EOF
}

#------------------------------------------------------------------------------
# Generate ImageSetConfiguration
#------------------------------------------------------------------------------

generate_imageset_config() {
    local profile=$1
    local output_file=$2
    local operators=""
    
    case $profile in
        layers)
            operators=$(get_layers_operators)
            ;;
        minimal)
            operators=$(get_minimal_operators)
            ;;
        standard)
            operators=$(get_standard_operators)
            ;;
        full)
            operators=$(get_full_operators)
            ;;
        custom)
            operators=$(get_custom_template)
            ;;
        *)
            log_error "Unknown profile: $profile"
            exit 1
            ;;
    esac
    
    cat > "$output_file" <<EOF
---
# ImageSetConfiguration for ${profile} profile
# Generated by mirror-operators.sh
# OpenShift version: ${OCP_VERSION}
#
# Usage:
#   oc-mirror --config ${output_file} docker://<ecr-url>
#
# Documentation: docs/ZERO-EGRESS.md
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
storageConfig:
  local:
    path: ./mirror-data
mirror:
  platform:
    channels:
      - name: stable-${OCP_VERSION}
        minVersion: ${OCP_VERSION}.0
        maxVersion: ${OCP_VERSION}.99
        type: ocp
    graph: true
  operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:v${OCP_VERSION}
      packages:
${operators}
  additionalImages: []
  helm: {}
EOF

    log_success "Generated ImageSetConfiguration: $output_file"
    
    if [[ "$profile" == "full" ]]; then
        log_warn "Full profile mirrors the ENTIRE operator catalog (~100GB+)"
        log_warn "Consider using 'standard' or 'custom' profile instead"
    fi
}

#------------------------------------------------------------------------------
# Generate IDMS (ImageDigestMirrorSet) config
#------------------------------------------------------------------------------

generate_idms_config() {
    local ecr_url=$1
    local output_file=$2
    
    # Extract registry host from ECR URL
    local registry_host
    registry_host=$(echo "$ecr_url" | sed 's|https://||' | sed 's|/.*||')
    
    cat > "$output_file" <<EOF
---
# ImageDigestMirrorSet for ROSA Zero-Egress Clusters
# Generated by mirror-operators.sh
#
# Apply this to your cluster BEFORE enabling GitOps:
#   oc apply -f ${output_file}
#
# This redirects image pulls from registry.redhat.io to your private ECR.
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: rosa-operator-mirror
spec:
  imageDigestMirrors:
    # Red Hat Operators
    - source: registry.redhat.io/redhat
      mirrors:
        - ${registry_host}/redhat
    # OpenShift Release Images
    - source: quay.io/openshift-release-dev
      mirrors:
        - ${registry_host}/openshift-release-dev
    # OperatorHub catalog
    - source: registry.redhat.io/redhat/redhat-operator-index
      mirrors:
        - ${registry_host}/redhat/redhat-operator-index
EOF

    log_success "Generated IDMS config: $output_file"
    echo ""
    log_info "Apply IDMS to cluster:"
    echo "    oc apply -f $output_file"
}

#------------------------------------------------------------------------------
# Show mirror instructions
#------------------------------------------------------------------------------

show_mirror_instructions() {
    local config_file=$1
    local ecr_url=$2
    
    echo ""
    echo "=========================================="
    echo "Mirror Workflow Instructions"
    echo "=========================================="
    echo ""
    echo "1. Authenticate to Red Hat registry:"
    echo "   oc-mirror login registry.redhat.io"
    echo ""
    echo "2. Authenticate to ECR:"
    echo "   aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin $ecr_url"
    echo ""
    echo "3. Run mirror (disk-to-disk):"
    echo "   oc-mirror --config $config_file file://mirror-data"
    echo ""
    echo "4. Transfer mirror-data to air-gapped network (USB, S3, etc.)"
    echo ""
    echo "5. Push to ECR from air-gapped side:"
    echo "   oc-mirror --from ./mirror-data docker://$ecr_url"
    echo ""
    echo "6. Apply IDMS to cluster:"
    echo "   oc apply -f ${OUTPUT_DIR}/idms-config.yaml"
    echo ""
    echo "See docs/ZERO-EGRESS.md for detailed workflow."
    echo ""
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            layers|minimal|standard|full|custom)
                PROFILE=$1
                shift
                ;;
            --ocp-version)
                OCP_VERSION=$2
                shift 2
                ;;
            --ecr-url)
                ECR_URL=$2
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR=$2
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    log_info "Profile: $PROFILE"
    log_info "OpenShift version: $OCP_VERSION"
    log_info "Output directory: $OUTPUT_DIR"
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Generate ImageSetConfiguration
    local config_file="${OUTPUT_DIR}/imageset-config-${PROFILE}.yaml"
    generate_imageset_config "$PROFILE" "$config_file"
    
    # Generate IDMS config if ECR URL provided
    if [[ -n "$ECR_URL" ]]; then
        local idms_file="${OUTPUT_DIR}/idms-config.yaml"
        generate_idms_config "$ECR_URL" "$idms_file"
        show_mirror_instructions "$config_file" "$ECR_URL"
    else
        echo ""
        log_info "To generate IDMS config and mirror instructions, provide --ecr-url"
        echo "    $0 $PROFILE --ecr-url <your-ecr-url>"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run - no mirror operations executed"
    fi
    
    echo ""
    log_success "Done! Configuration files generated in $OUTPUT_DIR"
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
