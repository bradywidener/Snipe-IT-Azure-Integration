#Snipe API Info
$SnipeToken = #SnipeToken Here. Should look "Bearer asdfpiqweurpoiajs;dklfjapoieurpqwoiru..."
$SnipeAPIBase = #SnipeAPI URI here. Should look like "https://domain.snipe-it.com/api/vi"

#Azure API Info
$TenantID = #Tenant ID Here
$SecretValue = #Secret Value Here
$ClientID = #Client ID Here

#Converts Secret to Get-Credential Object
$SecretString = ConvertTo-SecureString -String $SecretValue -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ClientID, $SecretString

#Connect Graph
Import-Module Microsoft.Graph.Beta.Devicemanagement
Connect-MgGraph -NoWelcome -TenantId $TenantID -ClientSecretCredential $Credential

#Querying all Intune Devices
$stopwatch = [System.Diagnostics.Stopwatch]::new()
$stopwatch.start()
$count = 0
$IntuneDevices = Get-MgBetaDeviceManagementManagedDevice -All

Foreach ($Device in $IntuneDevices)
{
$SerialNum = $Device.SerialNumber
#Querying device in Snipe by SerialNumber
$headers=@{}
$headers.Add("accept", "application/json")
$headers.Add("Authorization", "$SnipeToken")
$response = Invoke-WebRequest -Uri "$SnipeAPIBase/hardware/byserial/$SerialNum ?deleted=false" -Method GET -Headers $headers

#converting response to PSObject
$PSResponseSN = $response.content | ConvertFrom-Json

#Try here is to check if the asset exists in Snipe
Try{
#Setting variables to the Snipe ID for the second call
$SnipeID = $PSResponseSN.rows[0].id

#Second request to Snipe for Checkout and Device Info
$headers1=@{}
$headers1.Add("accept", "application/json")
$headers1.Add("Authorization", "$SnipeToken")
$response1 = Invoke-WebRequest -Uri "$SnipeAPIBase/hardware/$SnipeID" -Method GET -Headers $headers

#converting response to PSObject. Adding a half second sleep to prevent 'too many requests' errors.
start-sleep -seconds .5
$PSResponseID = $response1.content | ConvertFrom-Json

#Getting Device Data from Response and setting equal to variables
$AssetTag = $PSResponseID.asset_tag
$Status = $PSResponseID.status_label[0].name
$StatusType = $PSResponseID.status_label[0].status_type
$StatusMeta = $PSResponseID.status_label[0].status_meta
    try{
    $CheckoutUser = $PSResponseID.assigned_to[0].name
    $CheckoutTimeStamp = $PSResponseID.last_checkout[0].formatted
    }
    catch{
        $CheckoutUser = "None"
        $CheckoutTimeStamp = "this time."
    }
#Formatting the note for Intune
$NoteField = @"
[INFO FROM SNIPE IT]
Asset Tag:    $AssetTag
Status:    $Status > $StatusType > $StatusMeta
Current Checkout:    $CheckoutUser at $CheckoutTimeStamp
"@
}
#This will create a custom note if the device is not present in Snipe
Catch{
$NoteField = @"
[INFO FROM SNIPE IT]

ASSET DOES NOT EXIST

"@
    }
Finally{
    #Sending it up to intune in the device's note field
    Update-MgBetaDeviceManagementManagedDevice -ManagedDeviceId $Device.id -Notes $NoteField
    Write-Host "Device with serial"$SerialNum" has been successfully updated." -ForegroundColor yellow -BackgroundColor black
    $count++
}
}

$stopwatch.stop()
Write-Host ""
Write-Host "FINISHED SYNCING $count DEVICES"
Write-Host "Days:"$stopwatch.Elapsed.Days" Hours:"$stopwatch.Elapsed.Hours" Minutes:"$stopwatch.Elapsed.Minutes
Write-Host ""

Disconnect-Graph