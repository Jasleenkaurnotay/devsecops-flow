data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.app_name}-${var.environment}"
}

# Cheap, free-tier-friendly resources that still exercise every check:
# fmt, validate, tflint, checkov, plan-JSON scan, apply, drift.
module "app_bucket" {
  source = "./modules/app_bucket"

  bucket_name        = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}"
  log_retention_days = var.log_retention_days
}

resource "aws_ssm_parameter" "app_config" {
  name        = "/${var.app_name}/${var.environment}/bucket_name"
  description = "Bucket the ${var.environment} app writes to."
  type        = "String"
  value       = module.app_bucket.bucket_name
}

# Only the dev state owns the repo. Build once, push once, promote the same digest.
resource "aws_ecr_repository" "app" {
  count = var.create_ecr ? 1 : 0

  name                 = var.app_name
  image_tag_mutability = "IMMUTABLE" # a tag (the commit SHA) can never be overwritten

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "keep_last_20" {
  count      = var.create_ecr ? 1 : 0
  repository = aws_ecr_repository.app[0].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}
