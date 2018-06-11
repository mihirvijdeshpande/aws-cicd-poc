terraform {
  backend "s3" {
    encrypt     = "true"
    #bucket      = "dcloud-terraform"
    key         = "webserver.tfstate"
    region      = "eu-west-1"
    dynamodb_table  = "terraform_locking"
  }
}
