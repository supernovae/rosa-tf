#!/usr/bin/env bash
# Run from modules/cluster/rosa-classic or modules/cluster/rosa-hcp after init.
# Terraform and every provider are mocked by tests/bootstrap.tftest.hcl.
set -euo pipefail

"${TERRAFORM_BIN:-terraform}" test -json -verbose | jq -s -e '
  . as $events |
  [ .[] | select(.type == "test_summary") ] as $summaries |
  [ .[] | select(.type == "test_plan" and .["@testrun"] == "legacy_migration") ] as $plans |
  if ($summaries | length) != 1 or $summaries[0].test_summary.status != "pass" then
    error("Bootstrap tests failed: " + ([ $events[] | select(.type == "diagnostic") | .diagnostic ] | tojson))
  elif ($plans | length) != 1 then
    error("Missing legacy migration plan")
  else
    $plans[0].test_plan.resource_changes as $changes |
    [ $changes[] | select(.change.actions == ["forget"]) | .address ] as $forgotten |
    if ($forgotten | index("rhcs_identity_provider.htpasswd[0]")) == null or
       ($forgotten | index("rhcs_group_membership.cluster_admin[0]")) == null then
      error("Migration must forget both legacy admin resources without deleting them")
    elif any($changes[]; (.change.actions | index("delete")) != null) then
      error("Migration unexpectedly destroys or replaces a resource")
    else
      "Bootstrap tests passed; migration preserves existing resources and forgets legacy admin ownership."
    end
  end
'
