resource "aws_vpc" "TF_VPC" {
  cidr_block       = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = var.tags
}

resource "aws_subnet" "TF_subnet_private" {
    count = length(var.private_subnet)
    vpc_id = aws_vpc.TF_VPC.id
    cidr_block = var.private_subnet[count.index]
    availability_zone = var.availability_zone[count.index]

    tags = var.tags
}

resource "aws_subnet" "TF_subnet_public" {
    count = length(var.public_subnet)
    vpc_id = aws_vpc.TF_VPC.id
    cidr_block = var.public_subnet[count.index]
    availability_zone = var.availability_zone[count.index]
    map_public_ip_on_launch = true

    tags = var.tags
}

resource "aws_internet_gateway" "TF_IGW" {
  vpc_id = aws_vpc.TF_VPC.id
  tags = var.tags
}

resource "aws_eip" "TF_EIP" {
  count = length(var.public_subnet)
  domain   = "vpc"
}

resource "aws_nat_gateway" "TF_NAT" {
  count = length(var.public_subnet)
  allocation_id = aws_eip.TF_EIP[count.index].id
  subnet_id     = aws_subnet.TF_subnet_public[count.index].id

  tags = var.tags
}

resource "aws_route_table" "TF_route_table_public" {
  vpc_id = aws_vpc.TF_VPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.TF_IGW.id
  }

  tags = var.tags
}

resource "aws_route_table" "TF_route_table_private" {
  count = length(var.private_subnet)
  vpc_id = aws_vpc.TF_VPC.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.TF_NAT[count.index].id
  }

  tags = var.tags
}

resource "aws_route_table_association" "TF_private_RT_association" {
  count = length(var.private_subnet)
  subnet_id      = aws_subnet.TF_subnet_private[count.index].id
  route_table_id = aws_route_table.TF_route_table_private[count.index].id
}

resource "aws_route_table_association" "TF_public_RT_association" {
  count = length(var.public_subnet)
  subnet_id      = aws_subnet.TF_subnet_public[count.index].id
  route_table_id = aws_route_table.TF_route_table_public.id
}

resource "aws_security_group" "TF_SG" {
  name = "TF_SG"
  vpc_id = aws_vpc.TF_VPC.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # Allow HTTP traffic from any IP
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
