# -------------------------------
# Provider configuration
# -------------------------------
provider "aws" {
  region = "ap-southeast-1"
}

# -------------------------------
# Create a VPC
# -------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "nginx-vpc"
  }
}

# -------------------------------
# Create a subnet
# -------------------------------
resource "aws_subnet" "main_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-southeast-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "nginx-subnet"
  }
}

# -------------------------------
# Create an Internet Gateway
# -------------------------------
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "nginx-gw"
  }
}

# -------------------------------
# Create a route table
# -------------------------------
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "nginx-rt"
  }
}

# Associate subnet with route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.main_subnet.id
  route_table_id = aws_route_table.rt.id
}


# -------------------------------
# Generate a new SSH key pair
# -------------------------------
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save private key locally
resource "local_file" "private_key_pem" {
  filename        = "${path.module}/ec2-key.pem"
  content         = tls_private_key.ec2_key.private_key_pem
  file_permission = "0400"
}

# Create AWS key pair using public key
resource "aws_key_pair" "deployer_key" {
  key_name   = "github-actions-ec2-key"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

# -------------------------------
# Security group (allow SSH + HTTP)
# -------------------------------
resource "aws_security_group" "nginx_sg" {
  name        = "nginx-sg"
  description = "Allow SSH and HTTP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# -------------------------------
# EC2 instance
# -------------------------------
resource "aws_instance" "nginx_instance" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.main_subnet.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids      = [aws_security_group.nginx_sg.id]

  tags = {
    Name = "nginx-github-actions"
  }

  # Wait until instance is ready before outputs
  provisioner "local-exec" {
    command = "echo EC2 instance is up!"
  }
}

# -------------------------------
# Outputs (for GitHub Secrets)
# -------------------------------
output "EC2_HOST" {
  value       = aws_instance.nginx_instance.public_ip
  description = "Public IP of the EC2 instance"
}

output "EC2_USER" {
  value       = "ubuntu"
  description = "Default SSH username for Ubuntu AMI"
}

output "EC2_SSH_KEY" {
  value       = tls_private_key.ec2_key.private_key_pem
  sensitive   = true
  description = "Private SSH key for GitHub Actions"
}
