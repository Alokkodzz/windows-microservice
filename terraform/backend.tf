terraform {
  backend "s3" {
    bucket = "alokkodzz"
    key    = "State/terraform.tfstate"
    region = "us-east-1"
  }
}
