#!/usr/bin/env bash

yum -y install amazon-cloudwatch-agent
systemctl enable --now amazon-cloudwatch-agent.service
systemctl enable --now amazon-ssm-agent.service
yum install -y httpd
systemctl enable --now httpd
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
ip_address=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
echo "hello from ${ip_address}" > /var/www/html/index.html
