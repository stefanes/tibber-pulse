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
$todaysPriceInfoMetrics = Get-PriceInfoMetrics -PriceInfo $priceInfo -TimeZone $TimeZone
$priceInfoMetrics += $todaysPriceInfoMetrics
$priceInfoMetrics += @{
    priceAvgToday = $todaysPriceInfoMetrics[-1].priceAvg
    time          = $todaysPriceInfoMetrics[-1].time
    startsAt      = $todaysPriceInfoMetrics[-1].startsAt
}

if (-Not $ExcludeTomorrow.IsPresent) {
    # Get tomorrow's price info
    $priceInfo = Get-TibberPriceInfo @splat -IncludeTomorrow
    $tomorrowsPriceInfoMetrics = Get-PriceInfoMetrics -PriceInfo $priceInfo -TimeZone $TimeZone
    $priceInfoMetrics += $tomorrowsPriceInfoMetrics
    $priceInfoMetrics += @{
        priceAvgTomorrow = $tomorrowsPriceInfoMetrics[-1].priceAvg
        time             = $tomorrowsPriceInfoMetrics[-1].time
        startsAt         = $tomorrowsPriceInfoMetrics[-1].startsAt
    }
}
$priceInfoMetrics | ConvertTo-Json -Depth 10 | Out-File -FilePath "$Path\tibber-price.json"

# Reset log verbosity
$global:DebugPreference = $dbgpref
$global:VerbosePreference = $vrbpref
