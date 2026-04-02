# * the gateway, public vpc with subnet

# ** public vpc for the asg
resource "aws_vpc" "web_server" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    Name = "main"
  }
}

# ** the subnet
resource "aws_subnet" "web_server" {
  vpc_id     = aws_vpc.web_server.id
  cidr_block = "10.0.1.0/24"

  map_public_ip_on_launch = true # instances in this subnet get a public ip

  tags = {
    Name = "web_server"
  }
}

# ** the internet gateway
resource "aws_internet_gateway" "web_server" {
  vpc_id = aws_vpc.web_server.id
  tags = {
    Name = "web_server"
  }
}

# ** the routing table and association to subnet
resource "aws_route_table" "web_server" {
  vpc_id = aws_vpc.web_server.id
  tags = {
    Name = "web_server"
  }
}

resource "aws_route" "web_server" {
  route_table_id         = aws_route_table.web_server.id
  destination_cidr_block = "0.0.0.0/0"  # Any destination
  gateway_id             = aws_internet_gateway.web_server.id
}

# ** associate to subnet
resource "aws_route_table_association" "my_route_table_association" {
  subnet_id      = aws_subnet.web_server.id
  route_table_id = aws_route_table.web_server.id
}

# ** public subnet for the asg
resource "aws_vpc" "web_server" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "main"
  }
}

# ** with one subnet
resource "aws_subnet" "web_server" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "Main"
  }
}

# ** the security group for incoming https

resource "aws_security_group" "https_ingress_only" {
  name = "https_ingress_only"
  description = "Allow only HTTPS ingress"
  vpc_id = aws_vpc.main.id
}

resource "aws_security_group_ingress_rule" "https_ingress_only" {
  # https://docs.aws.amazon.com/AmazonS3/latest/userguide/privatelink-interface-endpoints.html
  description       = "Allow only HTTPS ingress rule"
  type              = "ingress"
  security_group_id = "https_ingress_only"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
}
