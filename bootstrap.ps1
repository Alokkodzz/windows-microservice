Start-Transcript -Path "C:\\bootstrap-log.txt"

$LocalArtifactPath = "C:\temp\app_artifact.zip"
$ExtractPath = "C:\inetpub\MyDotNetApp"
$webconfigPath = "C:\inetpub\MyDotNetApp\"
$SiteName = "MyDotNetApp"
$Port = 5002
$AppPoolName = "MyDotNetAppPool"
$AppPoolDotNetVersion = "v4.0" # Change to "No Managed Code" or "v2.0" if needed

Write-Host "Downloading application artifact from S3..."
New-Item -ItemType Directory -Path "C:\temp" -Force | Out-Null

Invoke-WebRequest -Uri "https://alok-production-artifacts.s3.us-east-1.amazonaws.com/windows-microservice.zip" -OutFile "C:\temp\app_artifact.zip"


New-Item -ItemType Directory -Path "C:\inetpub\MyDotNetApp" -Force | Out-Null

Expand-Archive -Path "C:\temp\app_artifact.zip" -DestinationPath "C:\inetpub\MyDotNetApp" -Force

# Step 4: Configure IIS Application Pool
Write-Host "Configuring IIS Application Pool..."

New-WebAppPool -Name $AppPoolName
New-Website -Name $SiteName -Port $Port -PhysicalPath "C:\inetpub\MyDotNetApp\publish" -ApplicationPool $AppPoolName -Force | Out-Null

Write-Host "Starting the website..."
Start-Website -Name $SiteName