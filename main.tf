terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "region" {
  default = "eu-west-1"
}

variable "pub_key" {
}

variable "ec2_instance_type" {
  default = "c5.9xlarge"
}

variable "azs" {
  default = [
    "eu-west-1a", 
    "eu-west-1b", 
    "eu-west-1c"]
}

provider "aws" {
  region = var.region
}

resource "aws_vpc" "gbarnett_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# subnet per-AZ
resource "aws_subnet" "gbarnett_vpc_subnet" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.gbarnett_vpc.id
  cidr_block        = cidrsubnet("10.0.0.0/16", 8, count.index)
  availability_zone = var.azs[count.index]
}

# use ubuntu 22.04 LTS
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}


resource "aws_key_pair" "ssh_key" {
  key_name   = "ssh_key"
  public_key = file(var.pub_key)
}

resource "aws_instance" "gbarnett_vm" {
  count           = length(var.azs)
  ami             = data.aws_ami.ubuntu.id
  instance_type   = var.ec2_instance_type
  subnet_id       = aws_subnet.gbarnett_vpc_subnet[count.index].id
  security_groups = [aws_security_group.gbarnett_vpc_ingress_all.id]
  key_name        = aws_key_pair.ssh_key.key_name
  user_data       = file("user_data.sh")
}

# public IP per-each VM so we can ssh 
resource "aws_eip" "gbarnett_vm_ip" {
  count    = length(var.azs)
  instance = aws_instance.gbarnett_vm[count.index].id
}

# simple sg -- allow all ingress/egress
resource "aws_security_group" "gbarnett_vpc_ingress_all" {
  vpc_id = aws_vpc.gbarnett_vpc.id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# route the internet to vpc
resource "aws_internet_gateway" "gbarnett_vpc_gateway" {
  vpc_id = aws_vpc.gbarnett_vpc.id
}

resource "aws_route_table" "gbarnett_vpc_rt" {
  vpc_id = aws_vpc.gbarnett_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gbarnett_vpc_gateway.id
  }
}

resource "aws_route_table_association" "gbarnett_vpc_rta" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.gbarnett_vpc_subnet[count.index].id
  route_table_id = aws_route_table.gbarnett_vpc_rt.id
}
