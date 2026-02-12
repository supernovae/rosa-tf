# Contributing to ROSA Classic GovCloud Terraform Module

Thank you for your interest in contributing to this project! This document provides guidelines and instructions for contributing.

## Code of Conduct

Please be respectful and constructive in all interactions. We're all working toward the same goal of making this module better.

## Getting Started

### Prerequisites

- Terraform >= 1.4.6
- AWS CLI with GovCloud access
- Go >= 1.21 (for some tools)
- Python >= 3.9 (for pre-commit and checkov)

### Setting Up Development Environment

1. Clone the repository:

```bash
git clone git@github.com:supernovae/rosa-tf.git
cd rosa-tf
```

2. Install development tools:

```bash
make install-tools
```

3. Install pre-commit hooks:

```bash
make install-hooks
```

4. Verify setup:

```bash
make test
```

## Development Workflow

### Making Changes

1. Create a feature branch:

```bash
git checkout -b feature/my-feature
```

2. Make your changes following the coding standards below

3. Run tests and linting:

```bash
make test
```

4. Commit your changes:

```bash
git add .
git commit -m "feat: add my feature"
```

5. Push and create a pull request:

```bash
git push origin feature/my-feature
```

### Commit Messages

We follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `style:` - Code style changes (formatting, etc.)
- `refactor:` - Code refactoring
- `test:` - Adding or updating tests
- `chore:` - Maintenance tasks

Examples:

```
feat: add support for custom machine pool labels
fix: correct IAM policy for GovCloud partition
docs: update README with SSM port forwarding examples
```

## Coding Standards

### Terraform Style

- Use `snake_case` for resource names and variables
- Always include descriptions for variables and outputs
- Group related resources with comments
- Use locals for complex expressions
- Pin provider versions

### File Organization

```
modules/
  module-name/
    main.tf         # Primary resources
    variables.tf    # Input variables
    outputs.tf      # Output values
    versions.tf     # Provider requirements
    README.md       # Module documentation
```

### Variable Naming

- Use descriptive names that indicate purpose
- Include units in names when applicable (e.g., `timeout_seconds`)
- Boolean variables should use `enable_*` or `is_*` prefix

### Documentation

- Update README.md when adding features
- Include examples in documentation
- Document all variables and outputs
- Add inline comments for complex logic

## Testing

### Local Testing

```bash
# Format and validate
make fmt validate

# Run linting
make lint

# Run security scans
make security

# Run all tests
make test
```

### Integration Testing

For testing with a real cluster:

```bash
# Commercial: Set service account credentials
export TF_VAR_rhcs_client_id="your-client-id"
export TF_VAR_rhcs_client_secret="your-client-secret"

# GovCloud: Set offline OCM token
export TF_VAR_ocm_token="your-token"

# Test minimal example
cd examples/minimal
terraform init
terraform plan
```

## Security

### No Secrets in Code

- Never commit secrets, tokens, or credentials
- Use environment variables for sensitive values
- Check `.gitignore` excludes sensitive files
- Run `detect-secrets scan` before committing

### Security Scanning

All PRs are automatically scanned for:

- Hardcoded credentials
- Insecure configurations
- AWS security best practices

## Pull Request Process

1. Ensure all tests pass (`make test`)
2. Update documentation if needed
3. Add relevant labels to your PR
4. Request review from maintainers
5. Address review feedback
6. Squash and merge when approved

### Automated CI Checks

All PRs automatically run the following checks via GitHub Actions:

| Check | Description |
|-------|-------------|
| `terraform fmt` | Code formatting validation |
| `terraform validate` | Syntax and configuration validation |
| `tflint` | Terraform best practices linting |
| `checkov` | Policy-as-code security scanning |
| `trivy` | Vulnerability and misconfiguration scanning (tfsec successor) |

**All checks must pass before merge.** If a check fails, review the CI output and fix the issues locally before pushing updates.

### PR Checklist

- [ ] Tests pass locally (`make test`)
- [ ] Pre-commit hooks pass
- [ ] CI checks pass (automated)
- [ ] Documentation updated
- [ ] No secrets in code
- [ ] Follows coding standards
- [ ] Commit messages follow convention

## Release Process

Releases are managed by maintainers following semantic versioning:

- **Major** (x.0.0): Breaking changes
- **Minor** (0.x.0): New features, backward compatible
- **Patch** (0.0.x): Bug fixes, backward compatible

## Getting Help

- Open an issue for bugs or feature requests
- Check existing issues before creating new ones
- Provide detailed information in bug reports

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
