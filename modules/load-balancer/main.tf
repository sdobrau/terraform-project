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
  security_groups            = [aws_security_group.http_ingress_only_from_cloudfront_egress_cloudfront.id]
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

# *** the load balancer 2
resource "aws_alb" "web_server_2" { # OK
  name = "web-server-2"

  timeouts {
    create = "10m"
    delete = "10m"
    update = "10m"
  }

  # Check: CKV_AWS_150

  internal                   = true  # internal, skip AVD-AWS-0053
  drop_invalid_header_fields = true  # drop HTTP headers
  enable_deletion_protection = false # Check: CKV_AWS_150
  security_groups            = [aws_security_group.http_ingress_only_from_cloudfront_egress_cloudfront.id]
  subnets = [
    var.web_server_alb_2_private_subnet_1_id,
    var.web_server_alb_2_private_subnet_2_id]
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

# *** the listener 2nd
resource "aws_alb_listener" "web_server_2" { # OK
  load_balancer_arn                    = aws_alb.web_server_2.arn
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

resource "aws_lb_listener_rule" "web_server_alb_2_secret_header_only" { # OK
  listener_arn = aws_alb_listener.web_server_2.arn
  priority     = 1

  action {
    type             = "forward" # fwd if secret header found
    target_group_arn = aws_alb_target_group.web_server_2.arn
  }

  condition {
    http_header {
      http_header_name = "X-Custom-Secret" # if secretheader provided
      values           = [var.secret_header_value]
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

# *** the autoscaling group 2nd
# autoscaling group of max 3, min 2
#
# https://registry.terraform.io/providers/-/aws/5.0.0/docs/resources/autoscaling_group#instance_refresh-1
# https://docs.aws.amazon.com/autoscaling/ec2/userguide/instance-refresh-overview.html

resource "aws_autoscaling_group" "web_server_2" { # OK
  # hard dependency on kms key
  name                      = "web_server_2_asg"
  max_size                  = 3
  min_size                  = 0
  health_check_grace_period = 5
  health_check_type         = "ELB"
  default_cooldown          = 20
  desired_capacity          = 0
  wait_for_capacity_timeout = 0 # think
  force_delete              = false
  placement_group           = aws_placement_group.web_server_asg_spread_placement_group.id
  availability_zones        = ["us-east-1b"]

  launch_template {
    id      = aws_launch_template.web_server_2.id
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

# *** the ebs DLM lifecycle policy 2

data "aws_iam_policy_document" "web_server_2_dlm_lifecycle_assume_role" { # OK
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "web_server_2_dlm_lifecycle" { # OK
  name               = "web_server_2_dlm_lifecycle"
  assume_role_policy = data.aws_iam_policy_document.web_server_2_dlm_lifecycle_assume_role.json
}

data "aws_iam_policy_document" "web_server_2_dlm_lifecycle" { # OK
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

resource "aws_iam_role_policy" "web_server_2_dlm_lifecycle" { # OK
  name   = "web_server_2_dlm_lifecycle"
  role   = aws_iam_role.web_server_2_dlm_lifecycle.id
  policy = data.aws_iam_policy_document.web_server_2_dlm_lifecycle.json
}

resource "aws_dlm_lifecycle_policy" "web_server_2" { # OK
  description        = "Web server DLM lifecycle policy"
  execution_role_arn = aws_iam_role.web_server_2_dlm_lifecycle.arn
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

# *** the autoscaling schedule to scale to 0 at 2AM, spin up at 6AM 2
resource "aws_autoscaling_schedule" "web_server_2_spin_down" { # OK
  scheduled_action_name  = "web_server_2_spin_down"
  max_size               = 0
  desired_capacity       = 0
  recurrence             = "0 2 * * *" # at 2AM
  autoscaling_group_name = aws_autoscaling_group.web_server_2.name
}

resource "aws_autoscaling_schedule" "web_server_2_spin_up" { # OK
  scheduled_action_name  = "web_server_2_spin_up"
  max_size               = 3
  min_size               = 1
  desired_capacity       = 1
  recurrence             = "59 1 * * *" # at 1:59AM
  autoscaling_group_name = aws_autoscaling_group.web_server_2.name
}

# *** the autoscaling attachment
resource "aws_autoscaling_attachment" "web_server" { # OK
  autoscaling_group_name = aws_autoscaling_group.web_server.name
  lb_target_group_arn    = aws_alb_target_group.web_server.arn
}

# *** the autoscaling attachment 2
resource "aws_autoscaling_attachment" "web_server_2" { # OK
  autoscaling_group_name = aws_autoscaling_group.web_server_2.name
  lb_target_group_arn    = aws_alb_target_group.web_server_2.arn
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

# *** the target group 2
resource "aws_alb_target_group" "web_server_2" { # OK
  name        = "web-server-2"
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

# *** the placement group and launch template
resource "aws_placement_group" "web_server_asg_spread_placement_group" { # OK
  name     = "web_server_asg_spread_placement_group"
  strategy = "spread"
}

# *** the ingress/egress for the load balancer
resource "aws_security_group" "http_ingress_only_from_cloudfront_egress_cloudfront" { # OK
  name        = "http_ingress_only_from_cloudfront_egress_cloudfront"
  description = "Allow only from cloudfront and egress all"
  vpc_id      = var.web_server_vpc_id
  # lifecycle {
  #   create_before_destroy = true
  # }
}

resource "aws_vpc_security_group_ingress_rule" "http_ingress_only_from_cloudfront" { # OK
  security_group_id = aws_security_group.http_ingress_only_from_cloudfront_egress_cloudfront.id
  description       = "Allow HTTPS only from cloudfront egress all"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  # need to allow this for cloudfront + vpc origin to work
  # CloudFront-VPCOrigins-Service-SG
  referenced_security_group_id = "sg-0e14ff6d4b867e5fc"
  # prefix_list_id    = "pl-3b927c52"
}

resource "aws_vpc_security_group_egress_rule" "egress_to_cloudfront" { # OK
  security_group_id            = aws_security_group.http_ingress_only_from_cloudfront_egress_cloudfront.id
  description                  = "Allow egress to cloudfront"
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = "sg-0e14ff6d4b867e5fc"
  # AVD-AWS-0104: ignore, fixed
}

# *** the ingress/egress for the private instances
resource "aws_security_group" "http_ingress_only_from_private_subnets_egress_all" { # OK
  name        = "http_ingress_only_from_private_subnets_egress_all"
  description = "Allow only HTTP ingress from private subnets egress all"
  vpc_id      = var.web_server_vpc_id
  # lifecycle {
  #   create_before_destroy = true
  # }
}

resource "aws_vpc_security_group_ingress_rule" "http_ingress_only_from_private_subnet_1" { # OK
  security_group_id = aws_security_group.http_ingress_only_from_private_subnets_egress_all.id
  description       = "Allow HTTP only from private subnet 1"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.0.0/24"

}

resource "aws_vpc_security_group_ingress_rule" "http_ingress_only_from_private_subnet_2" { # OK
  security_group_id = aws_security_group.http_ingress_only_from_private_subnets_egress_all.id
  description       = "Allow HTTP only from private subnet 2"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.1.0/24"
}

# NOTE: this is required for ssm to work
resource "aws_vpc_security_group_egress_rule" "egress_all" { # OK
  security_group_id = aws_security_group.http_ingress_only_from_private_subnets_egress_all.id
  description       = "Allow egress all"
  ip_protocol       = "-1"
  # ignore AVD-AWS-0104: we need this for fetching packages
  cidr_ipv4 = "0.0.0.0/0"
}

# *** the ingress/egress for the private instances 2
resource "aws_security_group" "http_ingress_only_from_private_subnets_2_egress_all" { # OK
  name        = "http_ingress_only_from_private_subnets_2_egress_all"
  description = "Allow only HTTP ingress from private subnets 2 egress all"
  vpc_id      = var.web_server_vpc_id
  # lifecycle {
  #   create_before_destroy = true
  # }
}

resource "aws_vpc_security_group_ingress_rule" "http_ingress_only_from_private_subnet_2_1" { # OK
  security_group_id = aws_security_group.http_ingress_only_from_private_subnets_2_egress_all.id
  description       = "Allow HTTP only from private subnet 1 of 2 "
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.4.0/24"

}

resource "aws_vpc_security_group_ingress_rule" "http_ingress_only_from_private_subnet_2_2" { # OK
  security_group_id = aws_security_group.http_ingress_only_from_private_subnets_2_egress_all.id
  description       = "Allow HTTP only from private subnet 2 of 2"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.5.0/24"
}

# NOTE: this is required for ssm to work
resource "aws_vpc_security_group_egress_rule" "egress_all_2" { # OK
  security_group_id = aws_security_group.http_ingress_only_from_private_subnets_2_egress_all.id
  description       = "Allow egress all"
  ip_protocol       = "-1"
  # ignore AVD-AWS-0104: we need this for fetching packages
  cidr_ipv4 = "0.0.0.0/0"
}

# *** the launch template for autoscaling group
resource "aws_launch_template" "web_server" { # OK
  name = "web-server"

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
    security_groups             = [aws_security_group.http_ingress_only_from_private_subnets_egress_all.id]
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

# *** the launch template for autoscaling group 2
resource "aws_launch_template" "web_server_2" { # OK
  name = "web-server-2"

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
    subnet_id                   = var.web_server_instances_private_subnet_2_id
    security_groups             = [aws_security_group.http_ingress_only_from_private_subnets_2_egress_all.id]
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
  name                   = "web-server-scale-down"
  autoscaling_group_name = aws_autoscaling_group.web_server.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1  # scale down
  cooldown               = 120 # with a cooldown of 120
}

resource "aws_autoscaling_policy" "web_server_scale_up" { # OK
  name                   = "web-server-scale-up"
  autoscaling_group_name = aws_autoscaling_group.web_server.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1   # scale up
  cooldown               = 120 # with a cooldown of 120
}

resource "aws_cloudwatch_metric_alarm" "web_server_scale_down" { # OK
  alarm_description   = "Monitors CPU utilization for web-server ASG"
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
  alarm_description   = "Monitors CPU utilization for web-server ASG"
  alarm_actions       = [aws_autoscaling_policy.web_server_scale_up.arn]
  alarm_name          = "web-server-scale-up"
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

# *** scaling policy for the auto-scaling group 2
resource "aws_autoscaling_policy" "web_server_2_scale_down" { # OK
  name                   = "web-server-2-scale-down"
  autoscaling_group_name = aws_autoscaling_group.web_server_2.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1  # scale down
  cooldown               = 120 # with a cooldown of 120
}


resource "aws_autoscaling_policy" "web_server_2_scale_up" { # OK
  name                   = "web-server-2-scale-up"
  autoscaling_group_name = aws_autoscaling_group.web_server_2.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1   # scale up
  cooldown               = 120 # with a cooldown of 120
}

resource "aws_cloudwatch_metric_alarm" "web_server_2_scale_down" { # OK
  alarm_description   = "Monitors CPU utilization for web-server-2 ASG"
  alarm_actions       = [aws_autoscaling_policy.web_server_2_scale_down.arn]
  alarm_name          = "web-server-2-scale-down"
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

resource "aws_cloudwatch_metric_alarm" "web_server_2_scale_up" { # OK
  alarm_description   = "Monitors CPU utilization for web-server-2 ASG"
  alarm_actions       = [aws_autoscaling_policy.web_server_scale_up.arn]
  alarm_name          = "web-server-scale-up"
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
