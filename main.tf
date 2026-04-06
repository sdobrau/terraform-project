# main ec2 instance

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
  #   assume_role = {
  #     role_arn = "arn:aws:iam::276719381645:role/web_server_terraform"
  #   }
  # }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "eu-north-1"
  # use an AdministratorAccess role for terraform
  # assume_role {
  #   # TODO: maybe different naming see bucket-state
  #   role_arn = "arn:aws:iam::276719381645:role/terraform"
  # }
}

data "aws_caller_identity" "source" {
  provider = aws
}

output "aws_source_account" {
  value = data.aws_caller_identity.source
}

####

module "iam-policies" { # OK
  source                = "./modules/iam-policies"
  aws_source_account_id = data.aws_caller_identity.source.account_id
}

module "kms-key" { # OK
  source                            = "./modules/kms-key"
  aws_source_account_id             = data.aws_caller_identity.source.account_id
  cloudwatch_route53_log_group_name = "bleh"
  web_server_asg_role               = "AWSServiceRoleForAutoScaling"
  domain_name                       = "playing-cloud.xyz"
}

module "vpc" {
  source              = "./modules/vpc"
  flow_log_bucket_arn = module.bucket-log.log_bucket.arn
}

module "load-balancer" {
  source      = "./modules/load-balancer"
  ami_id      = "ami-0bfa6d0ea0fe2c5a1"
  domain_name = "playing-cloud.xyz"
  # TODO: make sure consistent
  aws_source_account_id                  = data.aws_caller_identity.source.account_id
  web_server_vpc_id                      = module.vpc.web_server_vpc_id
  web_server_instances_private_subnet_id = module.vpc.web_server_instances_private_subnet.id
  web_server_alb_public_subnet_1_id      = module.vpc.web_server_alb_public_subnet_1.id
  web_server_alb_public_subnet_2_id      = module.vpc.web_server_alb_public_subnet_2.id

  adminaccount_web_key_id  = module.kms-key.adminaccount_web_key.id
  adminaccount_web_key_arn = module.kms-key.adminaccount_web_key.arn
  # web_cloudwatch_us_east_key_arn         = module.kms-key.web_cloudwatch_us_east_key.arn

  log_bucket_arn = module.bucket-log.log_bucket.arn
  log_bucket_id  = module.bucket-log.log_bucket.id
  #kinesis_firehose_enc_key_arn           = module.kms-key.adminaccount_web_key.arn
  secret_header_value                   = "TestingValue"
  aws_playing_cloud_xyz_certificate_arn = "arn:aws:acm:eu-north-1:276719381645:certificate/b0cc6b21-fca4-4be1-84b5-63adaea27547"
}

# module "cloudfront" {
#   source                                = "./modules/cloudfront"
#   web_server_alb_dns_name               = module.load-balancer.web_server_alb.dns_name
#   adminaccount_web_key_id               = module.kms-key.adminaccount_web_key.id
#   log_bucket_bucket                     = module.bucket-log.log_bucket.bucket
#   log_bucket_arn                        = module.bucket-log.log_bucket.arn
#   log_bucket_domain_name                = module.bucket-log.log_bucket.bucket_domain_name
#   aws_source_account_id                 = data.aws_caller_identity.source.account_id
#   web_server_cloudfront_secret_value    = "TestingValue"
#   aws_playing_cloud_xyz_certificate_arn = "arn:aws:acm:eu-north-1:276719381645:certificate/b0cc6b21-fca4-4be1-84b5-63adaea27547"
#
# }

module "bucket-log" {
  source                   = "./modules/bucket-log"
  aws_source_account_id    = data.aws_caller_identity.source.account_id
  adminaccount_web_key_id  = module.kms-key.adminaccount_web_key.id
  adminaccount_web_key_arn = module.kms-key.adminaccount_web_key.arn
}

# module "bucket-state" {
#   source                   = "./modules/bucket-state"
#   aws_source_account_id    = data.aws_caller_identity.source.account_id
#   adminaccount_web_key_id  = module.kms-key.adminaccount_web_key.id
#   adminaccount_web_key_arn = module.kms-key.adminaccount_web_key.arn
#   log_bucket_arn           = module.bucket-log.log_bucket.arn
#   log_bucket_id            = module.bucket-log.log_bucket.id
#   log_bucket_bucket        = module.bucket-log.log_bucket.bucket
# }
