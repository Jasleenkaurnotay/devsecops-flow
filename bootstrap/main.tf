# ONE-TIME bootstrap, applied by you from your laptop (not by a workflow):
# creates the GitHub OIDC provider and the IAM roles your workflows assume.
#   cd bootstrap && terraform init && terraform apply \
#     -var github_owner=<you> -var github_repo=<repo> -var state_bucket=<bucket>
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "github_owner" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "state_bucket" {
  type        = string
  description = "Existing S3 bucket that holds Terraform state."
}

variable "subject_prefix" {
  type        = string
  default     = ""
  description = <<-EOT
    Prefix of the token 'sub' claim before the colon-separated suffix.
    Empty = classic format  repo:<owner>/<repo>.
    If your repo uses GitHub's immutable subject format (repos created, renamed or
    transferred after 15 Jul 2026), decode a real token (see docs) and paste the exact
    prefix here, e.g. repo:<owner>@<owner_id>/<repo>@<repo_id>
  EOT
}

locals {
  prefix = var.subject_prefix != "" ? var.subject_prefix : "repo:${var.github_owner}/${var.github_repo}"
}

# If the account already has the GitHub provider, import it instead of creating:
#   terraform import aws_iam_openid_connect_provider.github arn:aws:iam::<acct>:oidc-provider/token.actions.githubusercontent.com
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS validates GitHub's certificate chain itself; the thumbprint is not used for this provider.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# ---- trust-policy factory --------------------------------------------------
# Each role trusts ONLY the subjects listed for it. Tight 'sub' = tight blast radius.
data "aws_iam_policy_document" "trust" {
  for_each = {
    plan         = ["${local.prefix}:pull_request"]
    apply_dev    = ["${local.prefix}:environment:dev"]
    apply_stage  = ["${local.prefix}:environment:staging"]
    apply_prod   = ["${local.prefix}:environment:production"]
    ecr_push     = ["${local.prefix}:ref:refs/heads/main"]
    nightly_read = ["${local.prefix}:ref:refs/heads/main"]
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

resource "aws_iam_role" "gha" {
  for_each           = data.aws_iam_policy_document.trust
  name               = "gha-${replace(each.key, "_", "-")}"
  assume_role_policy = each.value.json
}

# ---- permissions -------------------------------------------------------------
# plan + nightly drift: read-only on AWS, read state, and write ONLY the lock file.
resource "aws_iam_role_policy_attachment" "readonly" {
  for_each   = toset(["plan", "nightly_read"])
  role       = aws_iam_role.gha[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "state_readlock" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/student-portal/*"]
  }
  statement {
    # use_lockfile writes <key>.tflock; a plan role needs this and nothing more.
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/student-portal/*.tflock"]
  }
}

resource "aws_iam_role_policy" "state_readlock" {
  for_each = toset(["plan", "nightly_read"])
  role     = aws_iam_role.gha[each.key].id
  policy   = data.aws_iam_policy_document.state_readlock.json
}

# apply roles: state read/write for their own env + the few services this lab touches.
# Lab-grade (service-wide wildcards). Tightening these to resource ARNs is a good exercise.
data "aws_iam_policy_document" "apply" {
  for_each = {
    apply_dev   = "dev"
    apply_stage = "staging"
    apply_prod  = "prod"
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/student-portal/${each.value}/*"]
  }
  statement {
    actions   = ["s3:*", "ssm:*", "ecr:*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "apply" {
  for_each = data.aws_iam_policy_document.apply
  role     = aws_iam_role.gha[each.key].id
  policy   = each.value.json
}

# ecr_push: push images only.
data "aws_iam_policy_document" "ecr_push" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages", "ecr:DescribeRepositories"
    ]
    resources = ["arn:aws:ecr:${var.region}:*:repository/student-portal"]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  role   = aws_iam_role.gha["ecr_push"].id
  policy = data.aws_iam_policy_document.ecr_push.json
}

output "role_arns" {
  value = { for k, r in aws_iam_role.gha : k => r.arn }
}
