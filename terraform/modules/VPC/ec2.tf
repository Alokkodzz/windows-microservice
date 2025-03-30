resource "aws_security_group" "windows_asg_sg" {
  name_prefix = "windows-asg-sg"
  vpc_id = aws_vpc.TF_VPC.id

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Replace with your IP for security
  }

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
}

resource "aws_launch_template" "windows_template" {
  name_prefix   = "windows-template"
  image_id      = var.ami # Windows Server AMI
  instance_type = var.instance_type
  key_name      = "bastionnew"
  vpc_security_group_ids = [aws_security_group.windows_asg_sg.id]

  user_data = base64encode(<<EOF
<powershell>
Start-Transcript -Path "C:\\bootstrap-log.txt"

# Install IIS
Install-WindowsFeature -name Web-Server -IncludeManagementTools

# Deploy Microservice
Invoke-WebRequest -Uri "https://dev-swimlaneartifacts.s3.us-east-1.amazonaws.com/windows-microservice.zip" -OutFile "C:\\deploy.zip"

Expand-Archive -Path "C:\\deploy.zip" -DestinationPath "C:\\inetpub\\wwwroot\\" -Force

# Restart IIS
Restart-Service W3SVC

Stop-Transcript
</powershell>
EOF
  )
}


resource "aws_autoscaling_group" "windows_asg" {
  name  = "SB1-batch"
  desired_capacity     = 2
  max_size            = 2
  min_size            = 1
  vpc_zone_identifier = aws_subnet.TF_subnet_public[*].id

  launch_template {
    id      = aws_launch_template.windows_template.id
    version = "$Latest"
  }

  termination_policies = ["OldestInstance"]

  instance_refresh {
    strategy = "Rolling"
    preferences {
      instance_warmup        = 0
      min_healthy_percentage = 50
      }
  }

  tag {
    key                 = "windows_app"
    value               = "v1.0.1"
    propagate_at_launch = true
  }
}

resource "aws_lb" "windows_alb" {
  name               = "windows-alb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.TF_SG.id]
  subnets            = aws_subnet.TF_subnet_public[*].id


  tags = {
    Environment = "Dev"
  }
}

resource "aws_lb_target_group" "windows_alb_target_group" {
  name     = "windows-alb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.TF_VPC.id 
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.windows_asg.id
  lb_target_group_arn    = aws_lb_target_group.windows_alb_target_group.arn
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.windows_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.windows_alb_target_group.arn
  }
}
