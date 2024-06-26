terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.52.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.4.3"
    }
  }
  required_version = ">= 1.1.0"
}


variable "region" {
  description = "AWS region to deploy resources to"
  type        = string
  default     = "us-west-2"
}
variable "key_pair_name" {
  description = "key pair name"
  type        = string
}
variable "availability_zone" {
  description = "AWS region to deploy resources to (availability)"
  type        = string
  default     = "us-west-2a"
}
variable "tag_name" {
  description = "tag name"
  type        = string
}
variable "ami_id" {
  description = "Amazon Machine Image ID"
  type        = string
}
provider "aws" {
  region = var.region
}

# Create VPC
resource "aws_vpc" "my_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = var.tag_name
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = var.tag_name
  }
}

# Create Subnet
resource "aws_subnet" "my_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = var.tag_name
  }
}

# Create Route Table
resource "aws_route_table" "my_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = var.tag_name
  }
}

# Associate Subnet with Route Table
resource "aws_route_table_association" "my_route_association" {
  subnet_id      = aws_subnet.my_subnet.id
  route_table_id = aws_route_table.my_route_table.id
}

# Allow HTTP (port 80), HTTPS (port 443), and SSH (port 22) traffic
resource "aws_security_group" "my_security_group" {
  vpc_id = aws_vpc.my_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["18.237.140.160/29"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["207.225.223.16/32"]
  }

  tags = {
    Name = var.tag_name
  }
}

# Launch EC2 instance
resource "aws_instance" "openemr_instance" {
  ami                    = var.ami_id
  instance_type          = "t2.micro"
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.my_subnet.id
  vpc_security_group_ids = [aws_security_group.my_security_group.id]

  tags = {
    Name = var.tag_name
  }
}

# Allocate an Elastic IP
resource "aws_eip" "my_eip" {
}

# Associate the Elastic IP with the instance
resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.openemr_instance.id
  allocation_id = aws_eip.my_eip.id
}
