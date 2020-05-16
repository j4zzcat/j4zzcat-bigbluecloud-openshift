provider "ibm" {
  region     = var.region_name
  generation = 2
}

locals {
  repo_dir      = "/h/repo"

  scripts_dir   = "${local.repo_dir}/lib/scripts/ubuntu_18"
  helpers_dir   = "${local.repo_dir}/lib/helpers"
  terraform_dir = "${local.repo_dir}/lib/terraform"
  hosts_file    = "${local.repo_dir}"
}
