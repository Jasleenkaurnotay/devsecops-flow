terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial backend: the bucket/key/region come from envs/<env>.backend.hcl.
  #   terraform init -backend-config=envs/dev.backend.hcl
  # One state key PER ENVIRONMENT. Sharing a key between environments is the
  # exact mistake from the Oct 3 class (Terraform deleted a "foreign" cluster).
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "student-portal"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
