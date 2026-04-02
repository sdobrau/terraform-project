# * elb, certificate, target group, attachment and autoscaling group

# an elb configured with a listener fwds traffic to a target group
# the target group is registered to with an autoscaling group via an attachment
#
# vpc_zone_identifier in asg identifies where the asg can launch instances
# vpc_id in target_group places the target group itself in a vpc

# ** the key-pair to put inside the web servers

data "aws_key_pair" "sdobrau_web_ssh" {
  key_name           = "sdobrau_web_ssh"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFHK6zCZfK28nTMSA47TztuAqQvuItwAQUQGfovc0qLy sdobrau@tux"
}

# ** the certificate for the listener

resource "aws_acm_certificate" "web_server_elb" {
  domain_name       = "playing-cloud.com"
  validation_method = "DNS"

  tags = {
    Environment = "test"
  }

  lifecycle {
    create_before_destroy = true
  }
}


# ** TODO: create r53 reverse lookup zone for validating public ip range

resource "aws_route53_zone" "playing_cloud" {
  name = "playing-cloud.com"
}

# ** TODO: create r53 TXT record in the zone with the verification token

resource "aws_route53_record" "txt" {
  zone_id = aws_route53_zone.playing_cloud.zone_id
  name    = "<<VERIFICATION_TOKEN_NAME>>.113.0.203.in-addr.arpa" #
  type    = "TXT"
  ttl     = 300
  records = "<<VERIFICATION_TOKEN_VALUE>>"
}

# ** TODO the records for the certificate validation

resource "aws_route53_record" "txt" {
  zone_id = aws_route53_zone.playing_cloud.zone_id
  name    = "<<VERIFICATION_TOKEN_NAME>>.113.0.203.in-addr.arpa" #
  type    = "TXT"
  ttl     = 300
  records = "<<VERIFICATION_TOKEN_VALUE>>"
}

# ** TODO the load balancer # TODO eip for load balancer

# *** the load balancer

# Create a new load balancer
resource "aws_elb" "web_server" {
  name               = "web_server"
  availability_zones = ["use1-az1", "use1-az2", "use1-az3"]

  access_logs {
    bucket        = "web_server_logs"
    bucket_prefix = "access_logs"
    interval      = 60
  }

  # TODO:
  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:iam::${data.aws_caller_identity.source.account_id}:server-certificate/web_server_elb"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:443/"
    interval            = 30
  }

  instances                   = [aws_instance.foo.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "foobar-terraform-elb"
  }
}

# *** the autoscaling group

# autoscaling group of max 3, min 2
resource "aws_autoscaling_group" "web_server" {
  name                      = "web_server_asg"
  max_size                  = 3
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 3
  force_delete              = true
  placement_group           = aws_placement_group.web_server_asg_spread_placement_group.id
  launch_configuration      = aws_launch_configuration.foobar.name
  # where to launch instances?
  vpc_zone_identifier       = [aws_subnet.web_server.id] # 10.0.1.0/24"

  tag {
    component                 = "web"
  }
}

# *** the autoscaling attachment

resource "aws_autoscaling_attachment" "web_server" {
  autoscaling_group_id = aws_autoscaling_group.web_server
  target_group_arn     = aws_lb_target_group.web_server
}

# *** the target group

resource "aws_lb_target_group" "web_server" {
  name     = "app-target-group"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = "web_server"  # Replace with your VPC ID

  health_check {
    path                = "/index.html"
    interval            = 30
    timeout             = 5
    healthy_threshold  = 2
    unhealthy_threshold = 2
  }
}

# one main vp
# spread placement group: across diff hardware to minimize spread of failure

# *** the placement group and launch template

resource "aws_placement_group" "web_server_asg_spread_placement_group" {
  name = "web-server-asg-spread-placement-group"
  strategy = "spread"
}

# launch template for autoscaling group

resource "aws_launch_template" "web_server_ubuntu" {
  name = "web_server_ubuntu"

  subnet_id = "web_server"
  block_device_mappings {
    device_name = "/dev/sdf"

    ebs {
      # TODO: snapshotting
      volume_size = 20
      kms_key_id = "sdobrau_web"

    }
  }

  cpu_options {
    core_count       = 1
    threads_per_core = 1
  }

  iam_instance_profile {
    name = "web_server"
  }

  # ubuntu Questing Quokka
  image_id = "ami-02633e712f6dcb86f"
  instance_type = "t2.micro"

  key_name = [data.aws_key_pair.sdobrau_web_ssh.key_name]

  monitoring {
    enabled = true
  }

  network_interfaces {
    associate_public_ip_address = false
  }

  placement {
    availability_zone = "us-east-1a"
    group_name = "web_server_asg_spread_placement_group"
  }

  vpc_security_group_ids = ["https_ingress_only"]

  tag_specifications {
    resource_type = "instance"
    tags = {
      component = "web"
    }
  }

  user_data = filebase64("${path.module}/files/boot-server.sh")
}

# *** security for elastic load balancer

# **** web acl

# ***** the web acl as container of rule groups
# Web ACL must use lifecycle.ignore_changes to prevent drift from this resource
resource "aws_wafv2_web_acl" "web_server_elb_allow_me_only" {
  name  = ""
  scope = "GLOBAL"

  default_action {
    block {} # unless anything matched, block
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "example-web-acl"
    sampled_requests_enabled   = true
  }

  lifecycle {
    ignore_changes = [rule]
  }
}

# ***** the rule group and ipset containing rules
resource "aws_wafv2_ip_set" "me" {
  name               = "me"
  scope              = "GLOBAL"
  ip_address_version = "IPV4"
  addresses          = ["86.14.10.231/32"]
}

resource "aws_wafv2_rule_group" "web_server_elb_allow_me_only" {
  name        = "web_server_elb_allow_me_only"
  description = "Allow only the ipset allowing me"
  scope       = "GLOBAL"
  capacity    = 500

  rule {
    name     = "rule-1"
    priority = 1

    action {
      allow {} # allow if
    }
    ip_set_reference_statement {
      arn = aws_wafv2_ip_set.me.arn
    }
  }
  depends_on = [aws_wafv2_ip_set.me]
}

# ***** the rule group association
resource "aws_wafv2_web_acl_rule_group_association" "web_server_elb_allow_me_only" {
  rule_name   = "web_server_elb_allow_me_only"
  priority    = 100
  web_acl_arn = aws_wafv2_web_acl.web_server_elb_allow_me_only.arn

  rule_group_reference {
    arn = aws_wafv2_rule_group.web_server_elb_allow_me_only.arn
  }
}

# **** the association with the load balancer

resource "aws_wafv2_web_acl_association" "example" {
  resource_arn = aws_elb.web_server.arn
  web_acl_arn  = aws_wafv2_web_acl.web_server_elb_allow_me_only.arn
}
