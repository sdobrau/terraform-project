# * the log bucket for the elb and servers, source and destination

# ** the sns topics with encryption for both buckets
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
    # when replication done ? TODO
    filter_prefix = "main_logs/"
  }
}

# ** the versioning for both buckets (necessary)
resource "aws_s3_bucket_versioning" "web_server_logs_source" { # OK
  bucket = aws_s3_bucket.web_server_logs_source.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "web_server_logs_destination" { # OK
  bucket = aws_s3_bucket.web_server_logs_destination.id
  versioning_configuration {
    status = "Enabled"
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

# TODO: bucket logging for both bucket and state buckets to logging bucket
resource "aws_s3_bucket_policy" "web_server_logs_destination" { # OK
  bucket = aws_s3_bucket.web_server_logs_destination.bucket
  policy = data.aws_iam_policy_document.web_server_logs_destination_logging.json
}

# *** the bucket logging (server access logging) settings themselves
resource "aws_s3_bucket_logging" "web_server_logs_source" { # OK
  bucket = aws_s3_bucket.web_server_logs_source.bucket

  target_bucket = aws_s3_bucket.web_server_logs_source.bucket
  target_prefix = "bucket-logging-log/"
  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

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

# ** the encryption configuration for source and destination
resource "aws_s3_bucket_server_side_encryption_configuration" "web_server_logs_source" { # OK
  bucket = aws_s3_bucket.web_server_logs_source.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.adminaccount_web_key_id
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "web_server_logs_destination" { # OK
  bucket = aws_s3_bucket.web_server_logs_destination.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.adminaccount_web_key_id
      sse_algorithm     = "aws:kms"
    }
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
  bucket = "web-server-logs-source"

  tags = {
    component = "web"
  }
}

# TODO: log groups? for s3 logging, elb, state, application logs

resource "aws_s3_bucket" "web_server_logs_destination" { # OK
  bucket = "web-server-logs-destination"

  tags = {
    component = "web"
  }
}

# ** the bucket policy: allow put object from the web_server instance role and
#  elb, and also bucket logging

# TODO: debug module.bucket-log.aws_s3_bucket_policy.web_server_logs_source_elb_ec2_and_bucket_logging: Still creating... [01m10s elapsed]

data "aws_iam_policy_document" "web_server_alb_access_logs_and_ec2_instances" { # OK
  # using arn because arn is - not _
  statement {
    principals {
      identifiers = ["logging.s3.amazonaws.com"] # allow s3
      type        = "Service"
    }
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${aws_s3_bucket.web_server_logs_source.id}/bucket-logging-log/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }
  }
  statement {
    effect = "Allow" # allow ELB
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.web_server_logs_source.id}/access_logs/*",
      "arn:aws:s3:::${aws_s3_bucket.web_server_logs_source.id}/alb_connection_logs/*",
      "arn:aws:s3:::${aws_s3_bucket.web_server_logs_source.id}/alb_health_check_logs/*"
    ]
    actions = ["s3:PutObject"]

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    effect    = "Allow" # allow main logs
    resources = ["arn:aws:s3:::${aws_s3_bucket.web_server_logs_source.id}/main_logs/*"]

    actions = ["s3:PutObject"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_source_account_id}:role/web_server"]
    }
  }
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
  region = "eu-north-1"

  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.web_server_logs_source]

  role   = aws_iam_role.web_server_logs_replication.arn
  bucket = aws_s3_bucket.web_server_logs_source.id

  rule {
    id = "all"

    # replicate everything
    # filter {
    #   prefix = "example"
    # }

    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.web_server_logs_destination.arn
      storage_class = "STANDARD_IA"

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
