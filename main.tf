# * the main outside view

# cloudfront: d2i2uinmeijqvf.cloudfront.net
# elb: web-server-2068915431.us-east-1.elb.amazonaws.com

# first define the aws resource provider

terraform {
  # store the state file with locking inside a public s3 instance
  #
  # we will need to assume a role with:
  # s3:ListBucket on arn:aws:s3:::mybucket.
  # s3:GetObject on arn:aws:s3:::mybucket/path/to/my/key
  # s3:PutObject on arn:aws:s3:::mybucket/path/to/my/key
  # account will be able to assume the role
  # backend "s3" {
  #   bucket = "web_server_state"
  #   key = "terraform_state_file"
  #   region = "us-east-1"
  #   use_lockfile = true
  # }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  required_version = "~> 1.14"
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
  # assume_role {
  #   role_arn = "arn:aws:iam::276719381645:role/terraform"
  # }
}

data "aws_caller_identity" "source" {
  provider = aws
}

output "aws_source_account" {
  value = data.aws_caller_identity.source
}

# * the modules

module "iam-policies" { # OK
  source = "./modules/iam-policies"
}

module "db" {
  source                   = "./modules/db"
  adminaccount_web_key_arn = module.kms-key.adminaccount_web_key.arn
}

module "kms-key" { # OK
  source                            = "./modules/kms-key"
  aws_source_account_id             = data.aws_caller_identity.source.account_id
  cloudwatch_route53_log_group_name = module.load-balancer.cloudwatch_route53_log_group_name
}

module "vpc" {
  source = "./modules/vpc"

  adminaccount_web_key_arn = module.kms-key.adminaccount_web_key.arn
}

module "load-balancer" {
  source = "./modules/load-balancer"

  aws_source_account_id = data.aws_caller_identity.source.account_id

  adminaccount_web_key_arn = module.kms-key.adminaccount_web_key.arn
  adminaccount_web_key_id  = module.kms-key.adminaccount_web_key.id

  ami_id = "ami-01b14b7ad41e17ba4"

  domain_name = "playing-cloud.xyz"

  log_bucket_bucket = module.bucket-log.log_bucket.bucket
  log_bucket_id     = module.bucket-log.log_bucket.id

  web_server_vpc_id                      = module.vpc.web_server_vpc_id
  web_server_instances_private_subnet_id = module.vpc.web_server_instances_private_subnet.id
  web_server_alb_private_subnet_1_id     = module.vpc.web_server_alb_private_subnet_1.id
  web_server_alb_private_subnet_2_id     = module.vpc.web_server_alb_private_subnet_2.id

  secret_header_value = "TestingValue"
}

module "cloudtrail" {
  source = "./modules/cloudtrail"

  aws_source_account_id = data.aws_caller_identity.source.account_id

  adminaccount_web_key_arn = module.kms-key.adminaccount_web_key.arn
  adminaccount_web_key_id  = module.kms-key.adminaccount_web_key.id

  log_bucket_id = module.bucket-log.log_bucket.id
}

module "cloudfront" {
  source = "./modules/cloudfront"

  aws_source_account_id = data.aws_caller_identity.source.account_id

  aws_playing_cloud_xyz_certificate_arn = "arn:aws:acm:us-east-1:276719381645:certificate/92c85a20-ebe7-454e-9eb5-28484cd7e16f"

  adminaccount_web_key_arn = module.kms-key.adminaccount_web_key.arn
  adminaccount_web_key_id  = module.kms-key.adminaccount_web_key.id

  log_bucket_arn    = module.bucket-log.log_bucket.arn
  log_bucket_bucket = module.bucket-log.log_bucket.bucket
  # TODO:
  log_domain_name_domain_name = module.bucket-log.log_bucket.bucket_domain_name

  web_server_alb_arn                 = module.load-balancer.web_server_alb_arn
  web_server_alb_dns_name            = module.load-balancer.web_server_alb_dns_name
  web_server_cloudfront_secret_value = "TestingValue"
}

module "bucket-log" {
  source = "./modules/bucket-log"

  aws_source_account_id = data.aws_caller_identity.source.account_id

  adminaccount_web_key_arn = module.kms-key.adminaccount_web_key.arn
  adminaccount_web_key_id  = module.kms-key.adminaccount_web_key.id

}

module "bucket-state" {
  source = "./modules/bucket-state"

  aws_source_account_id    = data.aws_caller_identity.source.account_id
  adminaccount_web_key_arn = module.kms-key.adminaccount_web_key.arn
  adminaccount_web_key_id  = module.kms-key.adminaccount_web_key.id
  log_bucket_bucket        = module.bucket-log.log_bucket.bucket
}
