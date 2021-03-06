<#
.Synopsis

The script that gets called by the ARM template when it deploys a custom script extension. 
It sets up a scheduled task to upload usage data to OMS. 

.DESCRIPTION

It Sets up git and download repository containing the necessary scripts, stores necessary
information onto the host and then sets up a windows scheduled task to upload usage data 
daily.  

.EXAMPLE
This script is meant to be called from an ARM template. 
.\MasterScript `
    -DeploymentGuid <deployment guid> `
    -OMSWorkspaceName "myomsworkspace" `
    -OMSResourceGroup "myomswkspacersc" `
    -azureStackAdminUsername "serviceadmin@contoso.onmicrosoft.com" `
    -azureStackAdminPassword $Password `
    -azureUsername "admin@contoso.onmicrosoft.com" `
    -azurePassword $AzPassword
    -CloudName "Cloud#1"
    -Region "local"
    -Fqdn "azurestack.external"

#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $DeploymentGuid,
    [Parameter(Mandatory = $true)]
    [string] $OMSWorkspaceName,
    [Parameter(Mandatory = $true)]
    [string] $OMSResourceGroup,
    [Parameter(Mandatory = $true)]
    [string] $azureStackAdminUsername,
    [Parameter(Mandatory = $true)]
    [string] $azureStackAdminPassword,
    [Parameter(Mandatory = $true)]
    [string] $azureUsername,
    [Parameter(Mandatory = $true)]
    [string] $azurePassword,
    [Parameter(Mandatory = $true)]
    [string] $azureSubscription,
    [Parameter(Mandatory = $true)]
    [string] $CloudName,
    [Parameter(Mandatory = $true)]
    [string] $Region,
    [Parameter(Mandatory = $true)]
    [string] $Fqdn
)

$azureStackAdminPasswordSecureString = $azureStackAdminPassword | ConvertTo-SecureString -Force -AsPlainText
$azurePasswordSecureString = $azurePassword | ConvertTo-SecureString -Force -AsPlainText

# install git
iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
# refresh the PATH to recognize "choco" command
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") 
choco install git.install -y
# refresh the PATH to recognize git
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# download scripts from GitHub
cd C:\
# git clone "https://github.com/Azure-Samples/AzureStack-AdminPowerShell-OMSIntegration.git" C:\AZSAdminOMSInt
git clone https://github.com/nzRegularIT/AzureStack-AdminPowerShell-OMSIntegration.git C:\AZSAdminOMSInt

# installing powershell modules for azure stack. 
# NuGet required for Set-PsRepository PSGallery.  
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PsRepository PSGallery -InstallationPolicy Trusted
Get-Module -ListAvailable | where-Object {$_.Name -like "Azure*"} | Uninstall-Module
Install-Module -Name AzureRm.BootStrapper -Force
Use-AzureRmProfile -Profile 2017-03-09-profile -Force
Install-Module -Name AzureStack -RequiredVersion 1.3.0 -Force
Install-Module -Name AzureRM.OperationalInsights -RequiredVersion 3.4.1 

# store data required by scheduled task in files. 
$info = @{
    DeploymentGuid = $DeploymentGuid;
    CloudName = $CloudName;
    Region = $Region;
    Fqdn = $Fqdn;
    OmsWorkspaceName = $OMSWorkspaceName;
    OmsResourceGroup = $OMSResourceGroup;
    AzureStackAdminUsername = $azureStackAdminUsername;
    AzureUsername = $azureUsername;
    AzureSubscription = $azureSubscription;
}

$infoJson = ConvertTo-Json $info
Set-Content -Path "C:\AZSAdminOMSInt\info.txt" -Value $infoJson

#store passwords in txt files. 
$passwordText = $azureStackAdminPasswordSecureString | ConvertFrom-SecureString
Set-Content -Path "C:\AZSAdminOMSInt\azspassword.txt" -Value $passwordText
$passwordText = $azurePasswordSecureString | ConvertFrom-SecureString
Set-Content -Path "C:\AZSAdminOMSInt\azpassword.txt" -Value $passwordText

# Download OMS Ingestion API modules (Testing to remove modules from source)
cd C:\AZSAdminOMSInt
mkdir OMSAPI
Save-Module -Name OMSIngestionAPI -Path "C:\AZSAdminOMSInt\OMSAPI"
# Install Module!
Install-Module -Name OMSIngestionAPI -Force

#Download Azure Stack Tools VNext
cd c:\AZSAdminOMSInt
invoke-webrequest https://github.com/Azure/AzureStack-Tools/archive/master.zip -OutFile master.zip
expand-archive master.zip -DestinationPath . -Force

# schedule windows scheduled task
cd C:\AZSAdminOMSInt
& .\schedule_usage_upload.ps1
