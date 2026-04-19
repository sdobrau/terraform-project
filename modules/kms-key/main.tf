# * the kms key and key policy to encrypt the ebs storage and others

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  required_version = "~> 1.14"
}

data "aws_region" "current" {}

resource "aws_kms_key" "adminaccount_web" { # OK
  description             = "My KMS key"
  enable_key_rotation     = true
  deletion_window_in_days = 20
}

resource "aws_kms_alias" "adminaccount_web" { # OK
  name          = "alias/adminaccount_web"
  target_key_id = aws_kms_key.adminaccount_web.key_id
}

# ** the required role setup for asg and kms

# according to
# https://docs.aws.amazon.com/autoscaling/ec2/userguide/key-policy-requirements-EBS-encryption.html

data "aws_iam_policy_document" "web_server_asg" { # OK
  statement {
    sid    = "Allow me (adminaccount) and terraform to manage the key"
    effect = "Allow"
    #checkov:skip=CKV_AWS_109:Principles are admins
    resources = ["*"]
    actions = [
      "kms:CreateKey",
      "kms:ReplicateKey",
      "kms:Create*",
      "kms:Describe*",
      "kms:RotateKeyOnDemand", # added by me
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      # for associating with log group
      # see https://github.com/hashicorp/terraform-provider-aws/issues/8042
      "kms:AssociateKmsKey",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion"
    ]
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${var.aws_source_account_id}:user/adminaccount",
      "arn:aws:iam::${var.aws_source_account_id}:role/terraform"]
    }
  }
  # allow ASG to operate with the key
  statement {
    sid       = "Allow service-linked role use of the customer managed key"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_source_account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
  }

  statement {
    sid       = "Allow attachment of persistent resources"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["kms:CreateGrant"]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_source_account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
  }

  # for "aws_cloudwatch_log_group" "web_server_alb_dns_query_logging"
  # in load-balancer/main.tf:25

  statement {
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]

    # allow only to encrypt with this key /aws/route53/playing-cloud.xyz/
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${var.aws_source_account_id}:log-group:${var.cloudwatch_route53_log_group_name}"]
    }

    principals {
      type        = "Service"
      identifiers = ["logs.us-east-1.amazonaws.com"]
    }
  }

  # for cloudtrail cloudwatch log group

  statement {
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]

    # allow only to encrypt with this key /aws/route53/playing-cloud.xyz/
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${var.aws_source_account_id}:log-group:cloudtrail"]
    }

    principals {
      type        = "Service"
      identifiers = ["logs.us-east-1.amazonaws.com"]
    }
  }

  # for vpc flow log log group
  statement {
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]

    # allow only to encrypt with this key /aws/route53/playing-cloud.xyz/
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${var.aws_source_account_id}:log-group:vpc_flow_log"]
    }

    principals {
      type        = "Service"
      identifiers = ["logs.us-east-1.amazonaws.com"]
    }
  }

  # this is so the kms key can be added to the cloudwatch r53 log group
  statement {
    sid       = "Enable IAM User Permissions"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["kms:*"]

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${var.aws_source_account_id}:root",
        "arn:aws:iam::${var.aws_source_account_id}:user/adminaccount"
      ]
    }
  }

  statement {
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]

    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
  }

  # for allowing S3 to work with encrypted topic or queue
  # https://docs.aws.amazon.com/AmazonS3/latest/userguide/grant-destinations-permissions-to-s3.html

  statement {
    sid       = "Allow S3 work with SNS"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
    ]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }

  # allow cloudtrail ...
  # as in link
  # https://docs.aws.amazon.com/awscloudtrail/latest/userguide/create-kms-key-policy-for-cloudtrail.html#create-kms-key-policy-for-cloudtrail-describe
  # allow cloudtrail to encrypt logs
  statement {
    sid       = "Allow CloudTrail to encrypt logs"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["kms:GenerateDataKey*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:us-east-1:${var.aws_source_account_id}:trail/cloudtrail"]
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${var.aws_source_account_id}:trail/*"]
    }

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid       = "Allow CloudTrail to describe key"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["kms:DescribeKey"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid       = "Allow principals in the account to decrypt log files"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:Decrypt",
      "kms:ReEncryptFrom",
    ]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [var.aws_source_account_id] # allow caller accounts to
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:loudtrail:arn" # decrypt here v
      values   = ["arn:aws:cloudtrail:*:${var.aws_source_account_id}:trail/*"]
    }

    principals {
      type        = "AWS" # allow all principals
      identifiers = ["*"]
    }
  }
  # for cloudtrail again as specified in
  # https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-permissions-for-sns-notifications.html

  statement {
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt",
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  # for dynamodb
  statement {
    sid       = "Allow access through Amazon DynamoDB for all principals in the account that are authorized to use Amazon DynamoDB"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]

    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values   = ["dynamodb.*.amazonaws.com"]
    }

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_source_account_id}:user/adminaccount"]
    }
  }

  statement {
    sid       = "Allow administrators to view the KMS key and revoke grants"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:Describe*",
      "kms:Get*",
      "kms:List*",
      "kms:RevokeGrant",
    ]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_source_account_id}:user/adminaccount"]
    }
  }

}

# the key policy for asg to encrypt data and attach persistent storage
resource "aws_kms_key_policy" "web_server_asg" { # OK
  key_id = aws_kms_key.adminaccount_web.key_id
  policy = data.aws_iam_policy_document.web_server_asg.json
}
