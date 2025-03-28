variable "ami" {
    description = "AMI ID for EC2 Instance"
    type = string
}

variable "instance_type" {
    description = "Instance type for EU2 Instacne"
    type = string
  
}

variable "subnet_id" {
    description = "Public subnet ID for EU2 Instance"
    type = string
}

variable "private_subnet" {
  description = "CIDR block for Private subnet"
  type = list(string)
  default = [ "10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24" ]
}

variable "public_subnet" {
  description = "CIDR block for Public subnet"
  type = list(string)
  default = [ "10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24" ]
}

variable "tags" {
  description = "Tag for this project"
  type        = map(string)
  default = {
    "Name" = "windows_app"
    "Environment"  = "Dev"
  }
}

variable "availability_zone" {
    description = "AZ for VPC"
    type = list(string)
}

variable "subnet_ids" {
    description = "Private subnet id's"
    type = list(string)
  
}

