# * the gateway, public vpc with subnet

# ** vpc for the elb
resource "aws_vpc" "web_server" {
  cidr_block           = "10.0.0.0/16"
  instance_tenancy     = "default"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "web_server_alb_public"
  }
}

# ** the default security group disallowing all inbound allow all outbound

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.web_server.id
}

# ** the vpc flow logging for the vpc, and s3 subnets in an s3 bucket


# TODO: fix and rewrite with cloudwatch-logs

resource "aws_flow_log" "web_server" {
  log_destination      = var.flow_log_bucket_arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.web_server.id
}

# TODO fix and rewrite with cloudwatch logs
# https://registry.terraform.io/providers/-/aws/4.61.0/docs/resources/flow_log
# "LogDestination: web-server-logs-source is undeliverable"

# resource "aws_flow_log" "web_server_alb_public_1" {
#   log_destination      = var.flow_log_bucket_arn
#   log_destination_type = "s3"
#   traffic_type         = "ALL"
#   subnet_id            = aws_subnet.web_server_alb_public_1.id
# }

# resource "aws_flow_log" "web_server_alb_public_2" {
#   log_destination      = var.flow_log_bucket_arn
#   log_destination_type = "s3"
#   traffic_type         = "ALL"
#   subnet_id            = aws_subnet.web_server_alb_public_2.id
# }

# ** the public subnet for the elb
resource "aws_subnet" "web_server_alb_public_1" { # OK
  vpc_id                  = aws_vpc.web_server.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "eu-north-1b"
  map_public_ip_on_launch = true # instances in this subnet get an ip

  tags = {
    Name = "web_server_alb_public_1"
  }
}

resource "aws_subnet" "web_server_alb_public_2" { # OK
  vpc_id                  = aws_vpc.web_server.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-north-1c"
  map_public_ip_on_launch = true # instances in this subnet get an ip

  tags = {
    Name = "web_server_alb_public_2"
  }
}

# ** the internet gateway for the elb
resource "aws_internet_gateway" "web_server_alb_public" { # OK
  vpc_id = aws_vpc.web_server.id
  tags = {
    Name = "web_server"
  }
}

# ** the routing table and association to the public subnet
resource "aws_route_table" "web_server_alb_public" { # OK
  vpc_id = aws_vpc.web_server.id
  tags = {
    Name = "web_server_alb_public"
  }
}

# ** the route
resource "aws_route" "web_server_all_internet" { # OK
  route_table_id         = aws_route_table.web_server_alb_public.id
  destination_cidr_block = "0.0.0.0/0" # Any destination
  gateway_id             = aws_internet_gateway.web_server_alb_public.id
}

# ** associate to subnets
resource "aws_route_table_association" "web_server_alb_public_1" { # OK
  subnet_id      = aws_subnet.web_server_alb_public_1.id
  route_table_id = aws_route_table.web_server_alb_public.id
}

# ** associate to subnet
resource "aws_route_table_association" "web_server_alb_public_2" { # OK
  subnet_id      = aws_subnet.web_server_alb_public_2.id
  route_table_id = aws_route_table.web_server_alb_public.id
}


# ** private subnet for the asg
resource "aws_subnet" "web_server_instances_private" { # OK
  vpc_id     = aws_vpc.web_server.id
  cidr_block = "10.0.2.0/24"

  map_public_ip_on_launch = false

  tags = {
    Name = "web_server_instances_private"
  }
}

# TODO: network acls/sg at all levels
# 1. allow only from elb on private subnet [already done?]
# 2. allow only from cloudfront on public subnets [possible?]
# 3. allow only from
# aws_network_acl

# ** network acl for private subnet
resource "aws_network_acl" "web_server_allow_only_from_elb_to_private" { # OK
  vpc_id = aws_vpc.web_server.id

  subnet_ids = [aws_subnet.web_server_instances_private.id]

  # TODO: eips for both elbs and then allow from here
  ingress {
    protocol   = "tcp"
    rule_no    = 300
    action     = "allow"
    cidr_block = "10.0.0.0/24" # elb 1 subnet
    from_port  = 443
    to_port    = 443
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "10.0.1.0/24" # elb 2 subnet
    from_port  = 443
    to_port    = 443
  }

  tags = {
    Name = "main"
  }
}
