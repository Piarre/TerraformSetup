provider "aws" {
    region = "us-east-1"
    # TODO: Get the access key and secret key from the environment variables
    access_key = ""
    secret_key = ""
}

resource "aws_vpc" "prod_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "prod-gw"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod_vpc.id
}

resource "aws_route_table" "prod-rt" {
  vpc_id = aws_vpc.prod_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "prod-rt"
  }
}

# 4 Create subnet
resource "aws_subnet" "sn_1" {
  vpc_id = aws_internet_gateway.gw.id
  cidr_block = "10.0.1.0/24"

  availability_zone = "us-east-1e"

  depends_on = [ aws_internet_gateway.gw ]
  tags = {
    Name = "prod-sn-1"
  }
}

# Asign each other
resource "aws_route_table_association" "main" {
  subnet_id = aws_subnet.sn_1.id
  route_table_id = aws_route_table.prod-rt.id
}

# Create security group
resource "aws_security_group" "main" {
  name = "allow_web_traffic_plus_ssh"
  description = "Allow web traffic and SSH"
  vpc_id = aws_vpc.prod_vpc.id


 egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web_traffic_plus_ssh"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4" {
  security_group_id = aws_security_group.main.id
  cidr_ipv4         = aws_vpc.prod_vpc.cidr_block
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "allow_http" {
  security_group_id = aws_security_group.main.id
  cidr_ipv4         = aws_vpc.prod_vpc.cidr_block
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh" {
  security_group_id = aws_security_group.main.id
  cidr_ipv4         = aws_vpc.prod_vpc.cidr_block
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_network_interface" "main" {
  subnet_id = aws_subnet.sn_1.id
  private_ips = ["10.0.1.50"]
  security_groups = [aws_security_group.main.id]
}

# Create elastic IP

resource "aws_eip" "public_eip" {
  vpc = true
  network_interface = aws_network_interface.main.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.gw]
}

resource "aws_instance" "prod-instance" {
  ami = "ami-06aa3f7caf3a30282"
  instance_type = "t2.micro"
  availability_zone = "us-east-1e"
  key_name = "main"

  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.main.id
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install apache2 -y
              sudo systemctl start apache2 
              sudo bash -c "echo <h1>Deployed via Terraform</h1> > /var/www/html/index.html"
              EOF

  tags = {
    Name = "prod-instance"
  }
}