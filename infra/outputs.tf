output "bucket_name" {
  value = module.app_bucket.bucket_name
}

output "ecr_repository_url" {
  value = one(aws_ecr_repository.app[*].repository_url)
}
