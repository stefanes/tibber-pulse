[CmdletBinding()]
param (
    [switch] $Publish,
    [string] $TimeZone = [TimeZoneInfo]::Local.Id
)

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
Import-Module -Name $PSScriptRoot\tibber-pulse.psm1 -Force -PassThru

# Set Log verbosity
$dbgpref = $global:DebugPreference
$vrbpref = $global:VerbosePreference
$global:DebugPreference = $DebugPreference
$global:VerbosePreference = $VerbosePreference

# Get the home Id
$myHome = (Get-TibberHome -Fields 'id', 'appNickname')[0]
$homeId = $myHome.id
Write-Host "Home ID for '$($myHome.appNickname)': $homeId"

# Connect WebSocket and register a subscription
$connection = Connect-TibberWebSocket
$subscription = Register-TibberLiveMeasurementSubscription -Connection $connection -HomeId $homeId -Fields ('timestamp', $global:fields, 'signalStrength')
Write-Host "New GraphQL subscription created: $($subscription.Id)"

# Read data stream
$callbackArguments = @(
    $Publish.IsPresent
    $TimeZone
)
$readUntil = Get-ReadUntil
$time = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($readUntil), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm:ss')
Write-Host "Reading metrics until $time ($TimeZone):"
$result = Read-TibberWebSocket -Connection $connection -Callback ${function:Send-LiveMetricsToGraphite} -CallbackArgumentList $callbackArguments -ReadUntil $readUntil
Write-Host "Read $($result.NumberOfPackages) package(s) in $($result.ElapsedTimeInSeconds) seconds"

# Unregister subscription and close down the WebSocket connection
Unregister-TibberLiveMeasurementSubscription -Connection $connection -Subscription $subscription
Write-Host "GraphQL subscription stopped: $($subscription.Id)"
Disconnect-TibberWebSocket -Connection $connection

# Reset Log verbosity
$global:DebugPreference = $dbgpref
$global:VerbosePreference = $vrbpref
# $global:DebugPreference = $global:VerbosePreference = 'SilentlyContinue'
