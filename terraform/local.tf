locals {
  ami            = "ami-04e0594a8e5968548"
  instance_type  = "t2.micro"
  subnet_id      = "subnet-0802eb25e45a54f45"
  VPC_availability_zone = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
