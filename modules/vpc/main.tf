data "aws_region" "current" {}

# * the gateway, public vpc with subnet

# ** vpc for the elb
resource "aws_vpc" "web_server" { # OK
  cidr_block           = "10.0.0.0/16"
  instance_tenancy     = "default"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "web_server_alb_public"
  }
}

# ** the default security group disallowing all inbound allow all outbound

# sg-08ceb13e3022ef0c9
resource "aws_default_security_group" "default" { # OK?
  vpc_id = aws_vpc.web_server.id

  # default by aws, allow all ingress and egress
  ingress {
    protocol = "-1"
    # self        = true
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ** flow log: cloudwatch log group for flow logs

resource "aws_cloudwatch_log_group" "vpc_flow_log" { # OK
  name                        = "vpc_flow_log"
  retention_in_days           = 365
  log_group_class             = "STANDARD"
  deletion_protection_enabled = true
  kms_key_id                  = var.adminaccount_web_key_arn
}

# ** flow log: permissions

data "aws_iam_policy_document" "vpc_flow_log_assume_role" { # OK
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "vpc_flow_log" { # OK
  name               = "example"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_log_assume_role.json
}

data "aws_iam_policy_document" "vpc_flow_log" { # OK
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]

    resources = ["*"] # CKV_AWS_356 false alarm
  }
}

resource "aws_iam_role_policy" "vpc_flow_log" { # OK
  name   = "example"
  role   = aws_iam_role.vpc_flow_log.id
  policy = data.aws_iam_policy_document.vpc_flow_log.json
}

# ** flow log: flow log settings

resource "aws_flow_log" "web_server" { # OK
  iam_role_arn         = aws_iam_role.vpc_flow_log.arn
  log_destination      = aws_cloudwatch_log_group.vpc_flow_log.arn
  log_destination_type = "cloud-watch-logs"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.web_server.id
}

# ** the private subnets for the elb
resource "aws_subnet" "web_server_alb_private_1" { # OK
  vpc_id                  = aws_vpc.web_server.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false # instances in this subnet get an ip

  tags = {
    Name = "web_server_alb_private_1"
  }
}

resource "aws_subnet" "web_server_alb_private_2" { # OK
  vpc_id                  = aws_vpc.web_server.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false # instances in this subnet get an ip

  tags = {
    Name = "web_server_alb_private_2"
  }
}

# ** the public subnet for the nat gateway + internet gateway

resource "aws_subnet" "web_server_public" { # OK
  vpc_id                  = aws_vpc.web_server.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true # instances in this subnet get an ip

  tags = {
    Name = "web_server_public"
  }
}

# ** the internet gateway for the elb
resource "aws_internet_gateway" "web_server_public" { # OK
  vpc_id = aws_vpc.web_server.id
  tags = {
    Name = "web_server"
  }
}

# ** the routing table and association to the public subnet
resource "aws_route_table" "web_server_public" { # OK
  vpc_id = aws_vpc.web_server.id
  tags = {
    Name = "web_server"
  }
}

# ** the route
resource "aws_route" "web_server_all_internet" { # OK
  route_table_id         = aws_route_table.web_server_public.id
  destination_cidr_block = "0.0.0.0/0" # Any destination
  gateway_id             = aws_internet_gateway.web_server_public.id
}

# ** associate to one public subnet
resource "aws_route_table_association" "web_server" { # OK
  subnet_id      = aws_subnet.web_server_public.id
  route_table_id = aws_route_table.web_server_public.id
}

# ** private subnet for the asg
resource "aws_subnet" "web_server_instances_private" { # OK
  vpc_id     = aws_vpc.web_server.id
  cidr_block = "10.0.2.0/24"

  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "web_server_instances_private"
  }
}

# ** network acl for private subnets

resource "aws_network_acl" "web_server_allow_in_out_all" { # OK
  vpc_id = aws_vpc.web_server.id

  subnet_ids = [aws_subnet.web_server_instances_private.id]

  # ingress { # ftp
  #   protocol   = "tcp"
  #   rule_no    = 1
  #   action     = "allow"
  #   cidr_block = "10.0.0.0/24"
  #   from_port  = 443
  #   to_port    = 443
  # }

  # ingress { # ftp
  #   protocol   = "tcp"
  #   rule_no    = 2
  #   action     = "allow"
  #   cidr_block = "10.0.1.0/24"
  #   from_port  = 443
  #   to_port    = 443
  # }

  # TOFIX: strengthen
  egress {
    rule_no    = 3
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    action     = "allow"
    to_port    = 0
    from_port  = 0
  }

  ingress {
    rule_no    = 4
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    action     = "allow"
    to_port    = 0
    from_port  = 0
  }

  tags = {
    Name = "main"
  }
}


# ** vpc interface endpoint configuration for SSM, so private instances can conn
# as in
# https://heywoodonline.com/posts/Using%20SSM%20with%20VPC%20Endpoints.html
# and https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html

# *** the interface endpoints
resource "aws_security_group" "allow_only_private_instances_ingress_egress_all" {
  name        = "allow_only_private_instances_ingress_egress_all"
  description = "Allow only private instances to access the interface endpoints"
  vpc_id      = aws_vpc.web_server.id
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_only_private_instances_ingress" {
  description       = "Allow ingress only from private subnet"
  security_group_id = aws_security_group.allow_only_private_instances_ingress_egress_all.id
  cidr_ipv4         = "10.0.2.0/24"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "allow_only_private_instances_egress_all" {
  description       = "Allow egress all for private instances"
  security_group_id = aws_security_group.allow_only_private_instances_ingress_egress_all.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# these service names will map to private AWS backbone when queried in that vpc

variable "ssm_endpoints" {
  description = "SSM endpoints to configure interface gateway for"
  type        = list(string)
  default = [
    "ssm",
    "ec2messages",
    "ec2",
    "ssmmessages",
    "logs"
  ]
}

resource "aws_vpc_endpoint" "for_ssm" { # OK
  count               = length(var.ssm_endpoints)
  vpc_id              = aws_vpc.web_server.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${var.ssm_endpoints[count.index]}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [aws_subnet.web_server_instances_private.id]
  # security_group_ids  = [aws_security_group.allow_only_private_instances_ingress_egress_all.id]
}

resource "aws_vpc_endpoint" "s3" { # OK
  vpc_id            = aws_vpc.web_server.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
}

# * nat gateway and route in private subnet to via nat gateway for 0.0.0.0/0

resource "aws_route_table" "web_server_instances_private" { # OK
  vpc_id = aws_vpc.web_server.id
  tags = {
    Name = "web_server_instances_private"
  }
}

resource "aws_route_table_association" "web_server_instances_private" { # OK
  subnet_id      = aws_subnet.web_server_instances_private.id
  route_table_id = aws_route_table.web_server_instances_private.id
}

resource "aws_route" "web_server_instances_private_0_to_nat_gateway" { # OK
  route_table_id         = aws_route_table.web_server_instances_private.id
  destination_cidr_block = "0.0.0.0/0" # Any destination
  nat_gateway_id         = aws_nat_gateway.for_web_server_private_subnet.id
}

# * private subnet and nat gateway config

#checkov:skip=CKV2_AWS_19:EIP is allocated to NAT gateway
resource "aws_eip" "for_nat_gateway" { # OK
  depends_on = [aws_internet_gateway.web_server_public]
}

resource "aws_nat_gateway" "for_web_server_private_subnet" { # OK
  allocation_id = aws_eip.for_nat_gateway.id
  subnet_id     = aws_subnet.web_server_public.id

  tags = {
    Name = "for_web_server_private_subnet"
  }
  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.web_server_public]
}
