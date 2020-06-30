$erroractionpreference="Stop"
#Location for the script to log to
$log="C:\windows\config\logs\imaging.log"
$Namespath="path\BookofNames.csv"
function Write-Log
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [Alias('LogPath')]
        [string]$Path=$log,

        [Parameter(Mandatory=$false)]
        [ValidateSet("Error","Warn","Info")]
        [string]$Level="Info",

        [Parameter(Mandatory=$false)]
        [switch]$NoClobber
    )

    Begin
    {
        # Set VerbosePreference to Continue so that verbose messages are displayed.
        $VerbosePreference = 'Continue'
    }
    Process
    {

        # If the file already exists and NoClobber was specified, do not write to the log.
        if ((Test-Path $Path) -AND $NoClobber) {
            Write-Error "Log file $Path already exists, and you specified NoClobber. Either delete the file or specify a different name."
            Return
            }

        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path.
        elseif (!(Test-Path $Path)) {
            Write-Verbose "Creating $Path."
            New-Item $Path -Force -ItemType File
            }

        # Format Date for our Log File
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        # Write message to error, warning, or verbose pipeline and specify $LevelText
        switch ($Level) {
            'Error' {
                Write-Error $Message
                $LevelText = 'ERROR:'
                }
            'Warn' {
                Write-Warning $Message
                $LevelText = 'WARNING:'
                }
            'Info' {
                Write-Verbose $Message
                $LevelText = 'INFO:'
                }
            }

        # Write log entry to $Path
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
    }
    End
    {
    }
}

Write-log -Message "Starting Script"
#Certificate information to call Nutanix Prism API
  add-type @"
  using System.Net;
  using System.Security.Cryptography.X509Certificates;
  public class TrustAllCertsPolicy : ICertificatePolicy {
      public bool CheckValidationResult(
      ServicePoint srvPoint, X509Certificate certificate,
      WebRequest request, int certificateProblem) {
          return true;
      }
  }
"@ -ErrorAction SilentlyContinue
  [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
# Forcing PoSH to use TLS1.2 as it defaults to 1.0 and Prism requires 1.2.
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


#Variables to pass in the API request
  $Header = @{
  "Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ENV:RESTAPIUser+":"+$ENV:RESTAPIPassword ))}
$secpasswd = ConvertTo-SecureString $ENV:RESTAPIPASSWORD -AsPlainText -Force

  Function Get-VMName
  {
    param
    (
        [Parameter(Mandatory=$true)]
        [String]$imagename
    )
    $NamesInCsv=(Import-Csv $Namespath | select name).name
    $body = '
                {
                    "kind": "vm",
                    "sort_order": "ASCENDING",
                    "offset": 0,
                    "length": 1000,
                    "sort_attribute": ""
                } '

    $ListAssetsURI="https://pathtonutanixserver/api/nutanix/v3/vms/list"

#Make API call to get all VM names in use
    Write-Log -Message "Gathering used PVM names"
    $assets=Invoke-RestMethod -Uri $ListAssetsURI -Header $Header -Method post -Body $body -ContentType application/json

#Pair down taken VM names to only PVM's
    Write-Log -Message "Selecting only names that begin with $imagename"
    $TakenNames=$assets.entities.status | Where-Object name -Like $imagename* | select name

      for ($i = 1; $i -le 9999; $i++)
      {
          Switch ($i.tostring().Length)
          {
              1 {$PVMName=$imagename + '000' +$i}
              2 {$PVMName=$imagename + '00' +$i}
              3 {$PVMName=$imagename + 0 + $i}
              4 {$PVMName=$imagename + $i}
          }

          if ($NamesInCsv -notcontains $PVMName)
            {
              $filter='Name -like "{0}"' -f $PVMName
                if ( (!(Get-ADComputer -Filter $filter)) -and $TakenNames -notcontains $PVMName )
                    {
                        $Script:VMName=$PVMName
                        break
                        Write-Log -Message "$VMName isn't in use, I'll select that as the name for our new VM"
                    }
                    else
                    {
                        $NewLine = "{0},{1},{2},{3}" -f $PVMName, 'ADDED BY SCRIPT', 'ADDED BY SCRIPT','ADDED BY SCRIPT'
                        $NewLine | add-content -path $NamesPath
                        Write-Log -Message "$PVMName is in use, I'll add it to the CSV and keep looking for an available name"
                    }
            }
      }
  }

function New-OMNutanixVM{
# Parameter help description
Param (
[CmdletBinding()]
[Parameter(Mandatory=$true)]
  [int]
  $CPUCount,
[Parameter(Mandatory=$true)]
  [int]
  $CoresPerCPU,
[Parameter(Mandatory=$true)]
  $MemorySizeGB,
[Parameter(Mandatory=$true)]
  [string]
  $Computername,
  [int]
  $DiskSizeGB,
  [string]
  $Owner
)
Write-Log -Message "Setting variables for VM creation"
$diskSizeGB=$diskSizeGB * 1024
$MemorySizeGB=$MemorySizeGB * 1024

  $specBody=@"
  {
    "spec": {
      "description": "$Owner",
      "resources": {
        "num_threads_per_core": 1,
        "power_state": "ON",
        "num_vcpus_per_socket": $CoresPerCPU,
        "num_sockets": $CPUCount,
        "memory_size_mib": $MemorySizeGB,
        "boot_config": {
          "boot_device": {
            "disk_address": {
              "device_index": 0,
              "adapter_type": "SATA"
            }
          }
          },
        "hardware_clock_timezone": "UTC",
        "vga_console_enabled": true,
        "disk_list": [
          {
            "device_properties": {
              "disk_address": {
                "device_index": 0,
                "adapter_type": "SATA"
              },
              "device_type": "CDROM"
            },
            "data_source_reference": {
              "kind": "image",
              "uuid": "secretId"
            }
          },
           {
            "device_properties": {
              "disk_address": {
                "device_index": 1,
                "adapter_type": "SCSI"
              },
              "device_type": "DISK"
            },
            "disk_size_mib": $diskSizeGB
          }
        ],
        "nic_list": [
          {
            "nic_type": "NORMAL_NIC",
            "subnet_reference": {
              "kind": "subnet",
              "name": "secretNetwork",
              "uuid": "secretUUID"
            },
            "is_connected": true
          }
        ]
      },
      "cluster_reference": {
        "kind": "cluster",
        "name": "secretClustername",
        "uuid": "secretUUID"
      },
      "name": "$computername"
    },
    "api_version": "3.1.0",
    "metadata": {
      "kind": "vm"
      }
  }
"@
#Create the new VM
  Write-Log -Message "Sending request to Nutanix to create the new VM"
  $CreateURI="https://pathtonutanixserver/api/nutanix/v3/vms"
  $CreateTask=Invoke-RestMethod -Uri $CreateURI -body $specBody -Header $Header -Method post -ContentType application/json
  sleep 60

#Grab the UUID of the newly created VM from the task
  $GetTaskURI="https://pathtonutanixserver/api/nutanix/v3/tasks/$($CreateTask.status.execution_context.task_uuid)"
  do {
  $task=Invoke-RestMethod -Uri $GetTaskURI -Header $Header -Method get -ContentType application/json
  sleep 20
  if ($task.status -eq "FAILED"){exit "The request to create a new VM failed.  Please contact a Nutanix administrator"}
    Write-Log "Creation status is $($task.status)"
} until ($task.status -eq "SUCCEEDED")
  $Script:UUID=$task.entity_reference_list.uuid
  Write-Log -Message "The creation task returned a task ID of $UUID"

#Grab the information from the created VM
  $SpecURI="https://pathtonutanixserver/api/nutanix/v3/vms/$UUID"
  $Script:results=Invoke-RestMethod -Uri $SpecURI -Header $Header -Method get -ContentType application/json
#Parse out the MacAddress of the machine and write it to the CSV to be retrieved by MDT later
  $MacAddress=$results.spec.resources.nic_list.mac_address
  $NewLine = "{0},{1},{2},{3}" -f $VMName,$MacAddress,$UUID,$Owner
  Write-Log -Message "The mac address of the Nutanix NIC adapter for the new machine is $MacAddress"
  Write-Log -Message "Writing demographic information to the CSV for future use by MDT"
  $NewLine | add-content -path $Namespath

#Create the request body to change the boot device to the hard disk
  $results.spec.resources.boot_config.boot_device.disk_address.device_index=1
  $results.spec.resources.boot_config.boot_device.disk_address.adapter_type='SCSI'
  $return=$results | select spec, metadata | ConvertTo-Json -Depth 10
Sleep 180
#Change boot device
  Write-Log -Message "Changing boot device to the hard disk"
  $Put="https://pathtonutanixserver/api/nutanix/v3/vms/$UUID"
  $bootDeviceChange=Invoke-RestMethod -Uri $Put -Header $Header -Body $return -Method put -ContentType application/json

$specifications=@"
VM created with the following specs:
Name: $VMName
Owner: $Owner
Number of CPU's: $CPUCount
Cores per CPU: $CoresPerCPU
RAM(GB): $($MemorySizeGB / 1024)
Hard Disk Size (GB): $($diskSizeGB / 1024)
"@

  Write-Log -Message $specifications
  Write-Log -Message "VM creation completed, handing off to MDT now."
}
#Select an unused name for the VM
    Get-VMName -imagename 'PVM'
#Catch if no owner is entered
if ($env:Owner -eq "")
{
    $owner="Default"
}
else {
    $owner=$env:Owner
}
#Create the VM based on which template was selected
    switch ($env:VM_Type) {
        "Standard" {
            New-OMNutanixVM -CPUCount 2 -CoresPerCPU 1 -MemorySizeGB 8 -Computername $VMName -diskSizeGB 120 -Owner $ENV:Owner
        }
        "Developer" {
            New-OMNutanixVM -CPUCount 4 -CoresPerCPU 1 -MemorySizeGB 16 -Computername $VMName -diskSizeGB 120 -Owner $ENV:Owner
        }
        Default {
            Write-Log "No option was chosen, the process can not continue."
            exit
        }
}