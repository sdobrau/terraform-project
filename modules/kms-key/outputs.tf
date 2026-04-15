output "adminaccount_web_key" {
  value = aws_kms_key.adminaccount_web
}

output "adminaccount_web_key_policy" {
  value = aws_kms_key_policy.web_server_asg
}
