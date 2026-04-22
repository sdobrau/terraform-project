output "cloudwatch_route53_log_group_name" {
  value = aws_cloudwatch_log_group.web_server_alb_dns_query_logging.name
}

output "web_server_alb_arn" {
  value = aws_alb.web_server.arn
}

output "web_server_alb_dns_name" {
  value = aws_alb.web_server.dns_name
}

output "web_server_alb_2_arn" {
  value = aws_alb.web_server.arn
}

output "web_server_alb_2_dns_name" {
  value = aws_alb.web_server.dns_name
}
