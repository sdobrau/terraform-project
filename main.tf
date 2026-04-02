# main ec2 instance

# first define the aws resource provider

data "aws_caller_identity" "source" {
  provider = aws.source
}

terraform {
  # store the state file with locking inside a public s3 instance
  #
  # we will need to assume a role with:
  # s3:ListBucket on arn:aws:s3:::mybucket.
  # s3:GetObject on arn:aws:s3:::mybucket/path/to/my/key
  # s3:PutObject on arn:aws:s3:::mybucket/path/to/my/key
  # account will be able to assume the role
  backend "s3" {
    bucket = "web_server_state"
    key = "terraform_state_file"
    region = "us-east-1"
    use_lockfile = true
    assume_role = {
      role_arn = "arn:aws:iam::${data.aws_caller_identity.source.account_id}:role/web_server_terraform"
    }
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  required_version = "~> 6.0"
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

module "iam-policies" {
  source = "./modules/iam-policies"
}

module "kms-key" {
  source = "./modules/kms-key"
}

module "load-balancer" {
  source = "./modules/load-balancer"
}

module "log-bucket" {
  source = "./modules/log-bucket"
}

module "vpc" {
  source = "./modules/vpc"
}
