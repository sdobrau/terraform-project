# * the state bucket and policies

# # ** the sns topics with encryption for both buckets
resource "aws_sns_topic" "web_server_state_source_bucket_notification" { # OK
  name              = "web_server_state_source_bucket_notification"
  kms_master_key_id = var.adminaccount_web_key_id
  policy            = data.aws_iam_policy_document.web_server_state_allow_source_bucket_to_publish.json
}

resource "aws_sns_topic" "web_server_state_destination_bucket_notification" { # OK
  name              = "web_server_state_destination_bucket_notification"
  kms_master_key_id = var.adminaccount_web_key_id # encryption
  policy            = data.aws_iam_policy_document.web_server_state_allow_destination_bucket_to_publish.json
}

# ** the sns topic destination policies for s3
data "aws_iam_policy_document" "web_server_state_allow_source_bucket_to_publish" { # OK
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = ["arn:aws:sns:*:*:web_server_state_source_bucket_notification"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.web_server_state_source.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }
  }
}

data "aws_iam_policy_document" "web_server_state_allow_destination_bucket_to_publish" { # OK
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = ["arn:aws:sns:*:*:web_server_state_destination_bucket_notification"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.web_server_state_destination.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }
  }
}

# ** the bucket notification settings: send to sns topics
resource "aws_s3_bucket_notification" "web_server_state_source_bucket_notification" { # OK
  bucket = aws_s3_bucket.web_server_state_source.id

  topic {
    topic_arn = aws_sns_topic.web_server_state_source_bucket_notification.arn
    events    = ["s3:ObjectCreated:*"]
    # log sent by instance
    filter_prefix = "terraform_state_file.tflock"
  }
}

resource "aws_s3_bucket_notification" "web_server_state_destination_bucket_notification" { # OK
  bucket = aws_s3_bucket.web_server_state_destination.id

  topic {
    topic_arn     = aws_sns_topic.web_server_state_destination_bucket_notification.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "terraform_state_file.tflock"
  }
}

#
# ** the bucket logging configurations for both buckets
resource "aws_s3_bucket_logging" "web_server_state_source" { # OK
  bucket = aws_s3_bucket.web_server_state_source.id

  target_bucket = var.log_bucket_bucket
  target_prefix = "bucket-logging-log/"
  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

data "aws_iam_policy_document" "web_server_state_destination_logging" { # OK
  statement {
    principals {
      identifiers = ["logging.s3.amazonaws.com"]
      type        = "Service"
    }
    actions = ["s3:PutObject"]

    resources = ["arn:aws:s3:::${aws_s3_bucket.web_server_state_destination.id}/bucket-logging-log/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "web_server_state_destination" { # OK
  bucket = aws_s3_bucket.web_server_state_destination.id
  policy = data.aws_iam_policy_document.web_server_state_destination_logging.json
}

resource "aws_s3_bucket_logging" "web_server_state_destination" { # OK
  bucket        = aws_s3_bucket.web_server_state_destination.id
  target_bucket = var.log_bucket_bucket
  target_prefix = "bucket-logging-log/"
  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

# ** the versioning for both buckets (necessary)
resource "aws_s3_bucket_versioning" "web_server_state_source" { # OK
  bucket = aws_s3_bucket.web_server_state_source.id
  # mfa    = "serialnumber authvalue"
  versioning_configuration {
    status = "Enabled"
    # mfa_delete = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "web_server_state_destination" { # OK
  bucket = aws_s3_bucket.web_server_state_destination.id
  # mfa    = "serialnumber authvalue"
  versioning_configuration {
    status = "Enabled"
    # mfa_delete = "Enabled"
  }
}

# ** the encryption configuration for state source and destination

resource "aws_s3_bucket_lifecycle_configuration" "web_server_state_source" { # OK
  bucket = aws_s3_bucket.web_server_state_source.bucket

  rule {
    id = "rule-1"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      newer_noncurrent_versions = 2 # keep 2 noncurrent versions
      noncurrent_days           = 7 # 3rd noncurrent version expire after 7days
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

resource "aws_s3_bucket_lifecycle_configuration" "web_server_state_destination" { # OK
  bucket = aws_s3_bucket.web_server_state_destination.bucket

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

# ** the encryption configuration for state source and destination

resource "aws_s3_bucket_server_side_encryption_configuration" "web_server_state_source" {
  bucket = aws_s3_bucket.web_server_state_source.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.adminaccount_web_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "web_server_state_destination" {
  bucket = aws_s3_bucket.web_server_state_destination.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.adminaccount_web_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}
# ** the public access block
resource "aws_s3_bucket_public_access_block" "web_server_state_source" { # OK
  bucket = aws_s3_bucket.web_server_state_source.id

  block_public_acls       = true # block any acls that would make it public
  block_public_policy     = true # block any policies that would make it public
  ignore_public_acls      = true # ignore current public policies
  restrict_public_buckets = true # only aws services and owner can access if pub
}

resource "aws_s3_bucket_public_access_block" "web_server_state_destination" { # OK
  bucket = aws_s3_bucket.web_server_state_destination.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ** the state bucket themselves , source and destination

resource "aws_s3_bucket" "web_server_state_source" { # OK
  bucket        = "web-server-state-source-2"
  force_destroy = true

  # required for load balancer access logs
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

}

resource "aws_s3_bucket" "web_server_state_destination" { # OK
  bucket        = "web-server-state-destination-2"
  force_destroy = true

  # required for load balancer access logs
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

}

# ** the iam policy that contains requirements for the state file

data "aws_iam_policy_document" "web_server_state_source" { # OK
  # for bucket access logging
  statement {
    principals {
      identifiers = ["logging.s3.amazonaws.com"]
      type        = "Service"
    }
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${aws_s3_bucket.web_server_state_source.id}/bucket-logging-log/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }
  }
  statement {
    principals {
      type = "AWS"

      identifiers = ["arn:aws:iam::${var.aws_source_account_id}:role/terraform"]
    }
    effect    = "Allow"
    resources = ["${aws_s3_bucket.web_server_state_source.arn}"]
    actions   = ["s3:ListBucket"]

    condition {
      test     = "StringEquals"
      variable = "s3:prefix"
      values   = ["web_server_state_source/terraform_state_file"]
    }
  }

  # allow terraform to put a state file
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_source_account_id}:role/terraform"]
    }
    resources = ["${aws_s3_bucket.web_server_state_source.arn}/terraform_state_file"]

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
  }

  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_source_account_id}:role/terraform"]
    }
    resources = ["${aws_s3_bucket.web_server_state_source.arn}/terraform_state_file.tflock"]

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
  }
}

# the role attachment
# bucket side
resource "aws_s3_bucket_policy" "web_server_state_source" { # OK
  bucket = aws_s3_bucket.web_server_state_source.id
  policy = data.aws_iam_policy_document.web_server_state_source.json
}

# client-side (allow root to assume the role)
data "aws_iam_policy_document" "terraform_assume_role" { # OK
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
      "sts:SetSourceIdentity"
    ]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_source_account_id}:user/adminaccount"]
    }
  }
}

resource "aws_iam_role" "terraform" { # OK
  name               = "terraform"
  assume_role_policy = data.aws_iam_policy_document.terraform_assume_role.json
}

# ** the state bucket same-region replication configuration

# *** the permissions required for replication
data "aws_iam_policy_document" "web_server_state_replication_assume_role" { # OK
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "web_server_state_replication" { # OK
  name               = "web_server_state_replication"
  assume_role_policy = data.aws_iam_policy_document.web_server_state_replication_assume_role.json
}

data "aws_iam_policy_document" "web_server_state_replication_listing" { # OK
  statement {
    effect = "Allow"

    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]

    resources = [aws_s3_bucket.web_server_state_source.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]

    resources = ["${aws_s3_bucket.web_server_state_source.arn}/*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]

    resources = ["${aws_s3_bucket.web_server_state_destination.arn}/*"]
  }
}

resource "aws_iam_policy" "web_server_state_replication_listing" { # OK
  name   = "web_server_state_replication_listing"
  policy = data.aws_iam_policy_document.web_server_state_replication_listing.json
}

resource "aws_iam_role_policy_attachment" "web_server_state_replication" { # OK
  role       = aws_iam_role.web_server_state_replication.name
  policy_arn = aws_iam_policy.web_server_state_replication_listing.arn
}

# *** the actual bucket replication configuration
resource "aws_s3_bucket_replication_configuration" "web_server_state_replication" { # OK
  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.web_server_state_source]

  # assume this role for the replication
  role = aws_iam_role.web_server_state_replication.arn
  # to replicate this bucket
  bucket = aws_s3_bucket.web_server_state_source.id

  rule {
    id = "all" # of rule this name
    # Replication configuration XML V2 includes the Filter element for rules.
    # If you specify a rule with an empty filter tag your rule will apply to all
    # objects in your bucket
    delete_marker_replication {
      status = "Enabled"
    }
    filter {
      prefix = "" # all?
    }
    status = "Enabled"

    # to this bucket
    destination {
      bucket        = aws_s3_bucket.web_server_state_destination.arn
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
