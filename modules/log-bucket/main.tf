# * the log bucket for the elb and servers, source and destination

resource "aws_s3_bucket" "web_server_logs_source" {
  bucket = "web_server_logs_source"

  tags = {
    component = "web"
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

resource "aws_s3_bucket" "web_server_logs_destination" {
  bucket = "web_server_logs_destination"

  tags = {
    component = "web"
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

# ** the bucket policy: allow put object from the web_server instance role and elb DONE

resource "aws_iam_policy" "web_server_elb_access_logs_and_ec2_instances" {
  name = "web_server_elb_access_logs_and_ec2_instances"
  policy = jsonencode({

    "Version":"2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "logdelivery.elasticloadbalancing.amazonaws.com"
        },
        "Action": "s3:PutObject",
        "Resource": "arn:aws:s3:::web_server_logs_source/access_logs/*"
      },
      {
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::${data.aws_caller_identity.source.account_id}:role/web_server"
        },
        "Action": "s3:PutObject",
        "Resource": [
          "arn:aws:s3:::web_server_logs_source/main_logs"
        ]
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "web_server_instance" {
  bucket = aws_s3_bucket.web_server_logs.id
  policy = aws_iam_policy.web_server_elb_access_logs_and_ec2_instances.id
}

# ** the logs bucket replication configuration

# *** the permissions required for replication
data "aws_iam_policy_document" "web_server_logs_replication_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "web_server_logs_replication" {
  name               = "web_server_logs_replication"
  assume_role_policy = data.aws_iam_policy_document.web_server_logs_replication_assume_role.json
}

data "aws_iam_policy_document" "web_server_logs_replication_listing" {
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

resource "aws_iam_policy" "web_server_logs_replication" {
  name   = "web_server_logs_replication"
  policy = data.aws_iam_policy_document.web_server_logs_replication.json
}

resource "aws_iam_role_policy_attachment" "web_server_logs_replication" {
  role       = aws_iam_role.web_server_logs_replication.name
  policy_arn = aws_iam_policy.web_server_logs_replication.arn
}

# *** the versioning for both buckets (necessary)
resource "aws_s3_bucket_versioning" "web_server_logs_source" {
  bucket = aws_s3_bucket.web_server_logs_source.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "web_server_logs_destination" {
  bucket = aws_s3_bucket.web_server_logs_destination.id
  versioning_configuration {
    status = "Enabled"
  }
}

# *** the actual bucket replication configuration

resource "aws_s3_bucket_replication_configuration" "web_server_logs_replication" {
  region = "eu-central-1"

  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.web_server_logs_source]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.source.id

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
    }
  }
}
