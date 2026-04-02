# * the state bucket and policies

# ** the state bucket, source and destination

resource "aws_s3_bucket" "web_server_state_source" {
  tags = {
    Name = "web_server_state_source"
  }

  transition {
    storage_class = "STANDARD_IA"
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
        kms_master_key_id = aws_kms_key.sdobrau_web.id
      }
    }
  }
}

resource "aws_s3_bucket" "web_server_state_destination" {
  tags = {
    Name = "web_server_state_destination"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
        kms_master_key_id = aws_kms_key.sdobrau_web.id
      }
    }
  }
}

# ** the iam policy that contains requirements for the state file

data "aws_iam_policy_document" "web_server_terraform" {
  name = "web_server_terraform"
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": "s3:ListBucket",
        "Resource": "arn:aws:s3:::web_server_state_source",
        "Condition": {
          "StringEquals": {
            "s3:prefix": "web_server_state_source/terraform_state_file"
          }
        }
      },
      {
        "Effect": "Allow",
        "Action": ["s3:GetObject", "s3:PutObject"],
        "Resource": [
          "arn:aws:s3:::web_server_state_source/terraform_state_file"
        ]
      },
      {
        "Effect": "Allow",
        "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
        "Resource": [
          "arn:aws:s3:::web_server_state_source/terraform_state_file.tflock"
        ]
      }
    ]
  })
}

# the role attachment
# bucket side
resource "aws_s3_bucket_policy" "web_server_terraform" {
  bucket = aws_s3_bucket.web_server_terraform.id
  policy = data.aws_iam_policy_document.web_server_terraform.json
}

# TODO: proper form for referencing data?
# client-side (allow root to assume the role)

data "aws_iam_policy_document" "web_server_terraform" {
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
      "sts:SetSourceIdentity"
    ]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.source.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "web_server_terraform" {
  name = "web_server_terraform"
  assume_role_policy = data.aws_iam_policy_document.web_server_terraform.json
}

data "aws_iam_policy_document" "web_server_terraform" {
  provider = aws.destination
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
      "sts:SetSourceIdentity"
    ]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.source.account_id}:root"]
    }
  }
}

# ** TODO the state bucket same-region replication configuration

# *** the versioning for both buckets (necessary)
resource "aws_s3_bucket_versioning" "web_server_state_source" {
  bucket = aws_s3_bucket.web_server_state_source.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "web_server_state_destination" {
  bucket = aws_s3_bucket.web_server_state_destination.id
  versioning_configuration {
    status = "Enabled"
  }
}

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
  role   = aws_iam_role.web_server_state_replication.arn
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
    }
  }
}
