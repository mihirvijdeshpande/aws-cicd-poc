### These GLOBAL variables should be the same across all environments
# Simply symlink into parent folder across envs.
# Your aws secret key and access key should be in your env variables
#
#### DON'T PUT ANYTHING SENSITIVE IN HERE!!! ####


## Use appropriate AWS profile (as per ~/.aws/config ~/.aws/credentials)
# e.g. terraform plan -var 'region=us-east-1' -var 'profile=production'

variable "profile" {
  description = ""
  default = ""
}

# default to using the [default] profile (which should exist in .aws/config). To override,
# supply a value for 'profile' via CLI or other means. e.g.
# terraform plan -var 'profile=production'
locals {
  default_profile = "default"
  profile = "${var.profile != "" ? var.profile : local.default_profile}"
}

# This 'locals' gives us a shorthand way to query for our AWS account name [test|production|dev]
# Under the covers, a callerID lookup is being performed.
locals {
  aws_account     = "${lookup(var.account_purpose, data.aws_caller_identity.current.account_id)}"
  aws_account_id  = "${lookup(var.accountID_reverse, local.profile)}"
}

/*
provider "aws" {
    # Default region specified in terraform.tfvars but overridable via CLI
    region      = "${var.region}"
    # Default profile specified in locals.profile
    profile     = "${local.profile}"
    version = "~> 1.6"
}
*/

provider "aws" {
  assume_role {
    #role_arn = "arn:aws:iam::681496624581:role/api-access-cisco"
    role_arn      = "arn:aws:iam::${local.aws_account_id}:role/api-access-cisco"
    session_name  = "terraform"
  }
    # Default region specified in terraform.tfvars but overridable via CLI
    region      = "${var.region}"
    # Default profile specified in locals.profile
    #profile     = "${local.profile}"
    version = "~> 1.6"
}

variable "terraform_primary_region" {
  description = "AWS region (S3) where terraform state files live"
  default = "eu-west-1"
}

# we've got a lot: http://bgp.he.net/AS109
variable "cidr_blocks" {
  description = "Source Cisco IP ranges"
  default = [
    "128.107.0.0/16",
    "171.68.0.0/14",
    "173.36.0.0/14",
    "64.100.0.0/16",
    "64.101.0.0/18",
    "64.101.64.0/18",
    "64.101.128.0/18",
    "64.101.192.0/19",
    "64.101.224.0/19",
    "64.102.0.0/16",
    "64.103.0.0/16",
    "64.104.0.0/16",
    "64.68.96.0/19",
    "66.187.208.0/20",
    "72.163.0.0/16",
    "144.254.0.0/16",
    "161.44.0.0/16",
    "198.92.0.0/18",
    "216.128.32.0/19"
  ]
}

variable "log-bucket" {
  description = "S3 Bucket for Logs"
  default = "dcloudlogs"
}

variable "default_data_classification" {
  description = "Default to Cisco Confidential"
  default = "Cisco Confidential"
}

variable "mail_alias" {
  description = "Mail Alias for alerts about Infra"
  default = "pov-services-platform@cisco.com"
}

# Need a bucket per region for ELB logs - AWS won't ship logs from an ELB
# in us-east-1 to a bucket in eu-west-1
variable "elb-log-bucket" {
  type = "map"
  default = {
    production.eu-west-1  = "dcloud-elb-eu-west-1"
    production.us-east-1  = "dcloud-elb-us-east-1"
    dev.eu-west-1         = "dcloud-elb-dev-eu-west-1"
    dev.us-east-1         = "dcloud-elb-dev-us-east-1"
    test.eu-west-1        = "dcloud-elb-test-eu-west-1"
    test.us-east-1        = "dcloud-elb-test-us-east-1"
  }
}

variable "tf_s3_bucket" { default = "dcloud-terraform" }
variable "master_state_file" { default = "base.tfstate" }
variable "prod_state_file" { default = "production.tfstate" }
variable "staging_state_file" { default = "staging.tfstate" }
variable "dev_state_file" { default = "dev.tfstate" }

# lookup() can only return a string (otherwise this would be a map of lists e.g.
# eu-west-1 = ["eu-west-1a, eu-west-1b"])
variable "azs" {
  type = "map"
  default = {
    eu-west-1 = "eu-west-1a,eu-west-1b"
    us-east-1 = "us-east-1b,us-east-1c,us-east-1d"
  }
}

variable "region" { default = "eu-west-1" }
variable "key_name" { default = "owen-ec2-key" }

# Private key file is only used when we need to setup a database.
# Since we aren't generally doing that we can leave it empty
# Will be superceeded by vault when ready
variable "aws_private_key_file" { default = "/dev/null" }

variable "enable_dns_hostnames" { default = "true" }
variable "enable_dns_support" { default = "true" }
variable "ip_range" { default = "10.0.0.0/16" }

variable "mysql_port" { default = "3306" }

variable "volume_delete_on_termination" {
  description = "Whether to delete the root (EBS) volume upon EC2 termination"
  default = "true"
}

variable "ami"                          { default = "ami-c51e3eb6" } # eu-west-1 Amazon linux
variable "dcloud-centos6-ami"           { default = "ami-76c8fb10"}  # eu-west-1 Hardened Base (non-jumphost)
variable "centos7-ami"                  { default = "ami-7abd0209"}  # eu-west-1 Unhardened with updates
variable "dcloud-centos7-ami"           { default = "ami-bd96a5db"}  # eu-west-1 Hardened Base (non-jumphost)
variable "dcloud-centos7-encrypted-ami" { default = "ami-8aefd69c"} # encrypted & hardened (via packer)
variable "dcloud-centos7-bastion-ami"   { default = "ami-8c427dea" } # eu-west-1 Hardened Jumphost AMI
variable "ami_instance"                 { default = "t2.micro"}


# Here we use the AccountID to determine what account we are in
# i.e. if the production accountID is our aws_caller_identity, return 'production' etc
# aws_caller_identity is what enables us to query our AccountID
# https://www.terraform.io/docs/providers/aws/d/caller_identity.html

variable "account_purpose" {
  type = "map"
  default = {
    "295481564406"  = "production"
    "989122839423"  = "test"
    "681496624581"  = "dev"
  }
}

# This is needed to bootstrap the aws provider stanza as cannot perform a
# callerID lookup there (chicken - egg).
# Would much prefer to perform reverse lookup (i.e lookup a key based on value)
# against the 'account_purpose' map
# but no method to do so yet in terraform.
variable "accountID_reverse" {
  type = "map"
  default = {
    "production"  = "295481564406"
    "test"        = "989122839423"
    "dev"         = "681496624581"
  }
}

# ob 18/12/17 - uncomment this after destroy of uat
variable "dcloud-internal-zone" { default = "Z2YBAGLMROATRL"}

variable "dcloud-internal-zones" {
  type = "map"
  default = {
    production  = "Z2YBAGLMROATRL" #dcloud-internal.com  in Production Account
    test        = "Z36MEZCYC94JSX" #dcloud-internal.com  in Test Account
    dev         = "Z2UAN9O40MUM0C" #dcloud-internal.com  in Dev Account
  }
}

variable "dcloud-external-zones" {
  type = "map"
  default = {
    #production  = "ZOM365V6T0II0"   #ciscodcloud.com   move out
    production  = "Z1SR3FT36ORSIB"  #production.ciscodcloud.com
    test        = "Z3D12LOG1U3Y0K"  #test.ciscodcloud.com
    dev         = "Z30HW9VL6PYDXQ"  #dev.ciscodcloud.com
  }
}

# ob 18/12/17 - comment this after destroy of uat
variable "dcloud-external-zone" { default = "ZOM365V6T0II0"}

# zoneID for ciscodcloud.com
variable "cisco-dcloud-com" {
  default = "ZOM365V6T0II0"
}

#
#
# SECURITY STUFF
#
# A map of maps would suit better here, as opposed to using a double-barrel key {account_type}.{region}
# But terraform doesn't (yet) play nice with nested map interaction hence this:

  variable "kms_keys" {
    type = "map"
    default = {
      production.eu-west-1  = "arn:aws:kms:eu-west-1:295481564406:key/136c635b-f4de-489b-935c-b1ad7fdb3187"
      production.us-east-1  = "arn:aws:kms:us-east-1:295481564406:key/3cc74606-e341-46bc-bed8-4017d61ebc37"
      dev.eu-west-1         = "arn:aws:kms:eu-west-1:681496624581:key/5d8a08e0-39ae-48b1-b409-f27790d8fa78"
      dev.us-east-1         = "arn:aws:kms:us-east-1:681496624581:key/69c8eab6-fb66-46ea-a884-0cc6a1cb5b54"
      test.eu-west-1        = "arn:aws:kms:eu-west-1:989122839423:key/9c4ee6a8-dbee-4384-b663-49ad8943b6e8"
      test.us-east-1        = "arn:aws:kms:us-east-1:989122839423:key/346d26a0-8a6e-49a2-a175-d5bd9f53cacf"
    }
  }

  # Jan 18 Account change work. Changing keys to map to facilitate production/test/dev and
  # multiple regions
  # Used to subscribe to Cloudwatch alerts, scaling-group notifications etc..
  variable "dcloud_ops_topic_arn" {
    type = "map"
    default = {
      production.eu-west-1  = "arn:aws:sns:eu-west-1:295481564406:dcloud-ops"
      production.us-east-1  = "arn:aws:sns:us-east-1:295481564406:dcloud-ops"
      dev.eu-west-1         = "arn:aws:sns:eu-west-1:681496624581:dcloud-ops"
      dev.us-east-1         = "arn:aws:sns:us-east-1:681496624581:dcloud-ops"
      test.eu-west-1        = "arn:aws:sns:eu-west-1:989122839423:dcloud-ops"
      test.us-east-1        = "arn:aws:sns:us-east-1:989122839423:dcloud-ops"
      }
  }

# TODO: delete this when all code references above 'kms_keys' map instead.
variable "dcloud-encryption-key" {
  description = "dCloud EC2, EBS, RDS Encryption key in KMS"
  default     = "arn:aws:kms:eu-west-1:295481564406:key/136c635b-f4de-489b-935c-b1ad7fdb3187"
}

# Use 'custom_tags' to add additional tags. e.g:
# terraform apply -var 'region=us-east-1' -var 'custom_tags={KubernetesCluster="staging.ciscodcloud.com"}'

variable "custom_tags" {
  type = "map"
  default = {}
}

# Nice way to get around the inability to perform interpolation within variable
# declarations.
# ref: https://www.terraform.io/docs/configuration/locals.html

locals {
  default_tags = {
    Terraform           = "true"
    Environment         = "${terraform.env}"
    DataClassification  = "${var.default_data_classification}"
    CiscoMailAlias      = "${var.mail_alias}"
    ResourceOwner       = "dCloud"
    Account             = "${local.aws_account}"
  }
  # blend any custom tags with our default tags and return a (union) map
  # To use this, just point to: ${local.tags}
  tags = "${merge(local.default_tags, var.custom_tags)}"
}
