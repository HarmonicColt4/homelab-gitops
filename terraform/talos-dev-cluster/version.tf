terraform {
  required_version = "~> 1.17.0"

  backend "s3" {
    bucket = "terraform"
    key    = "talos-dev-cluster/terraform.state"

    profile = "garage"
    region = "garage"

    use_path_style = true

    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    skip_metadata_api_check     = true

    use_lockfile = true
  }
}