provider "aws" {
  region = "ap-south-1"
}

terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket0998"
    key            = "prod/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
}
}
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1b"
}
data "aws_ami" "ubuntu_latest" {
  most_recent = true
  owners      = ["099720109477"] # Canonical official AWS account

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


resource "aws_lb" "app_lb" {
  name = "load_balncer"
  load_balancer_type = "application"
  subnet_id = [aws_subnet.public.ip]
  internal = false
}

resource "aws_autoscaling_group" "asg" {
   desired_capacity     = 2
   max_size             = 4
   min_size             = 1
  vpc_zone_identifier  = [aws_subnet.private.id]
  launch_configuration = aws_launch_configuration.web_server.id

  

}

resource "aws_security_group" "alb-sg" {
  name = "alb-security"
  description = "sg for my app-lb"

  ingress {
    description = "http access"
    from_port = 80
    to_port = 80
    protocol = "tcp"
   
  }

  egress{
    from_port = 0
    to_port = 0
    protocol = "-1"
    
  }

}

resource "aws_security_group" "web-instance"{

  name = "web-sg"
  description = "aonly access from alb-sg"

  ingress {
    description = "accesss for web"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    security_groups          = [aws_security_group.alb-sg.id]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    
  }
}

resource "aws_iam_role" "ec2_role" {
  name = "ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "ec2_policy" {
  name = "ec2-policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["s3:*"],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action   = ["cloudwatch:*"],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "webserver" {
  ami           = aws_ami.ubuntu_latest.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.private.id
  security_groups = [aws_security_group.web-instance.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  user_data = file("${path.module}/bootstrap.sh")

}  
resource "aws_launch_configuration" "web_server" {
  name_prefix   = "web-"
  image_id      = aws_ami.ubuntu_latest.id
  instance_type = "t3.micro"
  security_groups = [aws_security_group.web_instance.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  user_data = file("${path.module}/bootstrap.sh")
}

resource "aws_autoscaling_group" "asg" {
  desired_capacity     = 2
  max_size             = 4
  min_size             = 1
  vpc_zone_identifier  = [aws_subnet.private.id]
  launch_configuration = aws_launch_configuration.web_server.name
}

