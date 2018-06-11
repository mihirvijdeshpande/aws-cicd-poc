terraform {
  backend "s3" {
    encrypt     = "true"
    #bucket      = "dcloud-terraform"
    key         = "vpc.tfstate"
    region      = "eu-west-1"
    dynamodb_table  = "terraform_locking"
  }
}
