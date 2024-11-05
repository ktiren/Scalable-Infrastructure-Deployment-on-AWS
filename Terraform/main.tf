provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "app_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "app-vpc"
  }
}

# Subnets
resource "aws_subnet" "app_subnet_a" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "app-subnet-a"
  }
}

resource "aws_subnet" "app_subnet_b" {
  vpc_id            = aws_vpc.app_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "app-subnet-b"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "app_ig" {
  vpc_id = aws_vpc.app_vpc.id

  tags = {
    Name = "app-ig"
  }
}

# Route Table
resource "aws_route_table" "app_rt" {
  vpc_id = aws_vpc.app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app_ig.id
  }

  tags = {
    Name = "app-rt"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.app_subnet_a.id
  route_table_id = aws_route_table.app_rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.app_subnet_b.id
  route_table_id = aws_route_table.app_rt.id
}

# Security Group
resource "aws_security_group" "app_sg" {
  vpc_id = aws_vpc.app_vpc.id

  ingress {
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

  tags = {
    Name = "app-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "app_lb" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.app_sg.id]
  subnets            = [aws_subnet.app_subnet_a.id, aws_subnet.app_subnet_b.id]

  enable_deletion_protection = false

  tags = {
    Name = "app-lb"
  }
}

# Target Group
resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.app_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "app-tg"
  }
}

# Listener for Load Balancer
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Launch Configuration
resource "aws_launch_configuration" "app_lc" {
  name                        = "app-lc"
  image_id                    = "ami-0fff1b9a61dec8a5f" # Update with a valid AMI ID for the desired region
  instance_type               = "t2.micro"
  security_groups             = [aws_security_group.app_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y nginx
              systemctl start nginx
              systemctl enable nginx
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app_asg" {
  launch_configuration = aws_launch_configuration.app_lc.id
  min_size            = 3
  max_size            = 5
  desired_capacity    = 3
  vpc_zone_identifier = [aws_subnet.app_subnet_a.id, aws_subnet.app_subnet_b.id]

  tag {
    key                 = "Name"
    value               = "app-instance"
    propagate_at_launch = true
  }

  health_check_type         = "ELB"
  health_check_grace_period = 300

  target_group_arns = [aws_lb_target_group.app_tg.arn]
  
  lifecycle {
    create_before_destroy = true
  }
}

# Target Tracking Scaling Policy
resource "aws_autoscaling_policy" "target_tracking_policy" {
  name                   = "target-tracking-scaling-policy"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}
