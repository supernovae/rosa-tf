#!/usr/bin/env bash
# ===========================================================================
# VPC Cleanup Script
# ===========================================================================
#
# Cleans up orphaned AWS resources (ENIs, security groups) left behind
# after a ROSA cluster is destroyed. Scoped to the specific cluster name
# to avoid interfering with other workloads in the same VPC.
#
# Usage:
#   ./vpc-cleanup.sh <vpc-id> <cluster-name>
#
# Called automatically by Terraform during destroy via local-exec.
# ===========================================================================
set -euo pipefail

VPC_ID="${1:?Usage: vpc-cleanup.sh <vpc-id> <cluster-name>}"
CLUSTER_NAME="${2:?Usage: vpc-cleanup.sh <vpc-id> <cluster-name>}"

echo ""
echo "============================================="
echo "  VPC Cleanup: $CLUSTER_NAME"
echo "============================================="
echo ""
echo "  VPC:     $VPC_ID"
echo "  Cluster: $CLUSTER_NAME"
echo ""

# ---------------------------------------------------------------------------
# Wait for initial AWS cleanup (load balancers, ENIs, etc.)
# ---------------------------------------------------------------------------
echo "  Waiting 2 minutes for AWS to clean up cluster resources..."
sleep 120

# ---------------------------------------------------------------------------
# Clean up orphaned ENIs belonging to this cluster
#
# Only deletes available (unattached) ENIs whose description contains the
# cluster name. ROSA NLBs use the naming pattern:
#   "ELB net/<cluster-name>-<infra-id>-int/..."
#
# Scoping to the cluster name ensures we never touch ENIs belonging to
# other clusters or workloads in the same VPC.
# ---------------------------------------------------------------------------
echo ""
echo "  Checking for orphaned ENIs (cluster: $CLUSTER_NAME)..."
for attempt in 1 2 3; do
  ENIS=$(aws ec2 describe-network-interfaces \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=available" \
    --query "NetworkInterfaces[?contains(Description, '$CLUSTER_NAME')].NetworkInterfaceId" \
    --output text 2>/dev/null || echo "")

  if [ -n "$ENIS" ] && [ "$ENIS" != "None" ]; then
    echo "  Found orphaned ENIs (attempt $attempt): $ENIS"
    for ENI in $ENIS; do
      echo "    Deleting ENI: $ENI"
      aws ec2 delete-network-interface --network-interface-id "$ENI" 2>/dev/null || true
    done
    sleep 10
  else
    echo "  No orphaned ENIs found for cluster '$CLUSTER_NAME'."
    break
  fi
done

# ---------------------------------------------------------------------------
# Clean up orphaned security groups belonging to this cluster
#
# Only targets SGs that match the cluster by:
#   1. Name tag containing the cluster name (*<cluster-name>*)
#   2. Group name prefix matching ROSA's infra-id pattern (<cluster-name>-*)
#
# Each SG is checked for active ENI attachments before deletion.
# Scoping prevents accidentally deleting SGs belonging to other clusters
# or workloads sharing the VPC.
# ---------------------------------------------------------------------------
echo ""
echo "  Checking for orphaned security groups (cluster: $CLUSTER_NAME)..."
for attempt in 1 2 3; do
  # Find SGs matching this cluster by Name tag
  TAGGED_SGS=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*${CLUSTER_NAME}*" \
    --query "SecurityGroups[?GroupName!='default'].GroupId" \
    --output text 2>/dev/null || echo "")

  # Also find SGs matching by group name prefix (ROSA infra-id pattern)
  NAMED_SGS=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=${CLUSTER_NAME}-*" \
    --query "SecurityGroups[].GroupId" \
    --output text 2>/dev/null || echo "")

  # Combine and deduplicate
  SGS=$(echo "$TAGGED_SGS $NAMED_SGS" | xargs -n1 2>/dev/null | sort -u | xargs 2>/dev/null || echo "")

  if [ -n "$SGS" ] && [ "$SGS" != "None" ]; then
    echo "  Found security groups (attempt $attempt): $SGS"
    for SG in $SGS; do
      # Only delete if no ENIs are using it
      IN_USE=$(aws ec2 describe-network-interfaces \
        --filters "Name=group-id,Values=$SG" \
        --query 'NetworkInterfaces[0].NetworkInterfaceId' \
        --output text 2>/dev/null || echo "None")

      if [ "$IN_USE" = "None" ] || [ -z "$IN_USE" ]; then
        echo "    Deleting unused SG: $SG"
        aws ec2 delete-security-group --group-id "$SG" 2>/dev/null || true
      else
        echo "    SG $SG still in use by ENI $IN_USE, skipping."
      fi
    done
    sleep 10
  else
    echo "  No orphaned security groups found for cluster '$CLUSTER_NAME'."
    break
  fi
done

echo ""
echo "============================================="
echo "  VPC Cleanup complete."
echo "============================================="
echo ""
