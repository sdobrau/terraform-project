variable "aws_source_account_id" {
  description = "AWS Source account ID"
  type        = string
}

variable "web_server_asg_role" {
  description = "Role used by ASG for KMS encryption"
  type        = string
}

variable "domain_name" {
  description = "Domain name used for the ALB"
  type        = string
}

variable "cloudwatch_route53_log_group_name" {
  description = "Log group name for Route 53 traffic"
  type        = string
}
