variable "my_ips" {
  description = "My IPs to use in the VPC"
  type        = list(any)
  default     = ["86.14.10.231/32"]
}

variable "aws_source_account_id" {
  description = "AWS Source Account"
  type        = string
}

variable "web_server_vpc_id" {
  description = "ID of the web server VPC"
  type        = string
}

variable "web_server_instances_private_subnet_id" {
  description = "ID of the private subnet for the web server ASG"
  type        = string
}

variable "web_server_alb_public_subnet_1_id" {
  description = "ID of the subnet that is public facing, where the ALB is placed"
  type        = string
}


variable "web_server_alb_public_subnet_2_id" {
  description = "ID of the subnet that is public facing, where the ALB is placed"
  type        = string
}


variable "ami_id" {
  description = "AMI to use for the ASG"
  type        = string
}

variable "log_bucket_arn" {
  description = "Bucket to use for logging ARN"
  type        = string
}

variable "log_bucket_id" {
  description = "Bucket to use for logging ID"
  type        = string
}

# variable "kinesis_firehose_enc_key_arn" {
#   description = "CMK Key ARN to encrypt kinesis firehose"
#   type        = string
# }

variable "adminaccount_web_key_id" {
  description = "Web key ID of the adminaccount key"
  type        = string
}

variable "adminaccount_web_key_arn" {
  description = "Web key ARN of the adminaccount key"
  type        = string
}

# variable "web_cloudwatch_us_east_key_arn" {
#   description = "Key ARN of us-east-1 key for CloudWatch log group"
#   type        = string
# }

variable "secret_header_value" {
  description = "Secret value to expect from CloudFront"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Domain name for the ALB"
  type        = string
}

variable "aws_playing_cloud_xyz_certificate_arn" {
  description = "ARN of the playing-cloud.xyz certificate"
  type        = string
}
