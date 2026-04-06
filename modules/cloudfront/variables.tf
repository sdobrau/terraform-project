variable "web_server_alb_dns_name" {
  description = "The DNS Name of the ALB"
  type        = string
}

variable "web_server_cloudfront_secret_value" {
  description = "X-Custom-Secret header to pass to ALB for it to work"
  type        = string
  sensitive   = true
}

variable "aws_source_account_id" {
  description = "Source account ID"
  type        = string
}

variable "adminaccount_web_key_id" {
  description = "The adminaccount key ID"
  type        = string
}

variable "log_bucket_bucket" {
  description = "The log bucket bucket"
  type        = string
}

variable "log_bucket_arn" {
  description = "The log bucket ARN"
  type        = string
}

variable "log_bucket_domain_name" {
  description = "Domain name of the log bucket"
  type        = string
}

variable "aws_playing_cloud_xyz_certificate_arn" {
  description = "ARN of the playing-cloud.xyz certificate"
  type        = string
}
