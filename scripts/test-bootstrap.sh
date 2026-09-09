#!/usr/bin/env bash
# Fresh-deployment bootstrap tests only; 2.0 has no in-place 1.x migration contract.
set -euo pipefail
"${TERRAFORM_BIN:-terraform}" test -no-color
