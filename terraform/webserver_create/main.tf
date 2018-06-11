
# Find our calling AccountID
# Used to map dev/test/prod env purpose to accountIDs
data "aws_caller_identity" "current" {}

# Need access to VPC meta-data for e.g. to determine vpc ID, subnet_ids etc
data "terraform_remote_state" "vpc_metadata" {
  backend = "s3"
  config {
    bucket = "dcloud-terraform-${local.aws_account}"
    key     = "workspace/${terraform.env}/vpc.tfstate"
    region  = "${var.terraform_primary_region}"

    # 24/01/18 - really shouldn't need to specify profile here, but terraform stubbornly seems to
    # ignore the profile you specify outside of this (e.g. via CLI).
    # https://github.com/hashicorp/terraform/issues/5839
    # https://github.com/hashicorp/terraform/issues/13589

    #profile = "${local.aws_account}"
    role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/api-access-cisco"
  }
}

resource "aws_security_group" "webserver-elb-SG" {
  name = "${terraform.env}-webserver-ELB"
  description = "SG to allow web access"
  vpc_id = "${data.terraform_remote_state.vpc_metadata.vpc_id}"

  # webserver HTTP port
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${var.cidr_blocks}"]
  }
  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name                = "${terraform.env}-webserver-elb-SG"
    #Account             = "${lookup(var.account_purpose, data.aws_caller_identity.current.account_id)}"
    Account             = "${local.aws_account}"
    Terraform           = "true"
    UI                  = "true"
    Software            = "true"
    Environment         = "${terraform.env}"
    DataClassification  = "${var.default_data_classification}"
    CiscoMailAlias      = "${var.mail_alias}"
    ResourceOwner       = "dCloud"
    ApplicationName     = "webserver"
  }
}

# ACCESS to/from other VPC resources (10.0.0.0/16)
# Security Group to enable HTTP & SSH access from our VPC CIDR range
resource "aws_security_group" "webserver-hosts-SG" {
  name = "SG_WEBSERVER"
  description = "Enable HTTP & SSH from VPC CIDR range 10.0.0.0/16"
  vpc_id = "${data.terraform_remote_state.vpc_metadata.vpc_id}"

  # SSH access from anywhere within VPC
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["${var.ip_range}"]
  }

  # ELB HTTPS port
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${var.ip_range}"]
  }

  # Permit ICMP Echo (aka ping)
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["${var.ip_range}"]
  }

  # Enable outbound internet access (installing s/w, OS updates etc)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name                = "${terraform.env}-webserver-hosts-SG"
    #Account             = "${lookup(var.account_purpose, data.aws_caller_identity.current.account_id)}"
    Account             = "${local.aws_account}"
    Terraform           = "true"
    UI                  = "true"
    Software            = "true"
    Environment         = "${terraform.env}"
    DataClassification  = "${var.default_data_classification}"
    CiscoMailAlias      = "${var.mail_alias}"
    ResourceOwner       = "dCloud"
    ApplicationName     = "webserver"
  }
}


# Here we build the ELB
# TODO: create module from this
# Note: S3 bucket needs appropriate perms reflected in bucket policy
# from specific Principal/ARN to permit logs from classic load balancer. Ref:
# https://docs.aws.amazon.com/elasticloadbalancing/latest/classic/enable-access-logs.html

resource "aws_elb" "webserver-elb" {
  name                = "${terraform.env}-webserver-elb"
  subnets             = ["${data.terraform_remote_state.vpc_metadata.public_subnets}"]
  security_groups     = ["${aws_security_group.webserver-elb-SG.id}"]
  idle_timeout        = 60 # default
  connection_draining = true

  access_logs {
    # Jan 18 Account Change
    #bucket        = "${lookup(var.elb-log-bucket, var.region)}"
    #bucket        = "${lookup(var.elb-log-bucket, "${lookup(var.account_purpose, data.aws_caller_identity.current.account_id)}.${var.region}")}"
    bucket        = "${lookup(var.elb-log-bucket, "${local.aws_account}.${var.region}")}"
    bucket_prefix = "elb-logs"
    interval      = 60
  }

  listener {
    instance_port       = 80
    instance_protocol   = "http"
    lb_port             = 80
    lb_protocol         = "http"
  }

  health_check {
    healthy_threshold   = 2   #num consecutive successes before declaring healthy
    unhealthy_threshold = 3   #num consecutive failures before declaring unhealthy
    timeout             = 10  #time to wait for response from healthcheck
    target              = "HTTP:80/index.html"
    interval            = 30  #time between healthchecks
  }

  tags {
    Name                = "${terraform.env}-webserver-load-balancer"
    #Account             = "${lookup(var.account_purpose, data.aws_caller_identity.current.account_id)}"
    Account             = "${local.aws_account}"
    Terraform           = "true"
    UI                  = "true"
    Software            = "true"
    Environment         = "${terraform.env}"
    DataClassification  = "${var.default_data_classification}"
    CiscoMailAlias      = "${var.mail_alias}"
    ResourceOwner       = "dCloud"
    ApplicationName     = "webserver"
  }
}

# TODO: bug - this is not being applied to the ELB: https://github.com/hashicorp/terraform/issues/12170

resource "aws_load_balancer_policy" "webserver-stickiness" {
  load_balancer_name  = "${aws_elb.webserver-elb.name}"
  policy_name         = "webserver-stickiness-policy"
  policy_type_name    = "LBCookieStickinessPolicyType"

  policy_attribute {
    name = "CookieExpirationPeriod"
    value = "3600"
  }
}

# This should retrieve the AMI ID for the most recent webserver AMI (compliments
# of packer)
data "aws_ami" "webserver_ami" {
  most_recent = true
  #name_regex  = "^${terraform.env}_dcloud_docstore_*"
  name_regex = "^webserver_*"
  owners      = ["self"]
}

resource "aws_launch_configuration" "launch_config" {
  # To update LC, terraform needs to destroy & recreate
  # see: https://www.terraform.io/docs/providers/aws/r/launch_configuration.html
  name_prefix           = "${terraform.env}-webserver_LC-"
  image_id              = "${data.aws_ami.webserver_ami.id}"
  instance_type         = "${var.ami_instance}"
  #iam_instance_profile  = "${aws_iam_instance_profile.webserver_instance_profile.name}"


  # Reason to concatenate these is because, if this is production, then
  # we wish to also add the qualys-target-host-SG which will permit the launched ec2
  # instances to be scanned. If this is not production then the concatenated list should
  # just contain the single 'docstore-hosts-SG'

  security_groups = ["${aws_security_group.webserver-hosts-SG.*.id}"]

  # For EBS volumes created with an EC2 instance this setting is determined by
  # the value set in the AMI.
  # Amazon images set delete_on_termination to 'true' by default
  # Community images not so. Hence, explicitly specifying it here
  # Update 27/07/17 - our packer build should now do this in advance anyway..

  root_block_device {
      delete_on_termination = "${var.volume_delete_on_termination}"
  }

  lifecycle {
      create_before_destroy = true
    }
}

/*

 obyrne: 23/05/18
 CI/CD testing

changing 'name' below to be something dynamic to try trigger recreation
whenever LC/AMI are changed/recreated.

Basically 3 x things:
1) The ASG interpolates the launch configuration name into its name,
so LC changes always force replacement of the ASG (and not just an ASG update)

2) The ASG sets min_elb_capicity which means Terraform will wait for instances
in the new ASG to show up as InService in the ELB before considering the
ASG successfully created

3) lifecycle {
    create_before_destroy = true
  }

*/
# launch config created above gets bound to this
resource "aws_autoscaling_group" "webserver_asg" {
  name = "${terraform.env}-WEBSERVER-ASG-${aws_launch_configuration.launch_config.name}"
  # lookup() can only return a string, so in our map we've changed from lists to
  # strings. Below, splits string based on ',' then returns list (workaround)
  availability_zones    = ["${split(",",lookup(var.azs, var.region))}"]
  vpc_zone_identifier   = ["${data.terraform_remote_state.vpc_metadata.private_subnets}"]
  launch_configuration  = "${aws_launch_configuration.launch_config.id}"
  max_size          = "2"
  min_size          = "2"
  desired_capacity  = "2"
  health_check_type = "ELB"
  health_check_grace_period = "300"
  load_balancers = ["${aws_elb.webserver-elb.name}"]

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances"
  ]

  tag {
    key                 = "Name"
    value               = "${terraform.env}-webserver"
    propagate_at_launch = true
  }
  tag {
    key                 = "Environment"
    value               = "${terraform.env}"
    propagate_at_launch = true
  }
  tag {
    key                 = "role"
    value               = "webserver_host"
    propagate_at_launch = true
  }
  tag {
    key                 = "Terraform"
    value               = "true"
    propagate_at_launch = true
  }
  tag {
    key                 = "UI"
    value               = "true"
    propagate_at_launch = true
  }
  tag {
    key                 = "Software"
    value               = "true"
    propagate_at_launch = true
  }
  tag {
    key                 = "DataClassification"
    value               = "${var.default_data_classification}"
    propagate_at_launch = true
  }
  tag {
    key                 = "CiscoMailAlias"
    value               = "${var.mail_alias}"
    propagate_at_launch = true
  }
  tag {
    key                 = "ResourceOwner"
    value               = "dCloud"
    propagate_at_launch = true
  }
  tag {
    key                 = "ApplicationName"
    value               = "webserver"
    propagate_at_launch = true
  }
  tag {
    key                 = "Account"
    value               = "${local.aws_account}"
    propagate_at_launch = true
  }

  lifecycle {
      create_before_destroy = true
    }
}

# Configure notification support so we can be alerted whenever the ASG
# creates/terminates new ec2 instances etc...

resource "aws_autoscaling_notification" "webserver_notifications" {
  group_names = [
    "${aws_autoscaling_group.webserver_asg.name}"
  ]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR"
  ]

  topic_arn = "${lookup(var.dcloud_ops_topic_arn, "${local.aws_account}.${var.region}")}"
}

################################################################################
################################################################################
##
## DNS STUFF
##
##  *** PUBLIC DNS 'ciscodcloud.com'***
##  This will create {environment}-docstore.ciscodcloud.com as an Alias record
##  (which is a bit like a CNAME) that points to the ELB.
##
################################################################################
################################################################################
resource "aws_route53_record" "webserver_alias_record" {
  #zone_id = "${lookup(var.dcloud-external-zones, lookup(var.account_purpose, data.aws_caller_identity.current.account_id))}"
  zone_id = "${lookup(var.dcloud-external-zones, local.aws_account)}"

  # this be an assignment of the format e.g. 'uat-docstore.test.ciscodcloud.com'
  name    = "${terraform.env}-webserver.${lookup(var.account_purpose, data.aws_caller_identity.current.account_id)}.ciscodcloud.com"

  type    = "A"

  alias {
    name                    = "${aws_elb.webserver-elb.dns_name}"
    zone_id                 = "${aws_elb.webserver-elb.zone_id}"
    evaluate_target_health  = true
  }
}
