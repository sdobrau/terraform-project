# * the iam policy, role, and instance profile for all 3 webservers

# TODO: s3 write
resource "aws_iam_policy" "web_server_write_to_web_s3_bucket" {
  name = "web_server_write_to_web_s3_bucket"

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "allow put to main_logs in web_server_logs",
        "Effect": "Allow",
        "Action": [
          "s3:PutObject"
        ],
        "Resource": "arn:aws:s3:::web_server_logs/main_logs"
      },
    ]
  })
}

resource "aws_iam_role" "web_server" {
  name = "web_server"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "web_server" {
  role = resource.aws_iam_role.web_server
  policy = resource.aws_iam_policy.web_server_write_to_web_s3_bucket.id
}

resource "aws_iam_instance_profile" "web_server" {
  name = "web_server"
  role = aws_iam_role.web_server.name
}
