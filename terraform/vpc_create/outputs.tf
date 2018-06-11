#output "account_id" {
#  value = "${data.aws_caller_identity.current.account_id}"
#}

# Bastion external IP address.
output "external_ip" {
  value = "${aws_eip.jumphost.public_ip}"
}
output "jumphost_FQDN" {
  value = "${aws_route53_record.jumphost-dns.name}"
}

output "environment" {
  value = "${terraform.env}"
}

output "vpc_id" {
  value = "${module.new_vpc.vpc_id}"
}

output "private_subnets" {
  value = ["${module.new_vpc.private_subnets}"]
}

output "public_subnets" {
  value = ["${module.new_vpc.public_subnets}"]
}

output "routing-tables" {
  #value = ["${module.new_vpc.private_route_table_ids}"]
  value = ["${concat("${module.new_vpc.private_route_table_ids}","${module.new_vpc.public_route_table_ids}")}"]
}

output "jumphost-eip" {
  value = "${aws_eip.jumphost.public_ip}"
}
/*
output "qualys-private-ip" {
  value = "${aws_instance.qualys_instance.*.private_ip}"
}
*/
// need splat index due to 'count' being set (i.e. qualys isn't provisioned in non-prod envs)
output "qualys-private-ip" {
  value = "${aws_instance.qualys_instance.*.private_ip}"
}
/*
output "qualys-public-ip" {
  value = "${aws_instance.qualys_instance.*.public_ip}"
}
*/
output "qualys-public-ip" {
  value = "${aws_instance.qualys_instance.*.public_ip}"
}
/*
output "qualys-sg-id" {
  value = "${aws_security_group.qualys-sg.*.id}"
}
*/
output "qualys-sg-id" {
  value = "${aws_security_group.qualys-sg.*.id}"
}

output "nat_gateway_ids" {
  value = ["${module.new_vpc.nat_gateway_ids}"]
}
