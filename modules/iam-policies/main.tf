# * the iam policy, role, and instance profile for all 3 webservers

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  required_version = "~> 1.14"
}

# ** terraform iam role with AdministratorAccess policy

# 'terraform' role can be assumed when running terraform with
# "adminaccount" credentials

# ** web server allow put to web_server_logs

data "aws_iam_policy_document" "web_server_write_to_web_s3_bucket_and_ssm_and_cloudwatch" { # OK
  # for logging main logs
  statement {
    sid       = "AllowInMainLogs"
    effect    = "Allow"
    resources = ["arn:aws:s3:::web-server-logs-source/main_logs/*"]
    actions   = ["s3:PutObject"]
  }

  # checkov:skip=CKV_AWS_111:TOREVIEW free access
  # checkov:skip=CKV_AWS_356:TOREVIEW free access
  # checkov:skip=CKV_AWS_108:SSM policy: instances are behind NAT
  # for
  # TOREVIEW
  statement {
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ssm:DescribeAssociation",
      "ssm:GetDeployablePatchSnapshotForInstance",
      "ssm:GetDocument",
      "ssm:DescribeDocument",
      "ssm:GetManifest",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:ListAssociations",
      "ssm:ListInstanceAssociations",
      "ssm:PutInventory",
      "ssm:PutComplianceItems",
      "ssm:PutConfigurePackageResult",
      "ssm:UpdateAssociationStatus",
      "ssm:UpdateInstanceAssociationStatus",
      # ignore AVD_AWS_0057: ok because by instance
      "ssm:UpdateInstanceInformation",
    ]
  }

  statement {
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
  }

  statement {
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]
  }
}

data "aws_iam_policy_document" "web_server" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"

      identifiers = [
        "ec2.amazonaws.com",
        "ssm.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role" "web_server" { # OK
  name               = "web_server"
  assume_role_policy = data.aws_iam_policy_document.web_server.json
}

resource "aws_iam_role_policy" "web_server" { # OK
  name   = "web_server"
  role   = aws_iam_role.web_server.id
  policy = data.aws_iam_policy_document.web_server_write_to_web_s3_bucket_and_ssm_and_cloudwatch.json
}

resource "aws_iam_instance_profile" "web_server" { # OK
  name = "web_server"
  role = aws_iam_role.web_server.name
}
