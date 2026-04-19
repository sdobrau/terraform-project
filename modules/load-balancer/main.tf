# * elb, certificate, target group, attachment and autoscaling group

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

# an elb configured with a listener fwds traffic to a target group
# the target group is registered to with an autoscaling group via an attachment
#
# vpc_zone_identifier in asg identifies where the asg can launch instances
# vpc_id in target_group places the target group itself in a vpc

# ** the dns zone
# *** the cloudwatch log group and relevants for dns query logging
resource "aws_cloudwatch_log_group" "web_server_alb_dns_query_logging" { # OK
  name                        = "/aws/route53/${aws_route53_zone.playing_cloud.name}"
  retention_in_days           = 365
  log_group_class             = "STANDARD"
  deletion_protection_enabled = true
  kms_key_id                  = var.adminaccount_web_key_arn
}

# allow r53 to push to cloudwatch logs /aws/route53 log group

data "aws_iam_policy_document" "web_server_alb_dns_query_logging" { # OK
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["arn:aws:logs:*:*:log-group:/aws/route53/*"]

    # ignore AVD_AWS_0057: ok because by route53 service principal
    principals {
      identifiers = ["route53.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "web_server_alb_dns_query_logging" { # OK

  policy_document = data.aws_iam_policy_document.web_server_alb_dns_query_logging.json
  policy_name     = "web_server_alb_dns_query_logging" #
}

# *** the query logging setting for the zone

# NOTE: place zone before query log for the aws_route_query_log to work
# or depends_on
resource "aws_route53_zone" "playing_cloud" { # NOTOK
  name = var.domain_name
}

# for zone_id log the queries in a cloudwatch log group
resource "aws_route53_query_log" "web_server_alb_dns_query_logging" { # OK
  # depends_on = [aws_cloudwatch_log_resource_policy.web_server_alb_dns_query_logging]

  cloudwatch_log_group_arn = aws_cloudwatch_log_group.web_server_alb_dns_query_logging.arn
  zone_id                  = aws_route53_zone.playing_cloud.zone_id

}

# ** the load balancer
# *** the load balancer: main
# Create a new load balancer
resource "aws_alb" "web_server" { # OK
  name = "web-server"

  timeouts {
    create = "10m"
    delete = "10m"
    update = "10m"
  }

  # Check: CKV_AWS_150

  internal                   = true  # internal, skip AVD-AWS-0053
  drop_invalid_header_fields = true  # drop HTTP headers
  enable_deletion_protection = false # Check: CKV_AWS_150
  security_groups            = [aws_security_group.https_ingress_only_from_cloudfront_egress_cloudfront.id]
  subnets = [
    var.web_server_alb_private_subnet_1_id,
    var.web_server_alb_private_subnet_2_id]

  # TOFIX
  access_logs {
    bucket  = var.log_bucket_id
    prefix  = "alb_access_logs"
    enabled = true
  }

  connection_logs {
    bucket  = var.log_bucket_id
    prefix  = "alb_connection_logs"
    enabled = true
  }

  health_check_logs {
    bucket  = var.log_bucket_id
    enabled = true
    prefix  = "alb_health_check_logs"
  }
}

resource "aws_lb_listener_rule" "web_server_alb_secret_header_only" { # OK
  listener_arn = aws_alb_listener.web_server.arn
  priority     = 1

  action {
    type             = "forward" # fwd if secret header found
    target_group_arn = aws_alb_target_group.web_server.arn
  }

  condition {
    http_header {
      http_header_name = "X-Custom-Secret" # if secretheader provided
      values           = [var.secret_header_value]
    }
  }
}

# *** the listener
resource "aws_alb_listener" "web_server" { # OK
  load_balancer_arn                    = aws_alb.web_server.arn
  port                                 = "80"
  protocol                             = "HTTP"
  routing_http_response_server_enabled = false # no aws/elb2.0 Server

  default_action {
    type = "fixed-response" # if no secretvalue provided
    fixed_response {
      content_type = "text/plain"
      message_body = "Secret value not provided"
      status_code  = "403"
    }
  }

}

# *** the autoscaling group

# autoscaling group of max 3, min 2
#
# https://registry.terraform.io/providers/-/aws/5.0.0/docs/resources/autoscaling_group#instance_refresh-1
# https://docs.aws.amazon.com/autoscaling/ec2/userguide/instance-refresh-overview.html

resource "aws_autoscaling_group" "web_server" { # OK
  # hard dependency on kms key
  name                      = "web_server_asg"
  max_size                  = 3
  min_size                  = 0
  health_check_grace_period = 5
  health_check_type         = "ELB"
  default_cooldown          = 20
  desired_capacity          = 0
  wait_for_capacity_timeout = 0 # think
  force_delete              = false
  placement_group           = aws_placement_group.web_server_asg_spread_placement_group.id
  availability_zones        = ["us-east-1a"]

  launch_template {
    id      = aws_launch_template.web_server.id
    version = "$Latest"
  }

  # where to launch instances?
  # see vpc/main.tf

  tag {
    key                 = "component"
    value               = "web"
    propagate_at_launch = true
  }

  # instance refresh.
  # do it when template changes, and rollback if the instance fails
  instance_refresh {
    strategy = "Rolling" # roll out
    preferences {
      min_healthy_percentage = 100  # how many must remain healthy?
      auto_rollback          = true # if fail, then roll back
    }
  }
}

# *** the ebs DLM lifecycle policy

data "aws_iam_policy_document" "web_server_dlm_lifecycle_assume_role" { # OK
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "web_server_dlm_lifecycle" { # OK
  name               = "web_server_dlm_lifecycle"
  assume_role_policy = data.aws_iam_policy_document.web_server_dlm_lifecycle_assume_role.json
}

data "aws_iam_policy_document" "web_server_dlm_lifecycle" { # OK
  statement {
    effect = "Allow"

    actions = [
      "ec2:CreateSnapshot",
      "ec2:CreateSnapshots",
      "ec2:DeleteSnapshot",
      # ignore AVD_AWS_0057: ok because by dlm
      "ec2:DescribeInstances",
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
    ]

    #checkov:skip=CKV_AWS_111:Permissive permissions are for DLM function
    #checkov:skip=CKV_AWS_356:Permissive permissions are for DLM function
    resources = ["*"]
  }

  statement {
    effect  = "Allow"
    actions = ["ec2:CreateTags"]
    # ignore AVD_AWS_0057: ok because by dlm
    resources = ["arn:aws:ec2:*::snapshot/*"]
  }
}

resource "aws_iam_role_policy" "web_server_dlm_lifecycle" { # OK
  name   = "web_server_dlm_lifecycle"
  role   = aws_iam_role.web_server_dlm_lifecycle.id
  policy = data.aws_iam_policy_document.web_server_dlm_lifecycle.json
}

resource "aws_dlm_lifecycle_policy" "web_server" { # OK
  description        = "Web server DLM lifecycle policy"
  execution_role_arn = aws_iam_role.web_server_dlm_lifecycle.arn
  state              = "ENABLED"

  policy_details {
    policy_type    = "EBS_SNAPSHOT_MANAGEMENT"
    resource_types = ["VOLUME"]

    schedule {
      name = "1 week of daily snapshots"
      create_rule {
        interval      = 24 # each 24 hours
        interval_unit = "HOURS"
        times         = ["23:45"] # at 23:45
      }

      retain_rule {
        count = 7 # retain only last 7 copies
      }

      tags_to_add = {
        SnapshotCreator = "Web server DLM"
      }

      copy_tags = false
    }

    target_tags = {
      Snapshot = "true" # see tag_specifications in launch_template
    }
  }
}

# *** the autoscaling schedule to scale to 0 at 2AM, spin up at 6AM

resource "aws_autoscaling_schedule" "web_server_spin_down" { # OK
  scheduled_action_name  = "web_server_spin_down"
  max_size               = 0
  desired_capacity       = 0
  recurrence             = "0 2 * * *" # at 2AM
  autoscaling_group_name = aws_autoscaling_group.web_server.name
}

resource "aws_autoscaling_schedule" "web_server_spin_up" { # OK
  scheduled_action_name  = "web_server_spin_up"
  max_size               = 3
  min_size               = 1
  desired_capacity       = 1
  recurrence             = "59 1 * * *" # at 1:59AM
  autoscaling_group_name = aws_autoscaling_group.web_server.name
}

# *** the autoscaling attachment

resource "aws_autoscaling_attachment" "web_server" { # OK
  autoscaling_group_name = aws_autoscaling_group.web_server.name
  lb_target_group_arn    = aws_alb_target_group.web_server.arn
}

# *** the target group

resource "aws_alb_target_group" "web_server" { # OK
  name        = "web-server"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.web_server_vpc_id # where to create the target group?

  health_check {
    path                = "/index.html"
    interval            = 30
    timeout             = 5
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2 # if 2 for 30
  }
}

# one main vp
# spread placement group: across diff hardware to minimize spread of failure

# *** the placement group and launch template

resource "aws_placement_group" "web_server_asg_spread_placement_group" { # OK
  name     = "web_server_asg_spread_placement_group"
  strategy = "spread"
}

# *** the ingress/egress for the load balancer

resource "aws_security_group" "https_ingress_only_from_cloudfront_egress_cloudfront" { # OK
  name        = "https_ingress_only_from_cloudfront_egress_cloudfront"
  description = "Allow only from cloudfront and egress all"
  vpc_id      = var.web_server_vpc_id
  # lifecycle {
  #   create_before_destroy = true
  # }
}

resource "aws_vpc_security_group_ingress_rule" "https_ingress_only_from_cloudfront" { # OK
  security_group_id = aws_security_group.https_ingress_only_from_cloudfront_egress_cloudfront.id
  description       = "Allow HTTPS only from cloudfront egress all"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  # need to allow this for cloudfront + vpc origin to work
  # CloudFront-VPCOrigins-Service-SG
  referenced_security_group_id = "sg-0e14ff6d4b867e5fc"
  # prefix_list_id    = "pl-3b927c52"
}

resource "aws_vpc_security_group_egress_rule" "egress_all" { # OK
  security_group_id            = aws_security_group.https_ingress_only_from_cloudfront_egress_cloudfront.id
  description                  = "Allow egress to cloudfront"
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = "sg-0e14ff6d4b867e5fc"
  cidr_ipv4                    = "0.0.0.0/0"
  # AVD-AWS-0104: ignore
}

# *** the ingress/egress for the private instances

resource "aws_security_group" "https_ingress_only_from_private_subnets_egress_all" { # OK
  name        = "https_ingress_only_from_private_subnets_egress_all"
  description = "Allow only HTTPS ingress from private subnets egress all"
  vpc_id      = var.web_server_vpc_id
  # lifecycle {
  #   create_before_destroy = true
  # }
}

resource "aws_vpc_security_group_ingress_rule" "https_ingress_only_from_private_subnet_1" { # OK
  security_group_id = aws_security_group.https_ingress_only_from_private_subnets_egress_all.id
  description       = "Allow HTTPS only from private subnet 1"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.0.0/24"

}

resource "aws_vpc_security_group_ingress_rule" "https_ingress_only_from_private_subnet_2" { # OK
  security_group_id = aws_security_group.https_ingress_only_from_private_subnets_egress_all.id
  description       = "Allow HTTPS only from private subnet 2"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.1.0/24"
}

# NOTE: this is required for ssm to work
resource "aws_vpc_security_group_egress_rule" "egress_all_2" { # OK
  security_group_id = aws_security_group.https_ingress_only_from_private_subnets_egress_all.id
  description       = "Allow egress all"
  ip_protocol       = "-1"
  # ignore AVD-AWS-0104: we need this for fetching packages
  cidr_ipv4 = "0.0.0.0/0"
}

# *** the launch template for autoscaling group

resource "aws_launch_template" "web_server" { # OK
  name = "web_server"

  block_device_mappings {
    device_name = "/dev/sdf"

    ebs {
      volume_size = 20
      encrypted   = true
      kms_key_id  = var.adminaccount_web_key_id

    }
  }
  cpu_options {
    core_count       = 1
    threads_per_core = 1
  }

  iam_instance_profile {
    name = "web_server"
  }
  # retrieve most recent amazon linux image

  image_id      = var.ami_id
  instance_type = "t3.micro"

  #IMDS options
  metadata_options {
    http_endpoint               = "enabled"  # ok
    http_tokens                 = "required" # require token for auth
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled" # access to instance tags
  }

  monitoring {
    enabled = true # enabled _detailed monitoring_
  }

  network_interfaces {
    associate_public_ip_address = false # private hosts
    subnet_id                   = var.web_server_instances_private_subnet_id
    security_groups             = [aws_security_group.https_ingress_only_from_private_subnets_egress_all.id]
  }

  placement {
    group_name = "web_server_asg_spread_placement_group"
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Snapshot = "true" # do snapshot
    }
  }

  user_data = filebase64("${path.module}/files/boot-server.sh")
}

# *** scaling policy for the auto-scaling group

resource "aws_autoscaling_policy" "web_server_scale_down" { # OK
  name                   = "web_server_scale_down"
  autoscaling_group_name = aws_autoscaling_group.web_server.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1  # scale down
  cooldown               = 120 # with a cooldown of 120
}


resource "aws_autoscaling_policy" "web_server_scale_up" { # OK
  name                   = "web_server_scale_up"
  autoscaling_group_name = aws_autoscaling_group.web_server.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1  # scale down
  cooldown               = 120 # with a cooldown of 120
}


resource "aws_cloudwatch_metric_alarm" "web_server_scale_down" { # OK
  alarm_description   = "Monitors CPU utilization for Terramino ASG"
  alarm_actions       = [aws_autoscaling_policy.web_server_scale_down.arn]
  alarm_name          = "web_server_scale_down"
  comparison_operator = "LessThanOrEqualToThreshold" # less than
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  threshold           = "10"  # 10
  evaluation_periods  = "2"   # two times under 10%
  period              = "120" # for two minutes
  statistic           = "Average"

  # when any host in this asg
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_server.name
  }
}

resource "aws_cloudwatch_metric_alarm" "web_server_scale_up" { # OK
  alarm_description   = "Monitors CPU utilization for Terramino ASG"
  alarm_actions       = [aws_autoscaling_policy.web_server_scale_up.arn]
  alarm_name          = "web_server_scale_up"
  comparison_operator = "GreaterThanOrEqualToThreshold" # less than
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  threshold           = "80" # 80
  evaluation_periods  = "2"  # two times
  period              = "10" # for 15 seconds
  statistic           = "Average"

  # when any host in this asg
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_server.name
  }
}

# *** security for elastic load balancer

# **** web acl

# ***** the necessary buckets and bucket configs for the web acl

resource "aws_s3_bucket_lifecycle_configuration" "aws-waf-logs-web_server_source" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-web_server_source.bucket

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

resource "aws_s3_bucket_lifecycle_configuration" "aws-waf-logs-web_server_destination" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-web_server_destination.bucket

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
resource "aws_s3_bucket_public_access_block" "aws-waf-logs-web_server_source" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-web_server_source.id

  block_public_acls       = true # block any acls that would make it public
  block_public_policy     = true # block any policies that would make it public
  ignore_public_acls      = true # ignore current public policies
  restrict_public_buckets = true # only aws services and owner can access if pub
}

resource "aws_s3_bucket_public_access_block" "aws-waf-logs-web_server_destination" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-web_server_destination.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# *** the bucket versionings
resource "aws_s3_bucket_versioning" "aws-waf-logs-web_server_source" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-web_server_source.id
  # mfa    = "serialnumber authvalue"
  versioning_configuration {
    status = "Enabled"
    # mfa_delete = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "aws-waf-logs-web_server_destination" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-web_server_destination.id
  # mfa    = "serialnumber authvalue"
  versioning_configuration {
    status = "Enabled"
    # mfa_delete = "Enabled"
  }
}

# *** the access logging in same bucket
# **** the access logging settings themselves
resource "aws_s3_bucket_logging" "aws-waf-logs-web_server_source" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-web_server_source.bucket

  target_bucket = var.log_bucket_bucket
  target_prefix = "bucket-logging-log/"
  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

resource "aws_s3_bucket_logging" "aws-waf-logs-web_server_destination" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-web_server_destination.bucket

  target_bucket = var.log_bucket_bucket
  target_prefix = "bucket-logging-log/"
  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

# *** the sse-cs
resource "aws_s3_bucket_server_side_encryption_configuration" "aws-waf-logs-web_server_source" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-web_server_source.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.adminaccount_web_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "aws-waf-logs-web_server_destination" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-web_server_destination.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.adminaccount_web_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# *** the policies for replication
data "aws_iam_policy_document" "aws-waf-logs-web_server_replication_assume_role" { # OK
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "aws-waf-logs-web_server_replication" { # OK
  name               = "aws-waf-logs-web_server_replication"
  assume_role_policy = data.aws_iam_policy_document.aws-waf-logs-web_server_replication_assume_role.json
}

data "aws_iam_policy_document" "aws-waf-logs-web_server_replication_listing" { # OK
  statement {
    effect = "Allow"

    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]

    resources = [aws_s3_bucket.aws-waf-logs-web_server_source.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]

    resources = ["${aws_s3_bucket.aws-waf-logs-web_server_source.arn}/*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]

    resources = ["${aws_s3_bucket.aws-waf-logs-web_server_destination.arn}/*"]
  }
}

resource "aws_iam_policy" "aws-waf-logs-web_server_replication" { # OK
  name   = "aws-waf-web_server_replication"
  policy = data.aws_iam_policy_document.aws-waf-logs-web_server_replication_listing.json
}

resource "aws_iam_role_policy_attachment" "aws-waf-logs-web_server_replication" { # OK
  role       = aws_iam_role.aws-waf-logs-web_server_replication.name
  policy_arn = aws_iam_policy.aws-waf-logs-web_server_replication.arn
}

# *** the actual bucket replication configuration
resource "aws_s3_bucket_replication_configuration" "aws-waf-logs-web_server_replication" { # OK

  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.aws-waf-logs-web_server_source]

  role   = aws_iam_role.aws-waf-logs-web_server_replication.arn
  bucket = aws_s3_bucket.aws-waf-logs-web_server_source.id

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
      bucket        = aws_s3_bucket.aws-waf-logs-web_server_destination.arn
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

# ** the buckets itself and policy

resource "aws_s3_bucket" "aws-waf-logs-web_server_source" { # OK
  bucket        = "aws-waf-logs-web-server-source-1"
  force_destroy = true
}

resource "aws_s3_bucket" "aws-waf-logs-web_server_destination" { # OK
  bucket        = "aws-waf-logs-web-server-destination-1"
  force_destroy = true
}

# *** the policy document as recommended by AWS

data "aws_iam_policy_document" "aws-waf-logs-web_server_source" { # OK
  statement {
    sid       = "AWSLogDeliveryWrite"
    effect    = "Allow"
    resources = ["${aws_s3_bucket.aws-waf-logs-web_server_source.arn}/*"]
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
    resources = [aws_s3_bucket.aws-waf-logs-web_server_source.arn]
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
    resources = ["${aws_s3_bucket.aws-waf-logs-web_server_source.arn}/bucket-logging-log/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }
  }
}

data "aws_iam_policy_document" "aws-waf-logs-web_server_destination" { # OK
  statement {
    sid       = "AWSLogDeliveryWrite"
    effect    = "Allow"
    resources = ["${aws_s3_bucket.aws-waf-logs-web_server_destination.arn}/*"]
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
    resources = [aws_s3_bucket.aws-waf-logs-web_server_destination.arn]
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
    resources = ["${aws_s3_bucket.aws-waf-logs-web_server_destination.arn}/bucket-logging-log/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_source_account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "aws-waf-logs-web_server_source" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-web_server_source.bucket
  policy = data.aws_iam_policy_document.aws-waf-logs-web_server_source.json
}

resource "aws_s3_bucket_policy" "aws-waf-logs-web_server_destination" { # OK
  bucket = aws_s3_bucket.aws-waf-logs-web_server_destination.bucket
  policy = data.aws_iam_policy_document.aws-waf-logs-web_server_destination.json
}
