# PLANTED ISSUES for the IaC scanners. Copy into infra/ on a feature branch to test the PR checks.
# Never merge this. Expected: checkov fails; terraform fmt/validate still pass (valid HCL).
resource "aws_security_group" "open_ssh" {
  name        = "planted-open-ssh"
  description = "planted"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # world-open SSH
  }
}

resource "aws_s3_bucket" "planted_public" {
  bucket = "planted-public-bucket-do-not-create"
}

resource "aws_s3_bucket_acl" "planted_public" {
  bucket = aws_s3_bucket.planted_public.id
  acl    = "public-read"
}
