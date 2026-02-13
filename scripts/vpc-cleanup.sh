#!/usr/bin/env bash
# ===========================================================================
# VPC Cleanup Script
# ===========================================================================
#
# Cleans up orphaned AWS resources (ENIs, security groups) left behind
# after a ROSA cluster is destroyed. Called automatically by Terraform
# during destroy via local-exec.
#
# WORKAROUND: ROSA's uninstaller has a known bug where it leaves behind
# security groups that are not properly cleaned up. These orphaned SGs
# block VPC/subnet deletion and cause terraform destroy to hang. This
# script works around the issue by:
#   1. Cleaning cluster-scoped resources (tagged/named with cluster name)
#   2. Falling back to removing any non-default, unused SGs in the VPC
#
# The fallback is safe because:
#   - It only runs AFTER the cluster has been fully destroyed
#   - It checks every SG for active ENI attachments before deleting
#   - SGs belonging to other clusters/workloads will still have ENIs
#   - Only truly orphaned (zero attachment) SGs are removed
#
# Usage:
#   ./vpc-cleanup.sh <vpc-id> <cluster-name>
#
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
# Pass 1 (cluster-scoped): Target SGs that match the cluster by:
#   1. Name tag containing the cluster name (*<cluster-name>*)
#   2. Group name prefix matching ROSA's infra-id pattern (<cluster-name>-*)
#
# Pass 2 (fallback for ROSA uninstaller bug): Target any non-default SG
# in the VPC that has ZERO active ENI attachments. This catches SGs left
# behind by the ROSA uninstaller that are stripped of identifying tags
# during cluster teardown.
#
# Safety: Every SG is checked for active ENI attachments before deletion.
# SGs in use by other clusters or workloads are never touched.
# ---------------------------------------------------------------------------
echo ""
echo "  Checking for orphaned security groups (cluster: $CLUSTER_NAME)..."
DELETED_SGS=""

# --- Pass 1: Cluster-scoped SGs (by name tag and group name) ---
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
    echo "  Found cluster-scoped security groups (attempt $attempt): $SGS"
    for SG in $SGS; do
      # Only delete if no ENIs are using it
      IN_USE=$(aws ec2 describe-network-interfaces \
        --filters "Name=group-id,Values=$SG" \
        --query 'NetworkInterfaces[0].NetworkInterfaceId' \
        --output text 2>/dev/null || echo "None")

      if [ "$IN_USE" = "None" ] || [ -z "$IN_USE" ]; then
        echo "    Deleting unused SG: $SG"
        aws ec2 delete-security-group --group-id "$SG" 2>/dev/null || true
        DELETED_SGS="$DELETED_SGS $SG"
      else
        echo "    SG $SG still in use by ENI $IN_USE, skipping."
      fi
    done
    sleep 10
  else
    echo "  No cluster-scoped security groups found."
    break
  fi
done

# --- Pass 2: Fallback for untagged orphan SGs (ROSA uninstaller bug) ---
#
# ROSA's uninstaller sometimes leaves behind security groups that have
# been stripped of their cluster-identifying tags during teardown. These
# SGs block VPC and subnet deletion. This pass finds any non-default SG
# in the VPC with zero ENI attachments and removes it.
#
# This is safe because:
#   - The cluster is already fully destroyed at this point
#   - SGs actively used by other clusters will have ENI attachments
#   - We skip any SG already deleted in Pass 1
#   - We skip the VPC default SG
# ---------------------------------------------------------------------------
echo ""
echo "  Checking for untagged orphan security groups (ROSA uninstaller bug workaround)..."

ALL_SGS=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[?GroupName!='default'].GroupId" \
  --output text 2>/dev/null || echo "")

if [ -n "$ALL_SGS" ] && [ "$ALL_SGS" != "None" ]; then
  ORPHAN_COUNT=0
  for SG in $ALL_SGS; do
    # Skip if already deleted in Pass 1
    case "$DELETED_SGS" in
      *"$SG"*) continue ;;
    esac

    # Check if any ENIs are attached
    IN_USE=$(aws ec2 describe-network-interfaces \
      --filters "Name=group-id,Values=$SG" \
      --query 'NetworkInterfaces[0].NetworkInterfaceId' \
      --output text 2>/dev/null || echo "None")

    if [ "$IN_USE" = "None" ] || [ -z "$IN_USE" ]; then
      # Get SG details for logging before deleting
      SG_NAME=$(aws ec2 describe-security-groups \
        --group-ids "$SG" \
        --query 'SecurityGroups[0].GroupName' \
        --output text 2>/dev/null || echo "unknown")

      echo "    Deleting orphan SG: $SG (name: $SG_NAME) [no ENI attachments]"
      aws ec2 delete-security-group --group-id "$SG" 2>/dev/null || true
      ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
    fi
  done

  if [ "$ORPHAN_COUNT" -eq 0 ]; then
    echo "  No untagged orphan security groups found."
  else
    echo "  Removed $ORPHAN_COUNT orphan security group(s) (ROSA uninstaller bug)."
  fi
else
  echo "  No non-default security groups remain in VPC."
fi

echo ""
echo "============================================="
echo "  VPC Cleanup complete."
echo "============================================="
echo ""
