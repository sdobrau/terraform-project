# * sns topic for cloudtrail

data "aws_region" "current" {}

# depends on log bucket policy to be properly configured

# resource "aws_sns_topic" "cloudtrail" { # OK
#   name              = "cloudtrail"
#   kms_master_key_id = var.adminaccount_web_key_id # encryption
# }

# # taken from the default permissions from a newly created trail
# data "aws_iam_policy_document" "cloudtrail_sns" {
#   # this part specifically
#   statement {
#     sid       = "__default_statement_ID"
#     effect    = "Allow"
#     resources = ["${aws_sns_topic.cloudtrail.arn}"]

#     actions = [
#       "SNS:GetTopicAttributes",
#       "SNS:SetTopicAttributes",
#       "SNS:AddPermission",
#       "SNS:RemovePermission",
#       "SNS:DeleteTopic",
#       "SNS:Subscribe",
#       "SNS:ListSubscriptionsByTopic",
#       "SNS:Publish",
#     ]

#     condition {
#       test     = "StringEquals"
#       variable = "AWS:SourceOwner"
#       values   = [var.aws_source_account_id]
#     }

#     principals {
#       type        = "AWS"
#       identifiers = ["*"]
#     }
#   }

#   statement {
#     sid       = "Example SNS topic policy"
#     effect    = "Allow"
#     resources = ["${aws_sns_topic.cloudtrail.arn}"]
#     actions   = ["SNS:Publish"]

#     condition {
#       test     = "ArnLike"
#       variable = "aws:SourceArn"
#       values   = ["${aws_cloudtrail.cloudtrail.arn}"]
#     }

#     condition {
#       test     = "StringEquals"
#       variable = "aws:SourceAccount"
#       values   = ["${var.aws_source_account_id}"]
#     }

#     principals {
#       type        = "Service"
#       identifiers = ["cloudtrail.amazonaws.com"]
#     }
#   }
# }

# resource "aws_sns_topic_policy" "cloudtrail" {
#   arn    = aws_sns_topic.cloudtrail.arn
#   policy = data.aws_iam_policy_document.cloudtrail_sns.json
# }

# * log group

resource "aws_cloudwatch_log_group" "cloudtrail" { # OK
  name              = "cloudtrail"
  retention_in_days = 365
  kms_key_id        = var.adminaccount_web_key_arn
}

# a policy and role that allows cloudwatch to write to a log group

data "aws_iam_policy_document" "cloudtrail_assume_role" { # OK
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${data.aws_region.current.name}:${var.aws_source_account_id}:trail/cloudtrail"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "cloudtrail" { # OK
  statement {
    sid       = "AWSCloudTrailCreateLogStream2014110"
    effect    = "Allow"
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${var.aws_source_account_id}:log-group:cloudtrail:log-stream:${var.aws_source_account_id}_CloudTrail_${data.aws_region.current.name}*"]
    actions   = ["logs:CreateLogStream"]
  }

  statement {
    sid       = "AWSCloudTrailPutLogEvents20141101"
    effect    = "Allow"
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${var.aws_source_account_id}:log-group:cloudtrail:log-stream:${var.aws_source_account_id}_CloudTrail_${data.aws_region.current.name}*"]
    actions   = ["logs:PutLogEvents"]
  }
}

resource "aws_iam_role" "cloudtrail" { # OK
  name               = "cloudtrail"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume_role.json
}

resource "aws_iam_role_policy" "cloudtrail" { # OK
  name   = "cloudtrail"
  role   = aws_iam_role.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail.json
}

# * cloudtrail

resource "aws_cloudtrail" "cloudtrail" { # OK
  name                          = "cloudtrail"
  s3_bucket_name                = var.log_bucket_id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true # capture from iam too
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  enable_logging                = true
  insight_selector {
    insight_type = "ApiErrorRateInsight" # OK
  }

  # CloudTrail requires the Log Stream wildcard
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail.arn
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"

  # MISSING: sns topic for cloudtrail
  # SNS Topic does not exist or the topic policy is incorrect!
  # although properly configured
  # sns_topic_name = aws_sns_topic.cloudtrail.arn
  kms_key_id = var.adminaccount_web_key_arn
  # record all s3 data events
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3"]
    }
  }
}
