# obyrne: abstracted security-group src IPs as were hardcoded to 0.0.0.0/0 in main.tf
variable "src_cidr_blocks" {
  description = "List of Cisco Source IP ranges"
  default = []
}
variable "default_data_classification" {
}
variable "mail_alias" {
}
variable "name" {
  default = "bastion"
}
variable "ami" {
}
variable "instance_type" {
  default = "t2.micro"
}
variable "iam_instance_profile" {
}
variable "user_data_file" {
  default = "user_data.sh"
}
variable "ssh_user" {
  default = "ubuntu"
}
variable "enable_hourly_cron_updates" {
  default = "false"
}
variable "keys_update_frequency" {
  default = ""
}
variable "additional_user_data_script" {
  default = ""
}
#variable "region" {
  #default = "eu-west-1"
#}
variable "vpc_id" {
}
variable "security_group_ids" {
  description = "Comma seperated list of security groups to apply to the bastion."
  default     = ""
}
variable "subnet_ids" {
  default     = []
  description = "A list of subnet ids"
}
variable "eip" {
  default = ""
}
variable "associate_public_ip_address" {
  default = false
}
variable "key_name" {
 default = ""
}
variable "environment" {
  default = ""
}
