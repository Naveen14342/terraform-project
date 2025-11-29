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

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true

tags = {
 name = "public-subnet-a"
}
}
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.7.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-b"
  }
}


resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.8.0/24"
  availability_zone = "ap-south-1b"
}
# 1. Create Internet Gateway
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main.id
}

# 2. Create a public route table and send internet traffic to IGW
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }
}

# 3. Associate both your subnets to the public route table
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
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
  name = "load-balncer"
  load_balancer_type = "application"
  subnets = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  internal = false
}

resource "aws_autoscaling_group" "asg" {
   desired_capacity     = 2
   max_size             = 4
   min_size             = 1
  vpc_zone_identifier  = [aws_subnet.private.id]
  launch_template {
    id      = aws_launch_template.web_server.id
    version = "$Latest"
  }

}

resource "aws_security_group" "alb-sg" {
  name = "alb-security"
  description = "sg for my app-lb"
 vpc_id      = aws_vpc.main.id

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
  vpc_id      = aws_vpc.main.id  

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
  ami           = data.aws_ami.ubuntu_latest.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.private.id
  security_groups = [aws_security_group.web-instance.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  user_data = file("${path.module}/bootstrap.sh")

}  
resource "aws_launch_template" "web_server" {
  name_prefix   = "web-"
  image_id      = data.aws_ami.ubuntu_latest.id
  instance_type = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web-instance.id]
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }
  user_data = base64encode(file("${path.module}/bootstrap.sh"))
}




