# Optional overlay for any of the four roots, AFTER cluster/GitOps bootstrap.
# Copy examples/gitops-workload to your own reviewed Git repository; customize URL/path.
# Do not point the Application at the platform layer directory.
install_gitops       = true
gitops_repo_url      = "https://git.example.mil/team/workloads.git"
gitops_repo_path     = "apps"
gitops_repo_revision = "main" # Manual sync; automated sync requires a reviewed commit SHA.
gitops_application = {
  enabled     = true
  namespace   = "team-a"
  view_groups = ["team-a-viewers"]
  sync_groups = ["team-a-deployers"]
  automated   = false
  prune       = false
  self_heal   = false
}
