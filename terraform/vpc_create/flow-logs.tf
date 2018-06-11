# Provisions VPC flow logging for ${terraform.env}
# and creates appropriate IAM role with required policy/permissions
# When this completes, VPC Flow Logs can be found in CloudWatch > Logs > '{var.environment}-dcloud-vpc-log-group'

#data "terraform_remote_state" "vpc_metadata" {
#  backend = "s3"
#  config {
#    bucket = "dcloud-terraform"
#    key = "${var.environment}.tfstate"
#    region = "${var.terraform_remote_state}"
#  }
#}

resource "aws_flow_log" "dcloud_flow_log" {
  log_group_name = "${aws_cloudwatch_log_group.dcloud_vpc_log_group.name}"
  iam_role_arn   = "${aws_iam_role.dcloud_flowlogs_role.arn}"
  vpc_id         = "${module.new_vpc.vpc_id}"
  traffic_type   = "ALL"
}

resource "aws_cloudwatch_log_group" "dcloud_vpc_log_group" {
  name = "${terraform.env}-dcloud-vpc-log-group"
  retention_in_days = 90
}

resource "aws_iam_role" "dcloud_flowlogs_role" {
  name = "${terraform.env}-dcloud-flowlogs-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "vpc-flow-policy" {
  name = "${terraform.env}-dcloud_vpc_flowlogs_policy"
  role = "${aws_iam_role.dcloud_flowlogs_role.id}"

  # https://github.com/hashicorp/terraform/issues/14750
  # after a destroy, an apply fails due to log group already existing
  #
  # NOTE: depending on how big a problem this really is, a workaround may be to
  # create the log 'group' outside of terraform, remove the action "logs:createloggroup"
  # from below and just let the streams be created
  #
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}
