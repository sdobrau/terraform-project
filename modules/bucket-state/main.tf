# * the state bucket and policies

# ** the sns topics with encryption for both buckets
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
    topic_arn = aws_sns_topic.web_server_state_destination_bucket_notification.arn
    events    = ["s3:ObjectCreated:*"]
    # when replication done ? TODO
    filter_prefix = "terraform_state_file.tflock"
  }
}

# # FIXME TODO: debug this soon. resource not valid
# # ** the bucket logging configurations for both buckets
# data "aws_iam_policy_document" "web_server_state_source_logging" {
#   statement {
#     principals {
#       identifiers = ["logging.s3.amazonaws.com"]
#       type        = "Service"
#     }
#     actions = ["s3:PutObject"]
#     # TODO: debug replace this with var form soon
#     resources = ["arn:aws:s3:::web-server-logs-source/bucket-logging-log/*"]
#     condition {
#       test     = "StringEquals"
#       variable = "aws:SourceAccount"
#       values   = [var.aws_source_account_id]
#     }
#   }
# }

# # TODO: bucket logging for both bucket and state buckets to logging bucket
# resource "aws_s3_bucket_policy" "web_server_state_source" { # OK
#   bucket = aws_s3_bucket.web_server_state_source.id
#   policy = data.aws_iam_policy_document.web_server_state_source_logging.json
# }

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
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "web_server_state_destination" { # OK
  bucket = aws_s3_bucket.web_server_state_destination.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ** the encryption configuration for state source and destination

resource "aws_s3_bucket_lifecycle_configuration" "web_server_state_source" {
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

resource "aws_s3_bucket_lifecycle_configuration" "web_server_state_destination" {
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
      kms_master_key_id = var.adminaccount_web_key_id
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "web_server_state_destination" {
  bucket = aws_s3_bucket.web_server_state_destination.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.adminaccount_web_key_id
      sse_algorithm     = "aws:kms"
    }
  }
}

# ** the public access block
resource "aws_s3_bucket_public_access_block" "web_server_state_source" {
  bucket = aws_s3_bucket.web_server_state_source.id

  block_public_acls       = true # block any acls that would make it public
  block_public_policy     = true # block any policies that would make it public
  ignore_public_acls      = true # ignore current public policies
  restrict_public_buckets = true # only aws services and owner can access if pub
}

resource "aws_s3_bucket_public_access_block" "web_server_state_destination" {
  bucket = aws_s3_bucket.web_server_state_destination.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ** the state bucket, source and destination

resource "aws_s3_bucket" "web_server_state_source" {
  bucket = "web-server-state-source"
}

resource "aws_s3_bucket" "web_server_state_destination" {
  bucket = "web-server-state-destination"
}

# ** the iam policy that contains requirements for the state file

data "aws_iam_policy_document" "web_server_terraform" {
  statement {
    principals {
      type = "AWS"

      identifiers = ["arn:aws:iam::${var.aws_source_account_id}:role/web_server_terraform"]
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


  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_source_account_id}:role/web_server_terraform"]
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
      identifiers = ["arn:aws:iam::${var.aws_source_account_id}:role/web_server_terraform"]
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
resource "aws_s3_bucket_policy" "web_server_terraform" { # OK
  bucket = aws_s3_bucket.web_server_state_source.id
  policy = data.aws_iam_policy_document.web_server_terraform.json
}

# TODO: proper form for referencing data?
# client-side (allow root to assume the role)

data "aws_iam_policy_document" "web_server_terraform_assume_role" { # OK
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

resource "aws_iam_role" "web_server_terraform" { # OK
  name               = "web_server_terraform"
  assume_role_policy = data.aws_iam_policy_document.web_server_terraform_assume_role.json
}

# ** TODO the state bucket same-region replication configuration

# *** the permissions required for replication
data "aws_iam_policy_document" "web_server_state_replication_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "web_server_state_replication" {
  name               = "web_server_state_replication"
  assume_role_policy = data.aws_iam_policy_document.web_server_state_replication_assume_role.json
}

data "aws_iam_policy_document" "web_server_state_replication_listing" {
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

resource "aws_iam_policy" "web_server_state_replication_listing" {
  name   = "web_server_state_replication_listing"
  policy = data.aws_iam_policy_document.web_server_state_replication_listing.json
}

resource "aws_iam_role_policy_attachment" "web_server_state_replication" {
  role       = aws_iam_role.web_server_state_replication.name
  policy_arn = aws_iam_policy.web_server_state_replication_listing.arn
}

# *** the actual bucket replication configuration
resource "aws_s3_bucket_replication_configuration" "web_server_state_replication" {
  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.web_server_state_source]

  # assume this role for the replication
  role = aws_iam_role.web_server_state_replication.arn
  # to replicate this bucket
  bucket = aws_s3_bucket.web_server_state_source.id

  rule {
    id = "all" # of rule this name

    # replicate everything
    # filter {
    #   prefix = "example" # for keys matching this prefix
    # }
    status = "Enabled"

    # to this bucket
    destination {
      bucket        = aws_s3_bucket.web_server_state_destination.arn
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
