output "web_server_alb_private_subnet_1" {
  value = aws_subnet.web_server_alb_private_1
}

output "web_server_alb_private_subnet_2" {
  value = aws_subnet.web_server_alb_private_2
}

output "web_server_instances_private_subnet" {
  value = aws_subnet.web_server_instances_private
}

output "web_server_vpc_id" {
  value = aws_vpc.web_server.id
}
