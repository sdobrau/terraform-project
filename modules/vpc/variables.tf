variable "my_ips" {
  default = ["86.14.10.231/32"]
}

variable "flow_log_bucket_arn" {
  description = "ARN of the bucket to store VPC flow logs in"
  type = string
}
