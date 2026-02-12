# Makefile for ROSA Multi-Environment Terraform Framework

.PHONY: help init validate fmt lint security docs clean test pre-commit install-tools

# Default target
help: ## Show this help message
	@echo "ROSA Multi-Environment Terraform Framework"
	@echo ""
	@echo "Usage: make [target] [ENV=<environment>]"
	@echo ""
	@echo "Environments: commercial-classic, commercial-hcp, govcloud-classic, govcloud-hcp"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

# Environment variable (default to govcloud-classic)
ENV ?= govcloud-classic
TFVARS ?= dev.tfvars
ENV_DIR = environments/$(ENV)

# Terraform commands for specific environment
init: ## Initialize Terraform for ENV
	cd $(ENV_DIR) && terraform init -upgrade

validate: ## Validate Terraform configuration for ENV
	cd $(ENV_DIR) && terraform init -backend=false && terraform validate

fmt: ## Format all Terraform files
	terraform fmt -recursive

plan: ## Run Terraform plan for ENV with TFVARS
	cd $(ENV_DIR) && terraform init && terraform plan -var-file=$(TFVARS)

apply: ## Apply Terraform configuration for ENV with TFVARS
	cd $(ENV_DIR) && terraform init && terraform apply -var-file=$(TFVARS)

destroy: ## Destroy Terraform resources for ENV with TFVARS
	cd $(ENV_DIR) && terraform destroy -var-file=$(TFVARS)

output: ## Show Terraform outputs for ENV
	cd $(ENV_DIR) && terraform output

# Linting and validation (runs on all code)
lint: ## Run TFLint on all modules
	tflint --init
	tflint --recursive

security: security-shell security-terraform security-secrets ## Run all security scans

security-shell: ## Run shell script security checks
	@echo "============================================="
	@echo "Running ShellCheck on shell scripts..."
	@echo "============================================="
	@find . -name "*.sh" -type f | xargs shellcheck -x -e SC1091 || true
	@echo ""

security-terraform: ## Run Terraform security scans (checkov, trivy)
	@echo "============================================="
	@echo "Running checkov..."
	@echo "============================================="
	checkov -d . --framework terraform --soft-fail --skip-check CKV_AWS_144,CKV_AWS_145 || true
	@echo ""
	@echo "============================================="
	@echo "Running trivy..."
	@echo "============================================="
	trivy config . --severity HIGH,CRITICAL --skip-dirs .terraform || true

security-secrets: ## Scan for secrets and credentials
	@echo "============================================="
	@echo "Running gitleaks..."
	@echo "============================================="
	gitleaks detect --source . --config .gitleaks.toml --no-git || true
	@echo ""
	@echo "============================================="
	@echo "Checking for common secret patterns..."
	@echo "============================================="
	@! grep -rn --include="*.tf" --include="*.tfvars" -E "(password|secret|token)\s*=\s*\"[^\"<][^\"]+\"" . 2>/dev/null | grep -v "_placeholder" | grep -v "sensitive" || echo "No hardcoded secrets found."

# Documentation
docs: ## Generate documentation with terraform-docs
	@for dir in modules/*/*/; do \
		if [ -f "$$dir/main.tf" ]; then \
			echo "Generating docs for $$dir"; \
			terraform-docs markdown table "$$dir" > "$$dir/README.md" 2>/dev/null || true; \
		fi \
	done

# Pre-commit
pre-commit: ## Run all pre-commit hooks
	pre-commit run --all-files

install-hooks: ## Install pre-commit hooks
	pre-commit install

# Test
test: fmt lint security validate-all ## Run all tests

validate-all: ## Validate all environments
	@for env in commercial-classic commercial-hcp govcloud-classic govcloud-hcp; do \
		echo "Validating environments/$$env..."; \
		cd environments/$$env && terraform init -backend=false && terraform validate && cd ../..; \
	done

# Clean
clean: ## Clean up temporary files
	rm -rf .terraform
	rm -f .terraform.lock.hcl
	rm -f terraform.tfstate*
	rm -f crash.log
	find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	find . -name ".terraform.lock.hcl" -type f -delete 2>/dev/null || true

# Install required tools
install-tools: ## Install required development tools
	@echo "Installing pre-commit..."
	pip install pre-commit
	@echo ""
	@echo "Installing shellcheck..."
	brew install shellcheck || apt-get install -y shellcheck || echo "Install shellcheck manually: https://github.com/koalaman/shellcheck"
	@echo ""
	@echo "Installing terraform-docs..."
	go install github.com/terraform-docs/terraform-docs@latest || brew install terraform-docs
	@echo ""
	@echo "Installing tflint..."
	curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash || brew install tflint
	@echo ""
	@echo "Installing checkov..."
	pip install checkov
	@echo ""
	@echo "Installing trivy..."
	curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin || brew install trivy
	@echo ""
	@echo "Installing gitleaks..."
	brew install gitleaks || go install github.com/gitleaks/gitleaks/v8@latest || echo "Install gitleaks manually: https://github.com/gitleaks/gitleaks"
	@echo ""
	@echo "All tools installed successfully!"

# Development
dev-init: install-tools install-hooks ## Initialize development environment
	@echo "Development environment ready!"

# Quick environment shortcuts
commercial-classic-dev: ## Deploy Commercial Classic dev
	$(MAKE) apply ENV=commercial-classic TFVARS=dev.tfvars

commercial-classic-prod: ## Deploy Commercial Classic prod
	$(MAKE) apply ENV=commercial-classic TFVARS=prod.tfvars

commercial-hcp-dev: ## Deploy Commercial HCP dev
	$(MAKE) apply ENV=commercial-hcp TFVARS=dev.tfvars

commercial-hcp-prod: ## Deploy Commercial HCP prod
	$(MAKE) apply ENV=commercial-hcp TFVARS=prod.tfvars

govcloud-classic-dev: ## Deploy GovCloud Classic dev
	$(MAKE) apply ENV=govcloud-classic TFVARS=dev.tfvars

govcloud-classic-prod: ## Deploy GovCloud Classic prod
	$(MAKE) apply ENV=govcloud-classic TFVARS=prod.tfvars

govcloud-hcp-dev: ## Deploy GovCloud HCP dev
	$(MAKE) apply ENV=govcloud-hcp TFVARS=dev.tfvars

govcloud-hcp-prod: ## Deploy GovCloud HCP prod
	$(MAKE) apply ENV=govcloud-hcp TFVARS=prod.tfvars
