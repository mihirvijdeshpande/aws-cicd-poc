variable "extra_private_subnets" {
  type = "list"
  default = []
}

variable "extra_public_subnets" {
  type = "list"
  default = []
}

# By default, 2 x private and 2 x public subnets will be provisioned.
# If extra are required, these can be declared via the "extra_private_subnets"
# and "extra_public_subnets" vars.
# The number of private subnets and public subnets must be equal i.e. if you
# add an extra private subnet you must also add an extra public one!

# This will merge any additionally declared public/private subnets into the default
locals {
  default_private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  default_public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  private_subnets = "${concat(local.default_private_subnets,var.extra_private_subnets)}"
  public_subnets  = "${concat(local.default_public_subnets, var.extra_public_subnets)}"

}
