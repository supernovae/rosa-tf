# Explicit, fail-closed developer commands. Install approved tools separately.
.PHONY: help init validate fmt plan apply lint security security-shell security-terraform security-secrets test validate-all pre-commit
ENV ?= govcloud-classic
ENV_DIR = environments/$(ENV)
TFVARS ?=
PLAN ?=

help:
	@echo 'Set ENV to a deployment root; use docs/DEPLOYMENT.md for ordered overlays.'
	@echo 'Targets: init validate fmt plan apply lint security test pre-commit'

init:
	terraform -chdir=$(ENV_DIR) init -lockfile=readonly

validate:
	terraform -chdir=$(ENV_DIR) init -backend=false -lockfile=readonly
	terraform -chdir=$(ENV_DIR) validate

fmt:
	terraform fmt -recursive

plan:
	@test -n "$(TFVARS)" && test -n "$(PLAN)" || (echo 'Set TFVARS and PLAN explicitly; protect the saved plan as a secret.'; exit 1)
	terraform -chdir=$(ENV_DIR) init -lockfile=readonly
	terraform -chdir=$(ENV_DIR) plan -var-file="$(TFVARS)" -out="$(PLAN)"

apply:
	@test -n "$(PLAN)" || (echo 'Set PLAN to the reviewed saved plan; this applies that exact plan.'; exit 1)
	terraform -chdir=$(ENV_DIR) apply "$(PLAN)"

lint:
	tflint --init
	tflint --recursive

security: security-shell security-terraform security-secrets

security-shell:
	git ls-files -z '*.sh' | xargs -0 shellcheck -x -e SC1091

security-terraform:
	checkov --config-file .checkov.yml
	grype dir:. --fail-on high

security-secrets:
	gitleaks detect --source . --config .gitleaks.toml

pre-commit:
	pre-commit run --all-files

test: lint security validate-all
	uv run scripts/check-examples.py
	python3 -m unittest discover -s tests/release -p 'test_*.py'

validate-all:
	@set -e; for target in commercial-classic commercial-hcp govcloud-classic govcloud-hcp; do \
		terraform -chdir=environments/$$target init -backend=false -lockfile=readonly; \
		terraform -chdir=environments/$$target validate; \
	done
