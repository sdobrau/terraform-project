variable "aws_source_account_id" {
  description = "ID of source account"
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

variable "ami_id" {
  description = "AMI to use for the ASG"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the ALB"
  type        = string
}

variable "log_bucket_bucket" {
  description = "Bucket of log bucket"
  type        = string
}

variable "log_bucket_id" {
  description = "ID of log bucket"
  type        = string
}

variable "web_server_alb_private_subnet_1_id" {
  description = "ID of the subnet that is private facing, where the ALB is placed"
  type        = string
}

variable "web_server_alb_private_subnet_2_id" {
  description = "ID of the subnet that is private facing, where the ALB is placed"
  type        = string
}

variable "web_server_alb_2_private_subnet_1_id" {
  description = "ID of the subnet that is private facing, where the ALB is placed"
  type        = string
}

variable "web_server_alb_2_private_subnet_2_id" {
  description = "ID of the subnet that is private facing, where the ALB is placed"
  type        = string
}

variable "web_server_instances_private_subnet_id" {
  description = "ID of the private subnet for the web server ASG"
  type        = string
}

variable "web_server_instances_private_subnet_2_id" {
  description = "ID of the private subnet for the 2nd web server ASG"
  type        = string
}

variable "web_server_vpc_id" {
  description = "ID of the web server VPC"
  type        = string
}

variable "secret_header_value" {
  description = "Secret value to expect from CloudFront"
  type        = string
  sensitive   = true
}
