module "tardigrade-ssm-default-host-management" {
  source = "git::https://github.com/plus3it/terraform-aws-tardigrade-ssm-default-host-management.git?ref=d557d50"
  version = "2.0.0"
}

# This enables host management for EC2 instances via SSM and SSM auto-update
# via SSM
# see ...
# ssm uses the role
# role/AWSSystemsManagerDefaultEC2InstanceManagementRole to manage the instances
# ssm-user is the user required to manage
# and AWS-UpdateSSMAgent ssm run command to update ssm once every two weeks
