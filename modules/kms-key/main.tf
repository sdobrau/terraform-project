# * the kms key and key policy to encrypt the ebs storage and others

resource "aws_kms_key" "adminaccount_web" {
  description             = "An example symmetric encryption KMS key"
  enable_key_rotation     = true
  deletion_window_in_days = 20
}

# us-east-1 for cloudwatch log group encryption
resource "aws_kms_key" "web_cloudwatch_us_east" {
  description             = "An example symmetric encryption KMS key"
  enable_key_rotation     = true
  deletion_window_in_days = 20
  region                  = "us-east-1"
}

resource "aws_kms_alias" "adminaccount_web" {
  name          = "alias/adminaccount_web"
  target_key_id = aws_kms_key.adminaccount_web.key_id
}

resource "aws_kms_alias" "web_cloudwatch_us_east" {
  name          = "alias/web_cloudwatch_us_east"
  target_key_id = aws_kms_key.adminaccount_web.key_id
}

# ** the required role setup for asg and kms

# resource "aws_iam_service_linked_role" "web_server_asg" {
#   aws_service_name = "autoscaling.amazonaws.com"

# }

# TODO: key policy
# allow only root and admin account to manage it, but allow asg to operate with it
# TODO: instantiate AWSServiceRoleForAutoScaling, then add policies to it
# according to
# https://docs.aws.amazon.com/autoscaling/ec2/userguide/key-policy-requirements-EBS-encryption.html

data "aws_iam_policy_document" "web_server_asg" {
  statement {
    sid       = "Allow me (adminaccount) to manage the key"
    effect    = "Allow"
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
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion"
    ]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_source_account_id}:user/adminaccount"]
    }
  }
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
}

# data "aws_iam_policy_document" "cloudwatch_log_group_key_policy" {

#   # TODO: allow log group calls to enc/dec etc
#   # https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html

#   statement {
#     effect    = "Allow"
#     resources = ["*"]

#     actions = [
#       "kms:Encrypt",
#       "kms:Decrypt",
#       "kms:ReEncrypt*",
#       "kms:GenerateDataKey*",
#       "kms:Describe*",
#     ]

#     condition {
#       test     = "ArnEquals"
#       variable = "kms:EncryptionContext:aws:logs:arn"
#       values   = ["arn:aws:logs:us-east-1:${var.aws_source_account_id}:log-group:${var.cloudwatch_route53_log_group_name}"]
#     }

#     principals {
#       type        = "Service"
#       identifiers = ["logs.us-east-1.amazonaws.com"]
#     }
#   }
# }

# resource "aws_kms_key_policy" "web_cloudwatch_us_east" {
#   key_id = aws_kms_key.web_cloudwatch_us_east.key_id
#   policy = data.aws_iam_policy_document.cloudwatch_log_group_key_policy.json
# }

# the key policy for asg to encrypt data and attach persistent storage
resource "aws_kms_key_policy" "web_server_asg" {
  key_id = aws_kms_key.adminaccount_web.key_id
  policy = data.aws_iam_policy_document.web_server_asg.json
}
