# * the iam policy, role, and instance profile for all 3 webservers

# ** terraform iam role with AdministratorAccess policy

# 'terraform' role can be assumed when running terraform with
# "adminaccount" credentials

resource "aws_iam_role" "terraform" {
  name               = "terraform"
  assume_role_policy = data.aws_iam_policy_document.terraform.json
}

resource "aws_iam_role_policy_attachment" "terraform" {
  role       = aws_iam_role.terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# i can assume
data "aws_iam_policy_document" "terraform" {
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
      "sts:SetSourceIdentity"
    ]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_source_account_id}:user/adminaccount"]
    }
  }

}

# TODO: s3 write
resource "aws_iam_policy" "web_server_write_to_web_s3_bucket" {
  name = "web_server_write_to_web_s3_bucket"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "al",
        "Effect" : "Allow",
        "Action" : [
          "s3:PutObject"
        ],
        "Resource" : "arn:aws:s3:::web_server_logs/main_logs"
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
        Sid    = "a"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "web_server" {
  role       = resource.aws_iam_role.web_server.name
  policy_arn = resource.aws_iam_policy.web_server_write_to_web_s3_bucket.arn
}

resource "aws_iam_instance_profile" "web_server" {
  name = "web_server"
  role = aws_iam_role.web_server.name
}
