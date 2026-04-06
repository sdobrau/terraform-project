# * the access logging settings (save as parquet to log-bucket)

# TODO (why?) does this need to be in us-east-1?
resource "aws_cloudwatch_log_delivery_source" "cloudfront" {
  #region = "us-east-1"

  name         = "cloudfront"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.cloudfront.arn
}

resource "aws_cloudwatch_log_delivery_destination" "cloudfront" {
  #region = "us-east-1"

  name          = "cloudfront"
  output_format = "parquet"

  delivery_destination_configuration {
    destination_resource_arn = var.log_bucket_arn
  }
}

resource "aws_cloudwatch_log_delivery" "example" {
  #region = "us-east-1"

  delivery_source_name     = aws_cloudwatch_log_delivery_source.cloudfront.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.cloudfront.arn

  s3_delivery_configuration {
    # suffix_path/AWSLogs/ACCOUNTID/CloudFront
    suffix_path = "/123456678910/{DistributionId}/{yyyy}/{MM}/{dd}/{HH}"
  }
}

# * The bucket(enc+repl) and policy for logging cloudfront Web ACL TODO:
# ** the lifecycle configuration, access logging, versioning, public access blocking, encryption and replication config
# *** the event notification sns topics with encryption for both buckets
resource "aws_sns_topic" "aws-waf-logs-cloudfront_source_bucket_notification" {
  name              = "aws-waf-logs-cloudfront_source_bucket_notification"
  kms_master_key_id = var.adminaccount_web_key_id
}

resource "aws_sns_topic" "aws-waf-logs-cloudfront_destination_bucket_notification" {
  name              = "aws-waf-logs-cloudfront_destination_bucket_notification"
  kms_master_key_id = var.adminaccount_web_key_id # encryption
}

# *** the bucket notification settings: send to sns topics
resource "aws_s3_bucket_notification" "aws-waf-logs-cloudfront_source_bucket_notification" {
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_source.id

  topic {
    topic_arn = aws_sns_topic.aws-waf-logs-cloudfront_source_bucket_notification.arn
    events    = ["s3:ObjectCreated:*"]
    # log sent by instance
    filter_prefix = "*" # TODO: right dir? main_log
  }
}

resource "aws_s3_bucket_notification" "aws-waf-logs-cloudfront_destination_bucket_notification" {
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_destination.id

  topic {
    topic_arn = aws_sns_topic.aws-waf-logs-cloudfront_destination_bucket_notification.arn
    events    = ["s3:ObjectCreated:*"]
    # when replication done ? TODO
    filter_prefix = "*" # TODO: right dir? main_log
  }
}

# *** the lifecycle configurations
resource "aws_s3_bucket_lifecycle_configuration" "aws-waf-logs-cloudfront_source" {
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_source.bucket

  rule {
    id = "rule-1"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    transition {
      days          = 0
      storage_class = "STANDARD_IA" # by default
    }

    transition {
      days          = 30 # after 30 days use glacier
      storage_class = "GLACIER"
      # ... other transition/expiration actions ...
    }
    transition {
      days          = 60 # after 30 days use glacier
      storage_class = "DEEP_ARCHIVE"
      # ... other transition/expiration actions ...
    }
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "aws-waf-logs-cloudfront_destination" {
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_destination.bucket

  rule {
    id = "rule-1"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    transition {
      days          = 0
      storage_class = "STANDARD_IA" # by default
    }

    transition {
      days          = 30 # after 30 days use glacier
      storage_class = "GLACIER"
      # ... other transition/expiration actions ...
    }
    transition {
      days          = 60 # after 30 days use glacier
      storage_class = "DEEP_ARCHIVE"
      # ... other transition/expiration actions ...
    }
    status = "Enabled"
  }
}

# *** the public access blocks
resource "aws_s3_bucket_public_access_block" "aws-waf-logs-cloudfront_source" {
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_source.id

  block_public_acls       = true # block any acls that would make it public
  block_public_policy     = true # block any policies that would make it public
  ignore_public_acls      = true # ignore current public policies
  restrict_public_buckets = true # only aws services and owner can access if pub
}

resource "aws_s3_bucket_public_access_block" "aws-waf-logs-cloudfront_destination" {
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_destination.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# *** the bucket versionings
resource "aws_s3_bucket_versioning" "aws-waf-logs-cloudfront_source" {
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_source.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "aws-waf-logs-cloudfront_destination" {
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_destination.id
  versioning_configuration {
    status = "Enabled"
  }
}

# *** the access logging in same bucket
# **** the iam permissions required for access logging to work
data "aws_iam_policy_document" "aws-waf-logs-cloudfront_source_logging" {
  statement {
    principals {
      identifiers = ["logging.s3.amazonaws.com"]
      type        = "Service"
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.aws-waf-logs-cloudfront_source.arn}/bucket-logging-log/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }
  }
}

# TODO: bucket logging for both bucket and state buckets to logging bucket
resource "aws_s3_bucket_policy" "aws-waf-logs-cloudfront_source" {
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_source.bucket
  policy = data.aws_iam_policy_document.aws-waf-logs-cloudfront_source_logging.json
}

data "aws_iam_policy_document" "aws-waf-logs-cloudfront_destination_logging" {
  statement {
    principals {
      identifiers = ["logging.s3.amazonaws.com"]
      type        = "Service"
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.aws-waf-logs-cloudfront_destination.arn}/bucket-logging-log/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }
  }
}

# TODO: bucket logging for both bucket and state buckets to logging bucket
resource "aws_s3_bucket_policy" "aws-waf-logs-cloudfront_destination" {
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_destination.bucket
  policy = data.aws_iam_policy_document.aws-waf-logs-cloudfront_destination_logging.json
}

# **** the access logging settings themselves
resource "aws_s3_bucket_logging" "aws-waf-logs-cloudfront_source" {
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_source.bucket

  target_bucket = var.log_bucket_bucket
  target_prefix = "bucket-logging-log/"
  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

resource "aws_s3_bucket_logging" "aws-waf-logs-cloudfront_destination" {
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_destination.bucket

  target_bucket = var.log_bucket_bucket
  target_prefix = "bucket-logging-log/"
  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

# *** the sse-cs
resource "aws_s3_bucket_server_side_encryption_configuration" "aws-waf-logs-cloudfront_source" {
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_source.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.adminaccount_web_key_id
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "aws-waf-logs-cloudfront_destination" {
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_destination.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.adminaccount_web_key_id
      sse_algorithm     = "aws:kms"
    }
  }
}

# *** the policies for replication
data "aws_iam_policy_document" "aws-waf-logs-cloudfront_replication_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "aws-waf-logs-cloudfront_replication" {
  name               = "web_server_logs_replication"
  assume_role_policy = data.aws_iam_policy_document.aws-waf-logs-cloudfront_replication_assume_role.json
}

data "aws_iam_policy_document" "aws-waf-logs-cloudfront_replication_listing" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]

    resources = [aws_s3_bucket.aws-waf-logs-cloudfront_source.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]

    resources = ["${aws_s3_bucket.aws-waf-logs-cloudfront_source.arn}/*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]

    resources = ["${aws_s3_bucket.aws-waf-logs-cloudfront_destination.arn}/*"]
  }
}

resource "aws_iam_policy" "aws-waf-logs-cloudfront_replication" {
  name   = "aws-waf-cloudfront_replication"
  policy = data.aws_iam_policy_document.aws-waf-logs-cloudfront_replication_listing.json
}

resource "aws_iam_role_policy_attachment" "aws-waf-logs-cloudfront_replication" {
  role       = aws_iam_role.aws-waf-logs-cloudfront_replication.name
  policy_arn = aws_iam_policy.aws-waf-logs-cloudfront_replication.arn
}

# *** the actual bucket replication configuration
resource "aws_s3_bucket_replication_configuration" "aws-waf-logs-cloudfront_replication" {
  region = "eu-north-1"

  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.aws-waf-logs-cloudfront_source]

  role   = aws_iam_role.aws-waf-logs-cloudfront_replication.arn
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_source.id

  rule {
    id = "all"

    # replicate everything
    # filter {
    #   prefix = "example"
    # }

    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.aws-waf-logs-cloudfront_destination.arn
      storage_class = "STANDARD_IA"
    }
  }
}

# ** the bucket itself and policy
resource "aws_s3_bucket" "aws-waf-logs-cloudfront_source" {
  bucket = "aws-waf-logs-cloudfront"
}

resource "aws_s3_bucket" "aws-waf-logs-cloudfront_destination" {
  bucket = "aws-waf-logs-cloudfront"
}

# # TODO: debug bucket policies
# resource "aws_s3_bucket_policy" "aws-waf-logs-cloudfront_source" {
#   bucket = aws_s3_bucket.aws-waf-logs-cloudfront_source.id

# policy = jsonencode({
#   Version = "2012-10-17"
#   Id      = "AWSLogDeliveryWrite20150319"
#   Statement = [
#     {
#       Sid    = "AWSLogDeliveryAclCheck"
#       Effect = "Allow"
#       Principal = {
#         Service = "delivery.logs.amazonaws.com" # WAF logging
#       }
#       Action   = "s3:GetBucketAcl" # to verify if can write logs
#       Resource = aws_s3_bucket.aws-waf-logs-cloudfront_source.arn
#       Condition = {
#         StringEquals = {
#           "aws:SourceAccount" = [var.aws_source_account_id]
#         }
#         ArnLike = {
#           "aws:SourceArn" = "arn:aws:logs:${data.aws_region.current.name}:${var.aws_source_account_id}:*"
#         }
#       }
#     },
#     {
#       Sid    = "AWSLogDeliveryWrite"
#       Effect = "Allow"
#       Principal = {
#         Service = "delivery.logs.amazonaws.com" # WAF logging
#       }
#       Action   = "s3:PutObject" # can put object
#       Resource = "${aws_s3_bucket.waf_logs.arn}/*"
#       Condition = {
#         StringEquals = {
#           "s3:x-amz-acl"      = "bucket-owner-full-control"
#           "aws:SourceAccount" = [var.aws_source_account_id]
#         }
#         ArnLike = {
#           "aws:SourceArn" = "arn:aws:logs:${data.aws_region.current.name}:${var.aws_source_account_id}:*"
#         }
#       }
#     }
#   ]
# })
# }


# * The ACL logging for the CKV2_AWS_47 setup
resource "aws_wafv2_web_acl_logging_configuration" "example" {
  log_destination_configs = [aws_s3_bucket.aws-waf-logs-cloudfront_source.arn]
  resource_arn            = aws_wafv2_web_acl.cloudfront_no_log4j.arn
}

# * the ACL for preventing  CKV2_AWS_47
# https://docs.prismacloud.io/en/enterprise-edition/policy-reference/aws-policies/aws-general-policies/bc-aws-general-47

resource "aws_wafv2_web_acl" "cloudfront_no_log4j" {
  name        = "cloudfront_no_log4j"
  description = "Example of a managed rule."
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "rule-1"
    priority = 1

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAnonymousIpList"
        vendor_name = "AWS"

        # excluded_rule { suggested by CKV2_AWS_47 but not available
        #   name = "SizeRestrictions_QUERYSTRING"
        # }

        scope_down_statement {
          geo_match_statement {
            country_codes = ["US", "NL"]
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "friendly-rule-metric-name"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "rule-2"
    priority = 2

    override_action {
      none {} # none for test to pass
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "friendly-rule-metric-name"
      sampled_requests_enabled   = false
    }
  }


  tags = {
    Tag1 = "Value1"
    Tag2 = "Value2"
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "friendly-metric-name"
    sampled_requests_enabled   = false
  }
}

# * the distribution NOTE: only one required to be in us-east-1
# ** the distribution declaration
resource "aws_cloudfront_distribution" "cloudfront" {
  origin {
    domain_name = var.web_server_alb_dns_name
    origin_id   = "web_server_origin"
    # Add secret header to all requests to ALB
    custom_header {
      name  = "X-Custom-Secret"
      value = var.web_server_cloudfront_secret_value
    }
    # only https
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only" # allow only https
      origin_ssl_protocols   = ["TLSv1.2"]  # allow TLSv1.2
    }
    # shield
    origin_shield {
      enabled              = true
      origin_shield_region = "eu-north-1"
    }

  }

  enabled             = true
  is_ipv6_enabled     = false
  comment             = "CloudFront distribution with ALB"
  default_root_object = "index.html" # Modify as needed

  logging_config {
    bucket = var.log_bucket_domain_name
    prefix = "cloudfront-logs/"
  }

  default_cache_behavior {
    target_origin_id       = "web_server_origin"
    viewer_protocol_policy = "redirect-to-https" # Change based on your needs
    allowed_methods        = ["GET"]
    cached_methods         = ["GET"] # cache get requests
    compress               = true    # compress Accept-Encoding: gzip
    default_ttl            = 86400   # 1-day TTL
    min_ttl                = 0
    max_ttl                = 31536000 # 1-year TTL

    # If you have specific cache behavior settings
    forwarded_values {
      query_string = false
      headers      = ["Authorization"]
      cookies {
        forward = "none" # no cookies required
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    # serving same domain as the alb so using the same cert as the alb
    acm_certificate_arn = var.aws_playing_cloud_xyz_certificate_arn
    #ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2025"
  }

  # Optionally set price class
  price_class = "PriceClass_100" # no africa/middle east/asia/india

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "RO"] # US, Canada, UK, Romania
    }
  }
  web_acl_id = aws_wafv2_web_acl.cloudfront_no_log4j.name
}

# headers setting

resource "aws_cloudfront_response_headers_policy" "cloudfront" {
  name    = "cloudfront"
  comment = "Security headers policy"
  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
      preload                    = true
    }

    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY" # TODO: read / prevent clickjacking attacks
      override     = true
    }

    referrer_policy {
      # when request is cross-origin
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }

  custom_headers_config {
    items {
      header   = "X-Custom-Header"
      value    = var.web_server_cloudfront_secret_value
      override = true
    }
  }
}

# ** the distribution certificate: NEEDS to be in us-east-1
resource "aws_acm_certificate" "cloudfront" {
  region      = "us-east-1"
  domain_name = "playing-cloud.com"
}
