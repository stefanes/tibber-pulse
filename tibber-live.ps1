#Requires -Modules @{ ModuleName = 'PSTibber'; ModuleVersion = '0.5.2' }

[CmdletBinding()]
param (
    [DateTime] $Until = [DateTime]::MinValue,
    [int] $ReadTimeout = 30,
    [switch] $Publish,
    [string] $TimeZone = [TimeZoneInfo]::Local.Id
)

if ($Until -ne [DateTime]::MinValue -And $Until -le [DateTime]::Now) {
    Write-Host "##[section]Time provided is in the past, returning..." -ForegroundColor Green
    return
}

# Publish to Graphite
$global:fields = @(
    'power'
    'accumulatedConsumption'
    'accumulatedConsumptionLastHour'
    'accumulatedCost'
    'powerProduction'
    'voltagePhase1'
    'voltagePhase2'
    'voltagePhase3'
    'currentL1'
    'currentL2'
    'currentL3'
)

# Import required modules
Import-Module -Name PSTibber -Force -PassThru
Import-Module -Name PSGraphite -Force -PassThru
Import-Module -Name $PSScriptRoot\tibber-pulse.psd1 -Force -PassThru

# Set Log verbosity
$dbgpref = $global:DebugPreference
$vrbpref = $global:VerbosePreference
$global:DebugPreference = $DebugPreference
$global:VerbosePreference = $VerbosePreference

# Get the home Id
$homeId = Get-HomeId

# Connect WebSocket and register a subscription
$connection = Connect-TibberWebSocket
$subscription = Register-TibberLiveMeasurementSubscription -Connection $connection -HomeId $homeId -Fields ('timestamp', $global:fields, 'signalStrength')
Write-Host "New GraphQL subscription created: $($subscription.Id)"

# Read data stream
$splat = @{
    Connection           = $connection
    Callback             = ${function:Send-LiveMetricsToGraphite}
    CallbackArgumentList = @(
        $Publish.IsPresent
        $TimeZone
    )
    TimeoutInSeconds     = $ReadTimeout
}
if ($Until -ne [DateTime]::MinValue) {
    $splat += @{
        ReadUntil = $Until
    }
    $time = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($Until, [CultureInfo]::InvariantCulture), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm:ss')
    Write-Host "Reading metrics until $time ($TimeZone):"
}
$result = Read-TibberWebSocket @splat
Write-Host "Read $($result.NumberOfPackages) package(s) in $($result.ElapsedTimeInSeconds) seconds"

# Unregister subscription and close down the WebSocket connection
Unregister-TibberLiveMeasurementSubscription -Connection $connection -Subscription $subscription
Write-Host "GraphQL subscription stopped: $($subscription.Id)"
Disconnect-TibberWebSocket -Connection $connection

# Reset Log verbosity
$global:DebugPreference = $dbgpref
$global:VerbosePreference = $vrbpref
# $global:DebugPreference = $global:VerbosePreference = 'SilentlyContinue'
