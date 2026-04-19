# * the log bucket for the elb and servers, source and destination

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
data "aws_partition" "current" {}

# ** the sns topics with encryption for both buckets
# TOIMPLEMENT: event notifications to sns topics.
# at the moment "unable to validate destination configuration"
resource "aws_sns_topic" "web_server_logs_source_bucket_notification" { # OK
  name              = "web_server_logs_source_bucket_notification"
  kms_master_key_id = var.adminaccount_web_key_id # encryption
  policy            = data.aws_iam_policy_document.web_server_logs_allow_source_bucket_to_publish.json
}

resource "aws_sns_topic" "web_server_logs_destination_bucket_notification" { # OK
  name              = "web_server_logs_destination_bucket_notification"
  kms_master_key_id = var.adminaccount_web_key_id # encryption
  policy            = data.aws_iam_policy_document.web_server_logs_allow_destination_bucket_to_publish.json
}

# ** the sns topic destination policies for s3
data "aws_iam_policy_document" "web_server_logs_allow_source_bucket_to_publish" { # OK
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = ["arn:aws:sns:*:*:web_server_logs_source_bucket_notification"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.web_server_logs_source.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }
  }
}

data "aws_iam_policy_document" "web_server_logs_allow_destination_bucket_to_publish" { # OK
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = ["arn:aws:sns:*:*:web_server_logs_destination_bucket_notification"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.web_server_logs_destination.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }
  }
}

# ** the bucket notification (access logging) settings: send to sns topics
resource "aws_s3_bucket_notification" "web_server_logs_source_bucket_notification" { # OK
  bucket = aws_s3_bucket.web_server_logs_source.id

  topic {
    topic_arn = aws_sns_topic.web_server_logs_source_bucket_notification.arn
    events    = ["s3:ObjectCreated:*"]
    # log sent by instance
    filter_prefix = "main_logs/"
  }
}

resource "aws_s3_bucket_notification" "web_server_logs_destination_bucket_notification" { # OK
  bucket = aws_s3_bucket.web_server_logs_destination.id

  topic {
    topic_arn = aws_sns_topic.web_server_logs_destination_bucket_notification.arn
    events    = ["s3:ObjectCreated:*"]
    # log sent by instance
    filter_prefix = "main_logs/"
  }
}

# ** the versioning for both buckets (necessary)
resource "aws_s3_bucket_versioning" "web_server_logs_source" { # OK
  bucket = aws_s3_bucket.web_server_logs_source.id
  # mfa    = "serialnumber authvalue"
  versioning_configuration {
    status = "Enabled"
    # mfa_delete = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "web_server_logs_destination" { # OK
  bucket = aws_s3_bucket.web_server_logs_destination.id
  # mfa    = "serialnumber authvalue"
  versioning_configuration {
    status = "Enabled"
    # mfa_delete = "Enabled"
  }
}

# ** the bucket logging configuration, place bucket logs in same bucket in log/*
# *** the permissions for bucket logging to work

data "aws_iam_policy_document" "web_server_logs_destination_logging" { # OK
  statement {
    principals {
      identifiers = ["logging.s3.amazonaws.com"]
      type        = "Service"
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.web_server_logs_destination.arn}/bucket-logging-log/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "web_server_logs_destination" { # OK
  bucket = aws_s3_bucket.web_server_logs_destination.bucket
  policy = data.aws_iam_policy_document.web_server_logs_destination_logging.json
}

# *** the bucket logging (server access logging) settings themselves
# resource "aws_s3_bucket_logging" "web_server_logs_source" { # OK
#   bucket = aws_s3_bucket.web_server_logs_source.bucket

#   target_bucket = aws_s3_bucket.web_server_logs_source.bucket
#   target_prefix = "bucket-logging-log/"
#   target_object_key_format {
#     partitioned_prefix {
#       partition_date_source = "EventTime"
#     }
#   }
# }

resource "aws_s3_bucket_logging" "web_server_logs_destination" { # OK
  bucket = aws_s3_bucket.web_server_logs_destination.bucket

  target_bucket = aws_s3_bucket.web_server_logs_destination.bucket
  target_prefix = "bucket-logging-log/"
  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

# ** the life cycle configuration for the bucket source and destination
resource "aws_s3_bucket_lifecycle_configuration" "web_server_logs_source" { # OK
  bucket = aws_s3_bucket.web_server_logs_source.bucket

  rule {
    id = "rule-1"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      newer_noncurrent_versions = 2
      noncurrent_days           = 7
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA" # by default
    }

    transition {
      days          = 60 # after 30 days use glacier
      storage_class = "GLACIER"
      # ... other transition/expiration actions ...
    }
    transition {
      days          = 150 # after 30 days use glacier
      storage_class = "DEEP_ARCHIVE"
      # ... other transition/expiration actions ...
    }
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "web_server_logs_destination" { # OK
  bucket = aws_s3_bucket.web_server_logs_destination.bucket

  rule {
    id = "rule-1"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      newer_noncurrent_versions = 2
      noncurrent_days           = 7
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA" # by default
    }

    transition {
      days          = 60 # after 30 days use glacier
      storage_class = "GLACIER"
      # ... other transition/expiration actions ...
    }
    transition {
      days          = 150 # after 30 days use glacier
      storage_class = "DEEP_ARCHIVE"
      # ... other transition/expiration actions ...
    }
    status = "Enabled"
  }
}


# ** the public access blocking configuration for source and destination

resource "aws_s3_bucket_public_access_block" "web_server_logs_source" { # OK
  bucket = aws_s3_bucket.web_server_logs_source.id

  block_public_acls       = true # block any acls that would make it public
  block_public_policy     = true # block any policies that would make it public
  ignore_public_acls      = true # ignore current public policies
  restrict_public_buckets = true # only aws services and owner can access if pub
}

resource "aws_s3_bucket_public_access_block" "web_server_logs_destination" { # OK
  bucket = aws_s3_bucket.web_server_logs_destination.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ** the buckets themselves

resource "aws_s3_bucket" "web_server_logs_source" { # OK
  bucket        = "web-server-logs-source-1"
  force_destroy = true
  tags = {
    component = "web"
  }
}

resource "aws_s3_bucket" "web_server_logs_destination" { # OK
  bucket        = "web-server-logs-destination-1"
  force_destroy = true
  tags = {
    component = "web"
  }
}
# ** the encryption configuration for logs source and destination
# TOFIX: disabling this to see if access_logs etc in alb work
# resource "aws_s3_bucket_server_side_encryption_configuration" "web_server_logs_source" {
#   bucket = aws_s3_bucket.web_server_logs_source.id

#   rule {
#     apply_server_side_encryption_by_default {
#       kms_master_key_id = var.adminaccount_web_key_arn
#       sse_algorithm     = "aws:kms"
#     }
#   }
# }

# resource "aws_s3_bucket_server_side_encryption_configuration" "web_server_logs_destination" {
#   bucket = aws_s3_bucket.web_server_logs_destination.id
#   rule {
#     apply_server_side_encryption_by_default {
#       kms_master_key_id = var.adminaccount_web_key_arn
#       sse_algorithm     = "aws:kms"
#     }
#   }
# }

# ** the bucket policy: allow put object from the web_server instance role and
#  elb, and also bucket logging

data "aws_iam_policy_document" "web_server_alb_access_logs_and_ec2_instances" { # OK

  # allow bucket logging
  statement {
    principals {
      identifiers = ["logging.s3.amazonaws.com"] # allow s3
      type        = "Service"
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.web_server_logs_source.arn}/bucket-logging-log/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }
  }

  # allow ELB
  # statement {
  #   effect = "Allow"
  #   resources = [
  #     "${aws_s3_bucket.web_server_logs_source.arn}/alb_access_logs/*",
  #     "${aws_s3_bucket.web_server_logs_source.arn}/alb_connection_logs/*",
  #     "${aws_s3_bucket.web_server_logs_source.arn}/alb_health_check_logs/*"
  #   ]
  #   actions = ["s3:PutObject"]

  #   principals {
  #     type        = "Service"
  #     identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
  #   }
  # }

  # testing
  statement {
    effect    = "Allow"
    resources = ["${aws_s3_bucket.web_server_logs_source.arn}/*"]
    actions   = ["s3:PutObject"]

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }

  # suggested by amazon's AI
  statement {
    effect    = "Allow"
    resources = [aws_s3_bucket.web_server_logs_source.arn]
    actions   = ["s3:ListBucket"]

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }

  # allow main logs
  statement {
    effect    = "Allow"
    resources = ["arn:aws:s3:::${aws_s3_bucket.web_server_logs_source.id}/main_logs/*"]

    actions = ["s3:PutObject"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_source_account_id}:role/web_server"]
    }
  }

  # allow cloudtrail
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.web_server_logs_source.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.region}:${var.aws_source_account_id}:trail/cloudtrail"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.web_server_logs_source.arn}/cloudtrail/AWSLogs/${var.aws_source_account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.region}:${var.aws_source_account_id}:trail/cloudtrail"]
    }
  }
  # for cloudfront logging

}

resource "aws_s3_bucket_policy" "web_server_logs_source_elb_ec2_and_bucket_logging" { # OK
  bucket = aws_s3_bucket.web_server_logs_source.bucket
  policy = data.aws_iam_policy_document.web_server_alb_access_logs_and_ec2_instances.json
}

# ** the logs bucket replication configuration
# *** the permissions required for replication
data "aws_iam_policy_document" "web_server_logs_replication_assume_role" { # OK
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "web_server_logs_replication" { # OK
  name               = "web_server_logs_replication"
  assume_role_policy = data.aws_iam_policy_document.web_server_logs_replication_assume_role.json
}

data "aws_iam_policy_document" "web_server_logs_replication_listing" { # OK
  statement {
    effect = "Allow"

    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]

    resources = [aws_s3_bucket.web_server_logs_source.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]

    resources = ["${aws_s3_bucket.web_server_logs_source.arn}/*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]

    resources = ["${aws_s3_bucket.web_server_logs_destination.arn}/*"]
  }
}

resource "aws_iam_policy" "web_server_logs_replication" { # OK
  name   = "web_server_logs_replication"
  policy = data.aws_iam_policy_document.web_server_logs_replication_listing.json
}

resource "aws_iam_role_policy_attachment" "web_server_logs_replication" { # OK
  role       = aws_iam_role.web_server_logs_replication.name
  policy_arn = aws_iam_policy.web_server_logs_replication.arn
}

# *** the actual bucket replication configuration (uni-directional)

resource "aws_s3_bucket_replication_configuration" "web_server_logs_replication" { # OK

  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.web_server_logs_source]

  role   = aws_iam_role.web_server_logs_replication.arn
  bucket = aws_s3_bucket.web_server_logs_source.id

  rule {
    id = "all"
    # Replication configuration XML V2 includes the Filter element for rules.
    # replicate everything
    # If you specify a rule with an empty filter tag your rule will apply to all
    # objects in your bucket
    delete_marker_replication {
      status = "Enabled"
    }
    filter {
      prefix = "" # all?
    }
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.web_server_logs_destination.arn
      storage_class = "STANDARD_IA"
      # enable RTC
      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }
      # for rtc
      metrics {
        event_threshold {
          minutes = 15
        }
        status = "Enabled"
      }
      encryption_configuration {
        replica_kms_key_id = var.adminaccount_web_key_arn
      }
    }
    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }
}
