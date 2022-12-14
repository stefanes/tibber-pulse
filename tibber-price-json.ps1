[CmdletBinding()]
param (
    [string] $Path = '.',
    [string] $TimeZone = [TimeZoneInfo]::Local.Id,
    [switch] $ExcludeTomorrow
)

# Import required modules
Import-Module -Name PSTibber -Force -PassThru
Import-Module -Name PSGraphite -Force -PassThru
Import-Module -Name $PSScriptRoot\tibber-pulse.psd1 -Force -PassThru

# Set log verbosity
$dbgpref = $global:DebugPreference
$vrbpref = $global:VerbosePreference
$global:DebugPreference = $DebugPreference
$global:VerbosePreference = $VerbosePreference

# Get the home Id
$homeId = Get-HomeId

$splat = @{
    HomeId         = $homeId
    ExcludeCurrent = $true
}
$priceInfoMetrics = @()

# Get today's price info
$priceInfo = Get-TibberPriceInfo @splat -IncludeToday
$priceInfoMetrics += Get-PriceInfoMetrics -PriceInfo $priceInfo -TimeZone $TimeZone

if (-Not $ExcludeTomorrow.IsPresent) {
    # Get tomorrow's price info
    $priceInfo = Get-TibberPriceInfo @splat -IncludeTomorrow
    $priceInfoMetrics += Get-PriceInfoMetrics -PriceInfo $priceInfo -TimeZone $TimeZone
}

$priceInfoMetrics | ConvertTo-Json -Depth 10 | Out-File -FilePath "$Path\tibber-price.json"

# Reset log verbosity
$global:DebugPreference = $dbgpref
$global:VerbosePreference = $vrbpref
