terraform {
  backend "s3" {
    bucket = "alokkodzz-state"
    key    = "State/terraform.tfstate"
    region = "us-east-1"
  }
}
