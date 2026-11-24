variable "region" {
  type        = string
  description = "AWS region."
  default     = "ap-south-1"
}

variable "environment" {
  type        = string
  description = "dev | staging | prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "app_name" {
  type    = string
  default = "student-portal"
}

variable "create_ecr" {
  type        = bool
  description = "Control variable (same idea as enable_argocd in class): only dev owns the ECR repo, because images are built once and promoted."
  default     = false
}

variable "log_retention_days" {
  type    = number
  default = 30
}
