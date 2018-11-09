<#

.SYNOPSIS
This script initializes and format a new disk

.DESCRIPTION
The script should run after a new disk is added

.EXAMPLE
.\InitializeNewDataDisk.ps1 -DiskLabel "DataDisk1"

#>

Param(
    [Parameter()]
    [string]$DiskLabel
)

$new_disk = Get-Disk | Where-Object partitionstyle -eq 'raw'
Initialize-Disk -Number $new_disk.Number
$new_partition = New-Partition -DiskNumber $new_disk.Number -AssignDriveLetter -UseMaximumSize
Format-Volume -DriveLetter $new_partition.DriveLetter -FileSystem NTFS -NewFileSystemLabel "${DiskLabel}" -Confirm:$false
