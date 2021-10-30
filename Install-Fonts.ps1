<#
.SYNOPSIS
    Installs fonts used for <org> brand.

.DESCRIPTION
    Installs OpenType / TrueType fonts using new method/syntax required for Windows 10 1809 or greater.

    Error Log: C:\Temp\Install-Fonts.log

    NOTES: This script was originally developed to run as a package / Task Sequence step via SCCM.

        Adapting this script to a different Environment:
        1) Line 31 -- Adjust filepath to your preferred log file location; otherwise, the folder 'Temp' must be in the root C:\
        2) Line 54 -- Adjust source directory for font files - original context was the script being deployed via a SCCM Package that included a folder named 'Fonts'
            If you want to utilise as-is, the script directory must have a folder named 'Fonts' - you can then place the desired fonts to install in the folder
        3) Line 72 -- Modify if you plan to install a font that isn't an OpenType or TrueType font.

.EXAMPLE

.NOTES
    Written by Chris Donovan, June 2020
    Email: nerd4hire@iinet.net.au

    Revision:	
       
#>


$logfile = "C:\Temp\Install-Fonts.log"

Function Write-ToLog {

    Param (
        # Message text to be added to log file
        [Parameter(Mandatory=$true)]
        [string]
        $Message
    )

    # Set timestamp
    $timestamp = Get-Date -Format u

    # Write log file entry
    "$($timestamp)  :  $Message" | Out-File $logfile -Append

}

#Timestamp log file entry
Write-ToLog "START"

# Set source files and destination
$source = "$PSScriptRoot\Fonts"
Write-ToLog "Fonts to install: $($source | Measure-Object | Select-Object -ExpandProperty Count)"

# Set COM Shell object for obtaining file list and details
Write-ToLog "Loading COM Shell object..."
$objShell = New-Object -ComObject Shell.Application
$objFolder = $objShell.namespace($source)

# Copy each font to system font directory and create matching registry value
foreach ($font in $objFolder.items()) {
    # Generate values needed for reg key
    $fontName = $($objFolder.getDetailsOf($font, 21))
    $fileType = $($objFolder.getDetailsOf($font, 2))
    $fontType = "(",$fileType.replace(' font file',''),")" -join ""
    $regKeyName = $fontName,$fontType -join ' '

    # Check that font isn't already installed and is a TrueType / OpenType font
    if (!(Test-Path "C:\Windows\Fonts\$($font.Name)") -AND (($fileType -eq 'OpenType font file') -OR ($fileType -eq 'TrueType font file'))) {
        Try {
            Copy-Item -Path $font.Path -Destination "$env:windir\Fonts"
            New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -Name $regKeyName -Value "$($font.Name).otf" -PropertyType String -Force

            Write-ToLog "Installed font $($font.Name)"

        } Catch {
            Write-ToLog "Failed to install font $($font.Name)"
        }
    } Else {
        Write-ToLog "Failed to install font: $($font.Name)  |  File already exists or font is not OpenType/TrueType"
    }
}

Write-ToLog "FINISH"