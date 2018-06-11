#!/usr/bin/env bash

# Amazon Linux (RHEL) - NAT instances
yum update -y
epel provides python-pip & jq
yum install -y epel-release
yum install python-pip jq -y
#####################

pip install --upgrade awscli

# Append addition user-data script
${additional_user_data_script}
