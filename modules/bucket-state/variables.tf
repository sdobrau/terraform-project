variable "adminaccount_web_key_id" {
  description = "Web key ID of the adminaccount key"
  type        = string
}

variable "adminaccount_web_key_arn" {
  description = "Web key ARN of the adminaccount key"
  type        = string
}

variable "aws_source_account_id" {
  description = "Source account ID"
  type        = string
}

variable "log_bucket_arn" {
  description = "The logging bucket ARN"
}

variable "log_bucket_id" {
  description = "The logging bucket ID"
}

variable "log_bucket_bucket" {
  description = "The logging bucket name"
}
