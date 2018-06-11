if not explicitly set, the default terraform environment is 'default'.

To create a new terraform environment:
`terraform env new foo`

To select a new terraform environment:
`terraform env select bar`


Steps to build new VPC:
`terraform init`
`terraform env select <your-environment>`
`terraform plan -var 'region=<your-region>'`
`terraform apply -var 'region=<your-region>'`

See here for handy methods to tailor behaviour based on environment name (e.g. for all envs other than default spin up 1 instance, instead of 5)
resource "aws_instance" "example" {
  count = "${terraform.env == "default" ? 5 : 1}"

  # ... other fields
}

https://www.terraform.io/docs/state/environments.html
