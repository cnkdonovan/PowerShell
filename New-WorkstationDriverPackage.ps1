<#
.SYNOPSIS
    Create a new workstation driver package in SCCM

.DESCRIPTION
    Script will import new device drivers and add to a new package using the following steps:
        - USER PROMPT -- Model (Validated) 
        - USER PROMPT -- Version (format in this design is [WindowsBuild]_[YearDownloaded]-[MonthDownloaded], e.g. 1909_2020-03)
        - Data Check: Test path for new version of Driver Source
        - Data Check: Check if model is part of Surface family -- run Set-DriverHash function
        - Data Check: Test path for new version of Driver Package -- Create folder for Driver Package if missing
        - SCCM Check: Check for existing category / package
        - SCCM: Create Category
        - SCCM: Create Driver Package
        - SCCM: Distribute new Driver Package
          
.FUNCTION Set-DriverHash
    
.PARAMETER Model

.PARAMETER Version

.EXAMPLE

.NOTES
    Written by Chris Donovan, June 2020
    Credit to William Bracken
    Sample script and notes provided at this URL were used to develop this script:
         https://model-technology.com/blog/importing-drivers-creating-driver-packages-using-powershell/

    Adapting this script to a different SCCM Environment:
        1) Line 52 -- Update the 'ValidateSet()' Parameter section for Model values -- IMPORTANT: This script assumes that you will use the same naming convention for the driver source and driver package directories.
        2) Line 94 -- Update the $rootDriverSource path value to match your source folder for importing drivers.
        3) Line 95 -- Update the $rootDriverPackage path value to match the folder containing your SCCM driver packages.
        4) Line 99 -- $altVersion step is based on a version naming convention of [Win10Version]_[yyyy-mm]
        5) Line 223 -- Update path to SCCM PowerShell module if installed to a different drive/location
        5) Line 226 -- insert your SCCM Site Code
        6) Line 278 -- insert the FQDN of the server hosting your Distribution Point


    Revision:	
        2020-06-08 -- Reconfigured function to adjust file hash for Surface devices; now applies to all devices
        2021-03-04 -- Updated location for .PSD1 file to import SCCM PS Module. New location due to SCCM upgrade
        
       
#>


Param (

    # Specify the model of workstation the drivers apply to
    [Parameter(Mandatory=$true)]
    [ValidateSet(
        'Latitude 5290 2-IN-1',
        'Latitude E5540',
        'Latitude E5450',
        'Latitude 7300',
        'Latitude 7480',
        'Latitude E7250',
        'Latitude 7390',
        'Latitude E7270',
        'Latitude E7240',
        'Latitude E7440',
        'Latitude E7450',
        'XPS 15 9560',
        'XPS 15 9570',
        'Surface Pro 5',
        'Latitude E7470',
        'Surface Book 2',
        'Surface Pro 4',
        'Surface Pro 6',
        'Surface Pro 7',
        'OptiPlex 7040',
        'OptiPlex 7060',
        'OptiPlex 7070',
        'Precision Rack 7910',
        'Precision 3430',
        'Precision 3431',
        'Precision 5510',
        'Precision T1700',
        'Precision T3420',
        'Precision T5810',
        'Precision T5820')]
    $Model,

    # Specify the build/package version for these drivers (should match the folder containing source files)
    [Parameter(Mandatory=$true)]
    $Version

)

Write-Host "Setting variables..." -ForegroundColor Yellow

# Set variables for root directory paths
$rootDriverSource = '[path to driver source directory]'
$rootDriverPackage = '[path to driver package directory]'

# Set variables from user input
$altModel = $Model -replace ' ','_'
$altVersion = $Version -replace '_',' - '

$SourcePath = "$rootDriverSource\$Model\$Version"
$PackagePath = "$rootDriverPackage\$Model\$Version"

$CategoryName = "$Model - $altVersion"
$PackageName = $CategoryName

Write-Host "Alt Model=  $altModel"
Write-Host "Alt Version=  $altVersion"
Write-Host "Source Path=  $SourcePath"
Write-Host "Package Path=  $PackagePath"
Write-Host "Category / Package Name=  $CategoryName"

# Run path checks
$PathCheck = $true

# Source Path
Write-Host "Checking Driver Source path..."
If (Test-Path $SourcePath -ErrorAction SilentlyContinue) {
    Write-Host "Source Path check passed..." -ForegroundColor Green
} Else {
    Write-Warning "Driver Source path check failed. Unable to continue."
    $PathCheck = $false
}

# Source Path files
Write-Host "Checking driver files in Driver Source..." -ForegroundColor Yellow
If (Get-ChildItem -Path $SourcePath -Recurse -Filter "*.inf" ) {
    Write-Host "File check passed..."
} Else {
    Write-Warning "Driver files not detected. Unable to continue."
    $PathCheck = $false
}

# Error out for issues with Source Path
If ($PathCheck -eq $false) {
    Write-Host "FAILED -- Resolve issue(s) with source files listed above." -ForegroundColor Red
    Break
}

# Package Path for model
Write-Host "Checking package path for model $Model..." -ForegroundColor Yellow
If (Test-Path "$rootDriverPackage\$Model" -ErrorAction SilentlyContinue) {
    Write-Host "Package Path check for $Model passed..." -ForegroundColor Green
} Else {
    Write-Warning "Package Path check for $Model failed. Unable to continue."
    $PathCheck = $false
}


# Package Path for version
Write-Host "Checking package path for existing folder for version $Version..." -ForegroundColor Yellow
If (Test-Path $PackagePath -ErrorAction SilentlyContinue) {
    Write-Warning "Folder for package version $version already exists. Checking contents..."

    # If it exists, make sure it's empty
    If (Get-ChildItem $PackagePath -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer }) {
        Write-Warning "Folder for package version $Version is not empty. Unable to continue."
        $PathCheck = $false
    } Else {
        Write-Host "Folder for package version $Version is empty. Able to continue..." -ForegroundColor Green
    }

} ElseIf ($PathCheck -eq $true) {
    Write-Host "Creating new folder for new package version $Version"
    New-Item -Path "$rootDriverPackage\$Model" -Name $Version -ItemType Directory

} Else {
    # Error out for issues with Package Path
    Write-Host "FAILED -- Resolve issue(s) with package location listed above." -ForegroundColor Red
    Break
}

# Function to fix file hash issue for duplicate drivers between models
function Set-DriverHash {
    <#
    .SYNOPSIS
        Duplicate a file in all subfolders of a Driver Source to manipulate SCCM hash value checks

    .NOTES
        Written by Chris Donovan, June 2020
        Revision:	
       
    #>
    
    # Check for existing mod file
    Write-Host "Checking for existing mod file..." -ForegroundColor Yellow
    $modFilePath = "$SourcePath\$($Version)_$altModel.txt"

    If (Get-Item -Path $modFilePath -ErrorAction SilentlyContinue) {
        Write-Host "Mod file already exists..."
        $modFile = Get-Item -Path $modFilePath
    } Else {
        Write-Host "No mod file found. Creating new one..."
        $modText = 'This file is copied to every subfolder for this driver deployment to manipulate hash values read by SCCM.'
        $modText | Out-File $modFilePath
    }
    
    # Copy mod file to all subfolders in Driver Source directory
    Write-Host 'Duplicating mod file...' -ForegroundColor Yellow

    $modFile = Get-Item -Path $modFilePath
    Get-ChildItem -Path $SourcePath -Recurse | Where-Object { $_.PSIsContainer } | ForEach-Object {
            Copy-Item $modFile.FullName -Destination $PSItem.FullName 
    }

}

# Error out for issues with Package Path
If ($PathCheck -eq $false) {
    Write-Host "FAILED -- Resolve issue(s) with package location listed above." -ForegroundColor Red
    Break
}

# Checking if selected model is from Surface family
Write-Host "Manipulating file hash values for source..." -ForegroundColor Yellow
Write-Host "Running Set-DriverHash function..."

Set-DriverHash


# Import SCCM module
Write-Host "Connecting to SCCM..." -ForegroundColor Yellow
Import-Module "C:\Program Files (x86)\Microsoft Endpoint Manager\AdminConsole\bin\ConfigurationManager.psd1"

# Move to SCCM Site
Set-Location [insert SCCM Site Code]:

# Check for existing package
Write-Host "Checking for existing package..." -ForegroundColor Yellow
If (Get-CMDriverPackage -Name $PackageName) {
    Write-Warning "Driver package $PackageName already exists. Unable to continue."
    Write-Host "FAILED -- Driver package already exists. Confirm you aren't importing drivers that already exist in SCCM." -ForegroundColor Red
    Set-Location C:
    Break
} Else {
    Write-Host "No existing package found." -ForegroundColor Green
}

# Check for existing driver category
Write-Host "Checking for existing driver category..." -ForegroundColor Yellow
If (Get-CMCategory -CategoryType DriverCategories -Name $CategoryName) {
    Write-Warning "Category $CategoryName already exists."
    Write-Host "FAILED -- Driver Category already exists. Confirm you are not importing drivers that already exist in SCCM" -ForegroundColor Red
    Set-Location C:
    Break
} Else {
    Write-Host "No existing category found." -ForegroundColor Green
}

# Create new driver package
Write-Host "Creating new driver package $PackageName..."
New-CMDriverPackage -Name $PackageName -Path $PackagePath 
Write-Host "New driver package created." -ForegroundColor Green

# Create new driver category
Write-Host "Creating new driver category $CategoryName..."
New-CMCategory -CategoryType DriverCategories -Name $CategoryName 
Write-Host "New driver category created." -ForegroundColor Green

# Import new drivers
Write-Host "Importing new drivers..." -ForegroundColor Yellow
$DriverPackage = Get-CMDriverPackage -Name $PackageName
$DriverCategory = Get-CMCategory -CategoryType DriverCategories -Name $CategoryName

Try {
    Import-CMDriver -UncFileLocation $SourcePath -ImportFolder -ImportDuplicateDriverOption AppendCategory -EnableAndAllowInstall $true -DriverPackage $DriverPackage -AdministrativeCategory $DriverCategory -UpdateDistributionPointsforDriverPackage $false 
    Write-Host "Driver import completed." -ForegroundColor Green
} Catch {
    Write-Host "FAILED -- Unable to import drivers." -ForegroundColor Red
    Set-Location C:
    Break
}

# Update driver package on Distribution Point
Write-Host "Distributing new Driver Package to Distribution Point(s)..." -ForegroundColor Yellow

Try {
    Start-CMContentDistribution -DriverPackageName $PackageName -DistributionPointName "[DP Server Name]"  -ErrorVariable $errormsg
    Write-Host "Content distribution completed." -ForegroundColor Green
} Catch {
    Write-Host "FAILED -- Content distribution failed. Check driver import results and distribute manually." -ForegroundColor Red
    Write-Host $errormsg
}

Set-Location C: