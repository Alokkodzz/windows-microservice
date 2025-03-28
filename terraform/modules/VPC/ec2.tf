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
Invoke-WebRequest -Uri "https://alok-swimlaneartifacts/windows-microservice.zip" -OutFile "C:\\deploy.zip"
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

  tag {
    key                 = "windows_app"
    value               = "Windows-ASG-Instance"
    propagate_at_launch = true
  }
}
