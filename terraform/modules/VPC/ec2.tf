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

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
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
  key_name      = "windows"
  vpc_security_group_ids = [aws_security_group.windows_asg_sg.id]

  user_data = base64encode(<<EOF
  <powershell>
  Start-Transcript -Path "C:\\bootstrap-log.txt"

  $LocalArtifactPath = "C:\temp\app_artifact.zip"
  $ExtractPath = "C:\inetpub\MyDotNetApp"
  $webconfigPath = "C:\inetpub\MyDotNetApp\"
  $SiteName = "MyDotNetApp"
  $Port = 5000
  $AppPoolName = "MyDotNetAppPool"
  $AppPoolDotNetVersion = "v4.0" # Change to "No Managed Code" or "v2.0" if needed

  # Step 2: Download artifact from S3
  Write-Host "Downloading application artifact from S3..."
  New-Item -ItemType Directory -Path "C:\temp" -Force | Out-Null

  Invoke-WebRequest -Uri "https://dev-swimlaneartifacts.s3.us-east-1.amazonaws.com/windows-microservice.zip" -OutFile "C:\temp\app_artifact.zip"


  New-Item -ItemType Directory -Path "C:\inetpub\MyDotNetApp" -Force | Out-Null

  Expand-Archive -Path "C:\temp\app_artifact.zip" -DestinationPath "C:\inetpub\MyDotNetApp" -Force

  # Step 4: Configure IIS Application Pool
  Write-Host "Configuring IIS Application Pool..."

  Remove-WebAppPool -Name $AppPoolName


  $appPool = New-WebAppPool -Name $AppPoolName
  $appPool.managedRuntimeVersion = $AppPoolDotNetVersion
  $appPool.autoStart = $true
  $appPool.startMode = "AlwaysRunning"
  $appPool.processModel.idleTimeout = [TimeSpan]::FromMinutes(0)
  $appPool | Set-Item

  # Step 5: Create IIS Website
  Write-Host "Creating IIS Website..."
  Remove-Website -Name $SiteName

  New-Website -Name $SiteName -Port $Port -PhysicalPath "C:\inetpub\MyDotNetApp" -ApplicationPool $AppPoolName -Force | Out-Null

  # Step 7: Configure Firewall
  Write-Host "Configuring Windows Firewall..."

  New-NetFirewallRule -Name "IIS-$Port-In" -DisplayName "IIS-$Port (In)" -Protocol TCP -LocalPort $Port -Action Allow -Enabled True | Out-Null


  # Step 8: Start the website
  Write-Host "Starting the website..."
  Start-Website -Name $SiteName

  Write-Host @"
  Deployment completed successfully!
  Your application should now be accessible at:
  http://<public-ip>:$Port/api/hello

  To find your public IP, you can run:
  (Invoke-WebRequest -Uri 'https://api.ipify.org' -UseBasicParsing).Content
  "@

  # Backup existing web.config
  Rename-Item "C:\inetpub\MyDotNetApp\web.config" "C:\inetpub\MyDotNetApp\web.config.bak" -Force -ErrorAction SilentlyContinue

  # Create new minimal web.config
  @"
  <?xml version="1.0" encoding="utf-8"?>
  <configuration>
    <system.webServer>
      <handlers>
        <add name="aspNetCore" path="*" verb="*" modules="AspNetCoreModuleV2" resourceType="Unspecified" />
      </handlers>
      <aspNetCore processPath="C:\Program Files\dotnet\dotnet.exe" arguments=".\Microservice.dll" stdoutLogEnabled="true" stdoutLogFile=".\logs\stdout" />
    </system.webServer>
  </configuration>
  "@ | Out-File "C:\inetpub\MyDotNetApp\web.config" -Encoding utf8

  # Verify XML syntax
  try {
      [xml](Get-Content "C:\inetpub\MyDotNetApp\web.config") | Out-Null
      Write-Host "web.config XML syntax is valid"
  } catch {
      Write-Host "Invalid XML in web.config: $_"
  }

  iisreset

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
    value               = "v1.0.5"
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
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.TF_VPC.id

  health_check {
    path                = "/api/hello"  # Or a dedicated health endpoint
    port                = "traffic-port" # Uses the same port (5002)
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200-399"  # Success HTTP codes
  }
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
