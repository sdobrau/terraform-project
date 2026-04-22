# * standard logging v2 for cloudfront distribution

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  required_version = "~> 1.14"
}

data "aws_region" "current" {
  provider = aws
}

# vv require cloudfront distribution to be created first
resource "aws_cloudwatch_log_delivery_source" "cloudfront" { # OK
  name = "cloudfront"
  #checkov:skip=CKV_AWS_86:Access logging is configured for Cloudfront w/
  #CloudWatch
  # ignore AVD-AWS-0013: configured here
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.cloudfront.arn
}

resource "aws_cloudwatch_log_delivery_destination" "cloudfront" { # OK
  name          = "cloudfront"
  output_format = "parquet"

  delivery_destination_type = "S3"
  delivery_destination_configuration {
    destination_resource_arn = var.log_bucket_arn
  }
}

resource "aws_cloudwatch_log_delivery" "cloudfront" { # TODO: test
  delivery_source_name     = aws_cloudwatch_log_delivery_source.cloudfront.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.cloudfront.arn

  s3_delivery_configuration {
    # suffix_path/AWSLogs/ACCOUNTID/CloudFront
    suffix_path = "/123456678910/{DistributionId}/{yyyy}/{MM}/{dd}/{HH}"
  }
}

# * The bucket(enc+repl) and policy for logging cloudfront Web ACL
# ** the lifecycle configuration, access logging, versioning, public access blocking, encryption and replication config
# *** the event notification sns topics with encryption for both buckets

resource "aws_sns_topic" "aws-waf-logs-cloudfront_source_bucket_notification" { # OK
  name              = "aws-waf-logs-cloudfront_source_bucket_notification"
  kms_master_key_id = var.adminaccount_web_key_id
}

resource "aws_sns_topic" "aws-waf-logs-cloudfront_destination_bucket_notification" { # OK
  name              = "aws-waf-logs-cloudfront_destination_bucket_notification"
  kms_master_key_id = var.adminaccount_web_key_id
}

# # *** the policy to use as a resource policy in sns topics

data "aws_iam_policy_document" "aws-waf-logs-cloudfront_source_bucket_notification_s3_to_sns" { # OK

  statement {
    sid       = "Example SNS topic policy"
    effect    = "Allow"
    resources = [aws_sns_topic.aws-waf-logs-cloudfront_source_bucket_notification.arn]
    actions   = ["SNS:Publish"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.aws-waf-logs-cloudfront_source.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "aws-waf-logs-cloudfront_destination_bucket_notification_s3_to_sns" { # OK

  statement {
    sid       = "Example SNS topic policy"
    effect    = "Allow"
    resources = [aws_sns_topic.aws-waf-logs-cloudfront_destination_bucket_notification.arn]
    actions   = ["SNS:Publish"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.aws-waf-logs-cloudfront_destination.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "aws-waf-logs-cloudfront_source_bucket_notification" { # OK
  arn    = aws_sns_topic.aws-waf-logs-cloudfront_source_bucket_notification.arn
  policy = data.aws_iam_policy_document.aws-waf-logs-cloudfront_source_bucket_notification_s3_to_sns.json
}

resource "aws_sns_topic_policy" "aws-waf-logs-cloudfront_destination_bucket_notification" { # OK
  arn    = aws_sns_topic.aws-waf-logs-cloudfront_destination_bucket_notification.arn
  policy = data.aws_iam_policy_document.aws-waf-logs-cloudfront_destination_bucket_notification_s3_to_sns.json
}

# *** the bucket notification settings: send to sns topics

resource "aws_s3_bucket_notification" "aws-waf-logs-cloudfront_source_bucket_notification" { # OK
  depends_on = [aws_sns_topic.aws-waf-logs-cloudfront_source_bucket_notification]
  bucket     = aws_s3_bucket.aws-waf-logs-cloudfront_source.bucket

  topic {
    topic_arn = aws_sns_topic.aws-waf-logs-cloudfront_source_bucket_notification.arn
    events    = ["s3:ObjectCreated:*"]
    # log sent by instance
    filter_prefix = "main_log/*"
  }
}

resource "aws_s3_bucket_notification" "aws-waf-logs-cloudfront_destination_bucket_notification" { # OK
  depends_on = [aws_sns_topic.aws-waf-logs-cloudfront_destination_bucket_notification]
  bucket     = aws_s3_bucket.aws-waf-logs-cloudfront_destination.bucket

  topic {
    topic_arn = aws_sns_topic.aws-waf-logs-cloudfront_destination_bucket_notification.arn
    events    = ["s3:ObjectCreated:*"]
    # when replication done ?
    filter_prefix = "main_log/*"
  }
}

# *** the lifecycle configurations
resource "aws_s3_bucket_lifecycle_configuration" "aws-waf-logs-cloudfront_source" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_source.bucket

  rule {
    id = "rule-1"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
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

resource "aws_s3_bucket_lifecycle_configuration" "aws-waf-logs-cloudfront_destination" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_destination.bucket

  rule {
    id = "rule-1"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
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

# *** the public access blocks
resource "aws_s3_bucket_public_access_block" "aws-waf-logs-cloudfront_source" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_source.id

  block_public_acls       = true # block any acls that would make it public
  block_public_policy     = true # block any policies that would make it public
  ignore_public_acls      = true # ignore current public policies
  restrict_public_buckets = true # only aws services and owner can access if pub
}

resource "aws_s3_bucket_public_access_block" "aws-waf-logs-cloudfront_destination" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_destination.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# *** the bucket versionings
resource "aws_s3_bucket_versioning" "aws-waf-logs-cloudfront_source" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_source.id
  # mfa    = "serialnumber authvalue"
  versioning_configuration {
    status = "Enabled"
    # mfa_delete = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "aws-waf-logs-cloudfront_destination" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_destination.id
  # mfa    = "serialnumber authvalue"
  versioning_configuration {
    status = "Enabled"
    # mfa_delete = "Enabled"
  }
}

# *** the access logging in same bucket
# **** the access logging settings themselves
resource "aws_s3_bucket_logging" "aws-waf-logs-cloudfront_source" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_source.bucket

  target_bucket = var.log_bucket_bucket
  target_prefix = "bucket-logging-log/"
  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

resource "aws_s3_bucket_logging" "aws-waf-logs-cloudfront_destination" { # OK
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
resource "aws_s3_bucket_server_side_encryption_configuration" "aws-waf-logs-cloudfront_source" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_source.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.adminaccount_web_key_arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "aws-waf-logs-cloudfront_destination" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_destination.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.adminaccount_web_key_arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# *** the policies for replication
data "aws_iam_policy_document" "aws-waf-logs-cloudfront_replication_assume_role" { # OK
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "aws-waf-logs-cloudfront_replication" { # OK
  name               = "aws-waf-logs-cloudfront_replication"
  assume_role_policy = data.aws_iam_policy_document.aws-waf-logs-cloudfront_replication_assume_role.json
}

data "aws_iam_policy_document" "aws-waf-logs-cloudfront_replication_listing" { # OK
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

resource "aws_iam_policy" "aws-waf-logs-cloudfront_replication" { # OK
  name   = "aws-waf-cloudfront_replication"
  policy = data.aws_iam_policy_document.aws-waf-logs-cloudfront_replication_listing.json
}

resource "aws_iam_role_policy_attachment" "aws-waf-logs-cloudfront_replication" {
  role       = aws_iam_role.aws-waf-logs-cloudfront_replication.name
  policy_arn = aws_iam_policy.aws-waf-logs-cloudfront_replication.arn
}

# *** the actual bucket replication configuration
resource "aws_s3_bucket_replication_configuration" "aws-waf-logs-cloudfront_replication" { # OK

  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.aws-waf-logs-cloudfront_source]

  role   = aws_iam_role.aws-waf-logs-cloudfront_replication.arn
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_source.id

  rule {
    id = "all"
    # Replication configuration XML V2 includes the Filter element for rules.
    # If you specify a rule with an empty filter tag your rule will apply to all
    # objects in your bucket
    filter {
      prefix = "" # all?
    }
    delete_marker_replication {
      status = "Enabled"
    }
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.aws-waf-logs-cloudfront_destination.arn
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

# ** the bucket itself and policy

resource "aws_s3_bucket" "aws-waf-logs-cloudfront_source" { # OK
  bucket        = "aws-waf-logs-cloudfront-source-1"
  force_destroy = true
}

resource "aws_s3_bucket" "aws-waf-logs-cloudfront_destination" { # OK
  bucket        = "aws-waf-logs-cloudfront-destination-1"
  force_destroy = true
}

# *** the policy document as recommended by AWS

data "aws_iam_policy_document" "aws-waf-logs-cloudfront_source" { # OK
  statement {
    sid       = "AWSLogDeliveryWrite"
    effect    = "Allow"
    resources = ["${aws_s3_bucket.aws-waf-logs-cloudfront_source.arn}/*"]
    actions   = ["s3:PutObject"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${var.aws_source_account_id}:*"]
    }

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSLogDeliveryAclCheck"
    effect    = "Allow"
    resources = [aws_s3_bucket.aws-waf-logs-cloudfront_source.arn]
    actions   = ["s3:GetBucketAcl"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:us-east-2:${var.aws_source_account_id}:*"]
    }

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
  }
  # for bucket logging
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

data "aws_iam_policy_document" "aws-waf-logs-cloudfront_destination" { # OK
  statement {
    sid       = "AWSLogDeliveryWrite"
    effect    = "Allow"
    resources = ["${aws_s3_bucket.aws-waf-logs-cloudfront_destination.arn}/*"]
    actions   = ["s3:PutObject"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${var.aws_source_account_id}:*"]
    }

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSLogDeliveryAclCheck"
    effect    = "Allow"
    resources = [aws_s3_bucket.aws-waf-logs-cloudfront_destination.arn]
    actions   = ["s3:GetBucketAcl"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:us-east-2:${var.aws_source_account_id}:*"]
    }

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
  }
  # for bucket logging
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

resource "aws_s3_bucket_policy" "aws-waf-logs-cloudfront_source" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_source.bucket
  policy = data.aws_iam_policy_document.aws-waf-logs-cloudfront_source.json
}

resource "aws_s3_bucket_policy" "aws-waf-logs-cloudfront_destination" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-cloudfront_destination.bucket
  policy = data.aws_iam_policy_document.aws-waf-logs-cloudfront_destination.json
}

# * The ACL logging for the CKV2_AWS_47 setup
resource "aws_wafv2_web_acl_logging_configuration" "aws-waf-logs-cloudfront_source" {
  log_destination_configs = [aws_s3_bucket.aws-waf-logs-cloudfront_source.arn]
  resource_arn            = aws_wafv2_web_acl.cloudfront_no_log4j.arn
}

# * the ACL for preventing  CKV2_AWS_47
# https://docs.prismacloud.io/en/enterprise-edition/policy-reference/aws-policies/aws-general-policies/bc-aws-general-47

resource "aws_wafv2_web_acl" "cloudfront_no_log4j" { # OK
  name        = "cloudfront_no_log4j"
  description = "Example of a managed rule."
  scope       = "CLOUDFRONT"

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

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "friendly-metric-name"
    sampled_requests_enabled   = false
  }
}

# * the distribution NOTE: only one required to be in us-east-1

# ** the vpc origin with the alb

resource "aws_cloudfront_vpc_origin" "alb" {
  vpc_origin_endpoint_config {
    name                   = "alb-origin"
    arn                    = var.web_server_alb_arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"
    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}

resource "aws_cloudfront_vpc_origin" "alb_2" {
  vpc_origin_endpoint_config {
    name                   = "alb-2-origin"
    arn                    = var.web_server_alb_2_arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"
    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}


# ** the kinesis stream for the log config
resource "aws_kinesis_stream" "cloudfront" {
  # TODO: kms + permissions
  name             = "cloudfront"
  shard_count      = 1
  retention_period = 48

  shard_level_metrics = [
    "IncomingBytes",
    "OutgoingBytes",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  encryption_type = "KMS"
  kms_key_id      = var.adminaccount_web_key_id
}

# ** the realtime log config
data "aws_iam_policy_document" "cloudfront_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cloudfront" {
  name               = "cloudfront"
  assume_role_policy = data.aws_iam_policy_document.cloudfront_assume_role.json
}

data "aws_iam_policy_document" "cloudfront" {
  statement {
    effect = "Allow"

    actions = [
      "kinesis:DescribeStreamSummary",
      "kinesis:DescribeStream",
      "kinesis:PutRecord",
      "kinesis:PutRecords",
    ]

    resources = [aws_kinesis_stream.cloudfront.arn]
  }
}

resource "aws_iam_role_policy" "cloudfront" {
  name   = "cloudfront"
  role   = aws_iam_role.cloudfront.id
  policy = data.aws_iam_policy_document.cloudfront.json
}

resource "aws_cloudfront_realtime_log_config" "cloudfront" {
  name          = "cloudfront"
  sampling_rate = 75
  fields        = ["timestamp", "c-ip"]

  endpoint {
    stream_type = "Kinesis"

    kinesis_stream_config {
      role_arn   = aws_iam_role.cloudfront.arn
      stream_arn = aws_kinesis_stream.cloudfront.arn
    }
  }

  depends_on = [
    aws_iam_role_policy.cloudfront,
    aws_kinesis_stream.cloudfront
  ]
}

# ** the distribution declaration
resource "aws_cloudfront_distribution" "cloudfront" {

  # first origin
  origin {
    domain_name = var.web_server_alb_dns_name
    vpc_origin_config {
      vpc_origin_id       = aws_cloudfront_vpc_origin.alb.id
      origin_read_timeout = 5 # wait 5 seconds for response
    }
    origin_id = "web-server-origin"
    # Add secret header to all requests to ALB
    custom_header {
      name  = "X-Custom-Secret"
      value = var.web_server_cloudfront_secret_value
    }

    # shield
    origin_shield {
      enabled              = true
      origin_shield_region = "us-east-1" # not available in eu-north-1
    }
  }

  # second origin
  origin {
    domain_name = var.web_server_alb_2_dns_name
    vpc_origin_config {
      vpc_origin_id       = aws_cloudfront_vpc_origin.alb_2.id
      origin_read_timeout = 5 # wait 5 seconds for response
    }
    origin_id = "web-server-2-origin"
    # Add secret header to all requests to ALB
    custom_header {
      name  = "X-Custom-Secret"
      value = var.web_server_cloudfront_secret_value
    }

    # shield
    origin_shield {
      enabled              = true
      origin_shield_region = "us-east-1" # not available in eu-north-1
    }
  }

  origin_group {
    origin_id = "cloudfront-web-servers-origin-group"

    failover_criteria {
      status_codes = [403, 404, 500, 502]
    }

    member {
      origin_id = "web-server-origin"
    }

    member {
      origin_id = "web-server-2-origin"
    }
  }
  custom_error_response {
    error_code         = "504"
    response_code      = "504"
    response_page_path = "/custom_504.html"
  }

  enabled             = true
  is_ipv6_enabled     = false
  comment             = "CloudFront distribution with ALB"
  default_root_object = "index.html" # Modify as needed

  default_cache_behavior {

    # Use managed policy that forwards ALL headers (including Host)
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3" # AllViewer

    target_origin_id        = "cloudfront-web-servers-origin-group"
    viewer_protocol_policy  = "redirect-to-https" # Change based on your needs
    allowed_methods         = ["GET", "HEAD", "OPTIONS"]
    cached_methods          = ["GET", "HEAD"]
    compress                = true  # compress Accept-Encoding: gzip
    default_ttl             = 86400 # 1-day TTL
    min_ttl                 = 0
    max_ttl                 = 31536000 # 1-year TTL
    realtime_log_config_arn = aws_cloudfront_realtime_log_config.cloudfront.arn
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    # serving same domain as the alb so using the same cert as the alb
    acm_certificate_arn      = var.aws_playing_cloud_xyz_certificate_arn
    ssl_support_method       = "sni-only"
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

  web_acl_id = aws_wafv2_web_acl.cloudfront_no_log4j.arn
}

# headers setting

#checkov:skip=CKV2_AWS_32:CloudFront distribution has response headers policy
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
      frame_option = "DENY" # don't allow this site to render inside an iframe
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
