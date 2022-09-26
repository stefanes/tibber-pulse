param (
    [switch] $Publish,
    [switch] $Detailed,
    [string] $TimeZone = [TimeZoneInfo]::Local.Id
)

function Send-LiveMetricsToGraphite {
    param (
        [Object] $MetricPoint
    )

    $tibberTimestamp = $MetricPoint.payload.data.liveMeasurement.timestamp
    $time = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($tibberTimestamp), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm:ss')
    Write-Host "Live metrics at $time ($TimeZone):"

    # Get power metrics
    $timestamp = Get-GraphiteTimestamp -Timestamp $tibberTimestamp
    $powerMetrics = @()
    $global:fields | ForEach-Object {
        $value = $MetricPoint.payload.data.liveMeasurement.$_
        if (-Not $value) {
            $value = 0.0
        }

        if ($Detailed.IsPresent -Or $_ -like 'power*') {
            Write-Host "    $($_): $value"
        }
        $powerMetrics += @{
            name  = "tibber.live.$_"
            value = $value
        }
    }
    $powerMetrics = Get-GraphiteMetric -Metrics $powerMetrics -IntervalInSeconds 10 -Timestamp $timestamp

    # Get signal strength metrics
    $value = $MetricPoint.payload.data.liveMeasurement.signalStrength
    if ($value) {
        if ($Detailed.IsPresent) {
            Write-Host "    signalStrength: $value" -ForegroundColor DarkGray
        }
        $signalStrengthMetrics = Get-GraphiteMetric -Metrics @{
            name  = "tibber.live.signalStrength"
            value = $value
        } -Timestamp $timestamp -IntervalInSeconds 120 # 2 min
    }

    # Publish metrics to Graphite
    if ($env:GRAPHITE_PUBLISH -eq $true) {
        $columns = @(
            @{ label = 'Status'; expression = { $_.StatusCode } }
            @{ label = '|'; expression = { $_.StatusDescription } }
            @{ label = 'Published'; expression = { "$(($_.Content | ConvertFrom-Json).Published)" } }
            @{ label = 'Invalid'; expression = { "$(($_.Content | ConvertFrom-Json).Invalid)" } }
        )

        if ($powerMetrics) {
            Send-GraphiteMetric -Metrics $powerMetrics | Select-Object $columns | ForEach-Object { if ($Detailed.IsPresent) { $_ | Out-Host } }
        }
        if ($signalStrengthMetrics) {
            Send-GraphiteMetric -Metrics $signalStrengthMetrics | Select-Object $columns | ForEach-Object { if ($Detailed.IsPresent) { $_ | Out-Host } }
        }
    }
}

# Publish to Graphite
$env:GRAPHITE_PUBLISH = $false
if ($Publish.IsPresent) {
    $env:GRAPHITE_PUBLISH = $true
}
$global:fields = @(
    'power'
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

# Get the home Id
$myHome = (Get-TibberHome -Fields 'id', 'appNickname')[0]
$homeId = $myHome.id
Write-Host "Home ID for '$($myHome.appNickname)': $homeId"

# Connect WebSocket and register a subscription
$connection = Connect-TibberWebSocket
$subscription = Register-TibberLiveMeasurementSubscription -Connection $connection -HomeId $homeId -Fields ('timestamp', $global:fields, 'signalStrength')
Write-Host "New GraphQL subscription created: $($subscription.Id)"

# Read data stream
$readUntil = ([DateTime]::Now).AddHours(1) | Get-Date -Minute 2 -Second 0 -Millisecond 0
Write-Host "Reading metrics until $($readUntil.ToString('yyyy-MM-dd HH:mm:ss')) ($([TimeZoneInfo]::Local.Id))..."
$result = Read-TibberWebSocket -Connection $connection -Callback ${function:Send-LiveMetricsToGraphite} -ReadUntil $readUntil
Write-Host "Read $($result.NumberOfPackages) package(s) in $($result.ElapsedTimeInSeconds) seconds"

# Unregister subscription and close down the WebSocket connection
Unregister-TibberLiveMeasurementSubscription -Connection $connection -Subscription $subscription
Write-Host "GraphQL subscription stopped: $($subscription.Id)"
Disconnect-TibberWebSocket -Connection $connection
