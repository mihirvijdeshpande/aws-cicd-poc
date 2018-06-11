# @blame: obyrne
# This will create a new VPC in the AWS region specified in variables.tf
# A private & public subnet will be created per AZ within the CIDR range
# defined in variables.tf
#
# To enable network segmentation, a NAT gateway is created per public subnet and a
# corresponding routing-table created per private subnet. A single routing table suffices for the public subnets.
# Appropriate Routing table entries are configured for each of the private/public
# subnets i.e. private subnets are NAT'd to local NAT gateway (one per AZ), while public subnets
# have a default route to the VPC's Internet Gateway.
# Lastly, a bastion/jumphost is created with an associated security group restricting
# access to TCP:22.
# An Ansible playbook has been written (see ansible folder within 'aws-infra' project) to create accounts
# and upload public SSH keys
# TODO: restrict access to the bastion/jumphost from a single list of source IPs (dCloud DMZaaS jumphosts)

# Get AccountID via which terraform is authorised
# Implemented to cater for multiple accounts (Dec '17)
# outputs accountID and other things.
data "aws_caller_identity" "current" {}

module "new_vpc" {
  # we'll use the tf_aws_vpc module for a lot of the heavy lifting
  source  = "./tf_aws_vpc"
  name    = "${terraform.env}"
  cidr    = "${var.ip_range}"
  private_subnets = "${local.private_subnets}"
  public_subnets  = "${local.public_subnets}"
  enable_nat_gateway    = "true"
  enable_dns_hostnames  = "${var.enable_dns_hostnames}"
  enable_dns_support    = "${var.enable_dns_support}"
  azs = ["${split(",",lookup(var.azs, var.region))}"]
  tags = "${local.tags}"
}

# Create a VPC endpoint to permit VPC resources to access S3 w/o traversing the
# Internet.

resource "aws_vpc_endpoint" "s3-endpoint" {
  vpc_id          = "${module.new_vpc.vpc_id}"
  service_name    = "${format("com.amazonaws.%s.s3","${var.region}")}" #com.amazonaws.eu-west-1.s3
  route_table_ids = ["${concat(module.new_vpc.private_route_table_ids, module.new_vpc.public_route_table_ids)}"]
}

# This creates a bastion/jumphost in the public subnet backed by an ASG and Launch config
# An EIP and a Route-53 record are bound to this instance.
# This ec2 instance is self-healing: should this jumphost die, another will be spawned (auto-scaling takes care of this).
# A cloud-init/bootstrap script on the newly spawned instance will auto-update the EIP association.
# The newly created IAM role 'ec2-s3-EIP' grants the appropriate permissions to enable the ec2 instance to do this.

# Get the ID of the latest dCloud base-hardened AMI
data "aws_ami" "latest_base_ami" {
  most_recent = true
  owners      = ["self"]
  filter {
    name      = "name"
    values    = ["dcloud_base*"]
  }
}

data "aws_ami" "latest_norad_ami" {
  count       = "${terraform.env == "production" ? 1 : 0}"
  most_recent = true
  owners      = ["self"]
  filter {
    name      = "name"
    values    = ["dcloud-norad*"]
  }
}

data "aws_ami" "latest_qualys_ami" {
  count       = "${terraform.env == "production" ? 1 : 0}"
  most_recent = true
  owners      = ["self"]
  filter {
    name      = "name"
    values    = ["dcloud-qualys*"]
  }
}

module "bastion" {
  # the 'tf_aws_bastion' module contains most of our logic
  source                      = "./tf_aws_bastion"
  instance_type               = "${var.ami_instance}"
  ami                         = "${data.aws_ami.latest_base_ami.id}"
  # obyrne env change
  #name                        = "${var.environment}-jumphost"
  name                        = "${terraform.env}-jumphost"
  # IAM role to permit readon-only S3 and EIP association via AWS cli
  iam_instance_profile        = "dcloud-jumphost-role" # IAM role
  vpc_id                      = "${module.new_vpc.vpc_id}"
  subnet_ids                  = ["${module.new_vpc.public_subnets}"]
  src_cidr_blocks             = "${var.cidr_blocks}"
  environment                 = "${terraform.env}" # used in ASG tag.
  default_data_classification = "${var.default_data_classification}"
  mail_alias                  = "${var.mail_alias}"

  eip = "${aws_eip.jumphost.public_ip}"

  additional_user_data_script = <<-EOF
  yum install -y mariadb
  aws ec2 associate-address --instance-id $(curl http://169.254.169.254/latest/meta-data/instance-id) --allocation-id ${aws_eip.jumphost.id} --allow-reassociation --region ${var.region}
  EOF
}

resource "aws_security_group" "norad-SG" {
  # Only create if this is a production VPC
  count       = "${terraform.env == "production" ? 1 : 0}"
  name        = "${terraform.env}-norad-SG"
  description = "SG for Norad"
  vpc_id      = "${module.new_vpc.vpc_id}"

  # Permit SSH from anywhere within VPC
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["${var.ip_range}"]
  }

  # Permit ICMP echo
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "norad_instance" {
  # Only create a Norad Relay if this is a production VPC
  count         = "${terraform.env == "production" ? 1 : 0}"
  ami           = "${data.aws_ami.latest_norad_ami.id}"
  subnet_id     = "${element(module.new_vpc.private_subnets,0)}"
  instance_type = "${var.ami_instance}"
  key_name      = "${var.key_name}"
  vpc_security_group_ids = ["${aws_security_group.norad-SG.id}"]

  root_block_device {
    volume_size = "20"
  }

  tags {
    Name      = "${terraform.env}-norad-relay"
    role      = "norad_host"
    security  = "true"
  }
}

# SG to enable qualys host to phone home
# according to https://cspo-wiki.cisco.com/display/VMPub/Qualys+Scanner+Deployment+Steps+for+AWS
# DNS & 443 are what's needed

resource "aws_security_group" "qualys-sg" {
  # Only create if this is a production VPC
  count   = "${terraform.env == "production" ? 1 : 0}"
  name = "${terraform.env}-qualys-sg"
  description = "Allow all outbound traffic from Qualys"
  vpc_id = "${module.new_vpc.vpc_id}"

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "qualys_instance" {
  # Only create a Qualys instance if this is a production VPC
  count           = "${terraform.env == "production" ? 1 : 0}"
  ami             = "${data.aws_ami.latest_qualys_ami.id}"
  subnet_id       = "${element(module.new_vpc.public_subnets,0)}"
  instance_type   = "t2.medium"
  vpc_security_group_ids = ["${aws_security_group.qualys-sg.id}"]

  root_block_device {
    volume_size = "40"
  }

  tags {
    Name      = "${terraform.env}-qualys-host"
    role      = "qualys_host"
    security  = "true"
    terraform = "true"
  }

  #TODO: place this in vault
  user_data = "PERSCODE=20098889085137"
}

# Create an Elastic IP
resource "aws_eip" "jumphost" {
  vpc = true
}

# Route-53 A record for jumphost
resource "aws_route53_record" "jumphost-dns" {
  zone_id = "${lookup(var.dcloud-external-zones, local.aws_account)}"
  # Below will produce e.g. dev4-jumphost.dev.ciscodcloud.com
  # where subdomain value (${local.aws_account}) will return: dev|test|production
  name    = "${terraform.env}-jumphost.${local.aws_account}.ciscodcloud.com"
  type    = "A"
  ttl     = "60"
  records = ["${aws_eip.jumphost.public_ip}"]
}

# Associate newly created VPC with private hosted zone
resource "aws_route53_zone_association" "dcloud-internal" {
  zone_id = "${lookup(var.dcloud-internal-zones, local.aws_account)}"
  vpc_id = "${module.new_vpc.vpc_id}"
}
