# Introduction

This project is both a playground and an attempt at configuring a
simple "Hello world" web application under AWS best practices, mainly
CloudFront and ALB with ASGs configured. This ensures high scalability
and availability. It could potentially evolve into a larger playground
with other ideas that would require Amazon Lambda, API Gateway
etc. For the moment the focus is VPC setup, IAM policies, ALBs, ASGs
and CloudFront.

# Features

- `VPC`: A standard VPC with `flow logs` enabled and an `internet gateway`
   - 2 each of:
     - 3 subnets, 1 public for the `NAT gateway` and 3 private for the ALB's and private instances
       - each of these are in a different availability zone: `us-east1a` and `us-east1b`
       - 2 private subnets for the ALB
       - 1 private subnet for the ASG instances
  * [x] A `NACL` allowing egress/ingress everywhere. This is required for
    private-NAT-net and back access to work.
  * [x] `Interface and Gateway endpoints` (with security groups as
    necessary) so that the private instance communicates via the AWS
    backbone for SSM Instance Connect
  * [x] Private instances are locked from remoting, only way is via `SSM Instance Connect`.

- `ALB + Cloudfront setup`: A highly available `CloudFront` setup backed
  with an `origin group` of 2 internal ALBs (using `VPC origins`), each composed of:
  * [x] An SG allowing only ingress from and egress to =CloudFront=
  * [x] An `autoscaling group` and `target group`
  * [x] Own `private subnets` for the ALBs and private instances, `public
    subnets` for the NAT so instances can communicate with the internet
    behind the NAT
  * [x] Ingress/egress `SG` rules for the private instances to only allow
    ingress traffic from the ALBs egress everywhere
  * [x] `Autoscaling policy` on low/high CPU usage
  * [x] 'Recurring/Scheduled policy' to spin down to 0 at `2AM` and spinup at `6AM`
  * [x] `Launch template` of an `Amazon Linux AMI` coupled with a simple
    `httpd` hello web page as defined in the `user data` file
  * [x] 7 `EBS` snapshots at 24-hour intervals using a `DLM lifecycle policy`

- Bucket setup:
  * [x] One `logging bucket` for all logs and a `state bucket` for storing Terraform state
  * [x] One logging bucket for `AWS WAF` logs for CloudFront
    * [x] With `SNS event notifications`
  - Each have
      * [x] `Bucket versioning`
      * [x] `Lifecycle configuration`
      * [x] `Public access` blocked
      * [x] `CMK-encryption` (excepting the log bucket)
        * [x] The CMK is here further used to create bucket-level
        keys, avoiding high costs associated to KMS encrypting each
        unique object with a unique data key. See [This
        article](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-key.html)
      * [x] `Same-region replica` setup for high availability
      * [x] `RTC` guarantee of 15 minutes
      * [x] `Access logging` to the `logging bucket` (excepting the
        logging bucket itself as that would cause an infinite loop of
        logs)

- `CloudFront` setup:
  * [x] Has `access logging` enabled to deliver `parquet` in the `log
        bucket`
  * [x] Forwards a `secret value` via `X-Custom-Secret` that the ALB
    expects to prevent attackers from impersonating as CloudFront
  * [x] `Real-time logging` to a `Kinesis stream`
  * [x] `Origin shield` enabled
  * [x] `Geo restriction` to US, Canada, United Kingdom, Romania
  * [x] a `Web ACL` against `log4j` and `Bad IPs` from `US` and `NL`

- Multi-region `CloudTrail` setup:
  * [x] Logs to a special `CloudWatch Log Group` for `CloudTrail`
  * [x] `SNS topic`

- IAM policies as required, mostly taken from Amazon documentation
  * [ ] Could be tightened down, however most IAM policies targeting
        asterisk resources are bound to a service principal so it
        is not as that large a security risk

- A simple global `DynamoDB` table, with autoscaling to maintain 70
  consumed vs provisioned and a `Global Secondary Index`

# Jenkins pipeline

The Jenkinsfile provided here passes the Terraform configuration
through various tools:

* [x] `Betterleaks` to check for committed secrets
* [x] `ClamAV` for antivirus scanning
* [x] `terraform validate` to validate the configs
* [x] `terraform plan` to further check for any validation errors
* [x] `tflint` to check for code smells, lack of best practices etc.
* [x] `checkov` to check for misconfigurations, no implementation of
  best practices etc.
* [x] `trivy` for further security checks
* [x] `Terratest` for testing that certain properties of the
  infrastructure are correct

# Dockerfile

All the tools mentioned above are run in a Jenkins pipeline under a
bespoke `Docker` container as described in `build/Dockerfile`.

```
docker {
            image 'sdobrau/terraform-ci:2026_19_04'
            label 'worker-docker'
            registryUrl 'https://ghcr.io'
            registryCredentialsId 'ghcr_credentials'
            alwaysPull true
        }
```

# Considerations/Future improvements

* [ ] The 2nd ALB setup is not done yet.
* [ ] Instead of allowing private instances egress to the internet so
      they can download packages, consider using a `golden image`
      approach where new AMIs are baked with all necessary, up-to-date
      software and use ASG `instance refresh` to replace the instances
      with ones with the new AMI-Launch template. After that they
      don't need to communicate with the Internet, they just allow
      ingress from the ALBs.
* [ ] ALB HA code is boilerplate. Could be instead and instead ALB
      instantiated twice with different parameters, avoiding `DRY`
* [ ] Terratest module that tests for example whether the CloudFront
      URI is reachable, whether the private instances are truly locked
      down etc.
* [ ] Create a simple application that interfaces with a DynamoDB
      table to put interfacing with the DB to practice
* [ ] The current Dockerfile for the CI has vulnerabilities, consider
      compiling more packages from source to be closer to the edge and
      to avoid high CVE scores
* [ ] Implement bucket-level event notifications for all buckets, not
      just the AWS WAF logs ones
* [ ] At the moment `checkov` doesn't install in the `alpine` docker
      image for the CI pipeline.
* [ ] The SSM Instance Connect configuration was done manually by
      setting up [Default Host Management
      Configuration](https://docs.aws.amazon.com/systems-manager/latest/userguide/quick-setup-default-host-management-configuration.html). How could this be done in Terraform?
* [ ] Working with Terraform is not very straightforward, sometimes
      deleting or creating resources takes several
      minutes. Furthermore I need to think of an alternative way of
      organizing the resources, as all coupling between modules needs
      to be explicitly outputted in the source module and then
      referenced in the destination module as a variable. One can
      imagine how unmaintainable this becomes at scale. Will need to
      research how to Terraform at scale.
      
```
module "load-balancer" {
  source = "./modules/load-balancer"

  aws_source_account_id = data.aws_caller_identity.source.account_id

  adminaccount_web_key_arn = module.kms-key.adminaccount_web_key.arn
  adminaccount_web_key_id  = module.kms-key.adminaccount_web_key.id

  ami_id = "ami-01b14b7ad41e17ba4"

  domain_name = "playing-cloud.xyz"

  log_bucket_bucket = module.bucket-log.log_bucket.bucket
  log_bucket_id     = module.bucket-log.log_bucket.id

  web_server_vpc_id = module.vpc.web_server_vpc_id

  web_server_instances_private_subnet_id   = module.vpc.web_server_instances_private_subnet.id
  web_server_instances_private_subnet_2_id = module.vpc.web_server_instances_private_subnet_2.id

  web_server_alb_private_subnet_1_id = module.vpc.web_server_alb_private_subnet_1.id
  web_server_alb_private_subnet_2_id = module.vpc.web_server_alb_private_subnet_2.id

  web_server_alb_2_private_subnet_1_id = module.vpc.web_server_alb_2_private_subnet_1.id
  web_server_alb_2_private_subnet_2_id = module.vpc.web_server_alb_2_private_subnet_2.id

  secret_header_value = "TestingValue"
  
# References outputs from the VPC module as 
# defined in modules/vpc/outputs.tf:

output "web_server_alb_private_subnet_1" {
  value = aws_subnet.web_server_alb_private_1
}

output "web_server_alb_private_subnet_2" {
  value = aws_subnet.web_server_alb_private_2
}

output "web_server_alb_2_private_subnet_1" {
  value = aws_subnet.web_server_alb_2_private_1
}

output "web_server_alb_2_private_subnet_2" {
  value = aws_subnet.web_server_alb_2_private_2
}

output "web_server_instances_private_subnet" {
  value = aws_subnet.web_server_instances_private
}

output "web_server_instances_private_subnet_2" {
  value = aws_subnet.web_server_instances_private_2
}

output "web_server_vpc_id" {
  value = aws_vpc.web_server.id
}

# Then variables inside of load-balancer 
# (modules/load-balancer/variables.tf) need to be explicitly declared:

variable "aws_source_account_id" {
  description = "ID of source account"
  type        = string
}

variable "adminaccount_web_key_arn" {
  description = "ARN of adminaccount_web key"
  type        = string
}

variable "adminaccount_web_key_id" {
  description = "ID of adminaccount_web key"
  type        = string
}

variable "ami_id" {
  description = "AMI to use for the ASG"
  type        = string
}

# etc..

}
```
# Notes

`mfa_delete` in `aws_s3_bucket_versioning`s does not change anything,
it just reflects the manually configured MFA setup
