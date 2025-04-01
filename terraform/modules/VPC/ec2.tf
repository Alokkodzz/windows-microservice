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
    from_port   = 5001
    to_port     = 5001
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
<#
.SYNOPSIS
    Deploys a .NET application from S3 to IIS on Windows Server 2022
.DESCRIPTION
    This script automates the deployment of a .NET application to IIS, configuring it to be accessible at port 5000.
.NOTES
    File Name      : Deploy-DotNetAppToIIS.ps1
    Prerequisites  : AWS Tools for PowerShell, Windows Server 2022
#>

# Parameters - Update these with your specific values

Start-Transcript -Path "C:\\bootstrap-log.txt"

$LocalArtifactPath = "C:\temp\app_artifact.zip"
$ExtractPath = "C:\inetpub\MyDotNetApp"
$webconfigPath = "C:\inetpub\MyDotNetApp\"
$SiteName = "MyDotNetApp"
$Port = 5001
$AppPoolName = "MyDotNetAppPool"
$AppPoolDotNetVersion = "v4.0" # Change to "No Managed Code" or "v2.0" if needed

# Install required modules if not present
if (-not (Get-Module -ListAvailable -Name AWSPowerShell)) {
    Install-Module -Name AWSPowerShell -Force -Confirm:$false
}

# Import required modules
Import-Module AWSPowerShell
Import-Module WebAdministration

# Function to check if a command succeeded
function Test-CommandSuccess {
    param ($ExitCode)
    if ($ExitCode -ne 0) {
        throw "Command failed with exit code $ExitCode"
    }
}

# Step 1: Install IIS and required features
Write-Host "Installing IIS and required features..."
$features = @(
    "Web-Server",
    "Web-WebServer",
    "Web-Asp-Net45",
    "Web-ISAPI-Ext",
    "Web-ISAPI-Filter",
    "Web-Mgmt-Tools",
    "Web-Mgmt-Console"
)

foreach ($feature in $features) {
    if (-not (Get-WindowsFeature -Name $feature).Installed) {
        Add-WindowsFeature -Name $feature | Out-Null
        Write-Host "Installed feature: $feature"
    }
}

# Step 2: Download artifact from S3
Write-Host "Downloading application artifact from S3..."
if (-not (Test-Path -Path "C:\temp")) {
    New-Item -ItemType Directory -Path "C:\temp" -Force | Out-Null
}
Invoke-WebRequest -Uri "https://dev-swimlaneartifacts.s3.us-east-1.amazonaws.com/windows-microservice.zip" -OutFile $LocalArtifactPath
#Read-S3Object -BucketName $S3BucketName -Key $S3ObjectKey -File $LocalArtifactPath
if (-not (Test-Path -Path $LocalArtifactPath)) {
    throw "Failed to download artifact from S3"
}

# Step 3: Extract the artifact
Write-Host "Extracting application files..."
if (Test-Path -Path $ExtractPath) {
    Remove-Item -Path $ExtractPath -Recurse -Force
}
New-Item -ItemType Directory -Path $ExtractPath -Force | Out-Null

Expand-Archive -Path $LocalArtifactPath -DestinationPath $ExtractPath -Force

# Step 4: Configure IIS Application Pool
Write-Host "Configuring IIS Application Pool..."
if (Test-Path "IIS:\AppPools\$AppPoolName") {
    Remove-WebAppPool -Name $AppPoolName
}

$appPool = New-WebAppPool -Name $AppPoolName
$appPool.managedRuntimeVersion = $AppPoolDotNetVersion
$appPool.autoStart = $true
$appPool.startMode = "AlwaysRunning"
$appPool.processModel.idleTimeout = [TimeSpan]::FromMinutes(0)
$appPool | Set-Item

# Step 5: Create IIS Website
Write-Host "Creating IIS Website..."
if (Get-Website -Name $SiteName -ErrorAction SilentlyContinue) {
    Stop-Website -Name $SiteName
    Remove-Website -Name $SiteName
}

New-Website -Name $SiteName -Port $Port -PhysicalPath $ExtractPath -ApplicationPool $AppPoolName -Force | Out-Null

# Step 6: Configure Application for /api/hello
Write-Host "Configuring application for /api/hello endpoint..."
$apiPath = "$ExtractPath\api\hello"
if (-not (Test-Path -Path $apiPath)) {
    Write-Warning "The /api/hello path doesn't exist in your application. Please ensure your application handles this route."
}

# Step 7: Configure Firewall
Write-Host "Configuring Windows Firewall..."
if (-not (Get-NetFirewallRule -Name "IIS-$Port-In" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name "IIS-$Port-In" -DisplayName "IIS-$Port (In)" -Protocol TCP -LocalPort $Port -Action Allow -Enabled True | Out-Null
}

# Step 8: Start the website
Write-Host "Starting the website..."
Start-Website -Name $SiteName

# Step 9: Verify deployment
Write-Host "Verifying deployment..."
$status = Get-Website -Name $SiteName | Select-Object -ExpandProperty State
if ($status -ne "Started") {
    throw "Website failed to start. Current status: $status"
}

Write-Host @"
Deployment completed successfully!
Your application should now be accessible at:
http://<public-ip>:$Port/api/hello

To find your public IP, you can run:
(Invoke-WebRequest -Uri 'https://api.ipify.org' -UseBasicParsing).Content
"@

# Backup existing web.config
Rename-Item "$webconfigPath\web.config" "$webconfigPath\web.config.bak" -Force -ErrorAction SilentlyContinue

# Create new minimal web.config
@"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <handlers>
      <add name="aspNetCore" path="*" verb="*" modules="AspNetCoreModuleV2" resourceType="Unspecified" />
    </handlers>
    <aspNetCore processPath="C:\Program Files\dotnet\dotnet.exe" arguments=".\MyDotNetApp.dll" stdoutLogEnabled="true" stdoutLogFile=".\logs\stdout" />
  </system.webServer>
</configuration>
"@ | Out-File "$webconfigPath\web.config" -Encoding utf8

# Verify XML syntax
try {
    [xml](Get-Content "$webconfigPath\web.config") | Out-Null
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
    value               = "v1.0.4"
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
