variable "aws_source_account_id" {
  description = "ID of source account"
  type        = string
}

variable "aws_playing_cloud_xyz_certificate_arn" {
  description = "ARN of the playing-cloud.xyz certificate"
  type        = string
}

variable "adminaccount_web_key_arn" {
  description = "ARN of adminaccount_web key"
  type        = string
}

variable "adminaccount_web_key_id" {
  description = "ID of adminaccount_web key"
  type        = string
}

variable "log_bucket_arn" {
  description = "ARN of log bucket"
  type        = string
}

variable "log_bucket_bucket" {
  description = "Bucket of log bucket"
  type        = string
}

variable "log_bucket_domain_name" {
  description = "Domain name of log bucket"
  type        = string
}

variable "web_server_alb_arn" {
  description = "The ARN of the ALB"
  type        = string
}

variable "web_server_alb_dns_name" {
  description = "The DNS Name of the ALB"
  type        = string
}

variable "web_server_cloudfront_secret_value" {
  description = "X-Custom-Secret header to pass to ALB for it to work"
  type        = string
  sensitive   = true
}
