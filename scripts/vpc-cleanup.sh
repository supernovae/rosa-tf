#!/usr/bin/env bash
# Read-only decommission inventory. No ownership inference and no automatic deletes.
set -euo pipefail
VPC_ID="${1:?Usage: vpc-cleanup.sh <vpc-id>}"
if [[ ! "$VPC_ID" =~ ^vpc-[a-f0-9]+$ ]]; then
  echo "Invalid VPC ID" >&2
  exit 2
fi
echo "Read-only inventory. Review exact resource ownership and recovery needs before manual cleanup."
aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --output json
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --output json
