﻿param (
    [switch] $Publish,
    [switch] $Detailed
)

function Send-LiveMetricsToGraphite {
    param (
        [Object] $MetricPoint
    )

    Write-Host "New live metrics at $($MetricPoint.payload.data.liveMeasurement.timestamp):"

    # Get power metrics
    $timestamp = Get-GraphiteTimestamp -Timestamp $MetricPoint.payload.data.liveMeasurement.timestamp
    $powerMetrics = @()
    @(
        'power'
        'powerProduction'
        'voltagePhase1'
        'voltagePhase2'
        'voltagePhase3'
        'currentL1'
        'currentL2'
        'currentL3'
    ) | ForEach-Object {
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
            Write-Host "    signalStrength: $value"
        }
        $signalStrengthMetrics = Get-GraphiteMetric -Metrics @{
            name  = "tibber.live.signalStrength"
            value = $value
        } -IntervalInSeconds 120 -Timestamp $timestamp
    }

    # Publish metrics to Graphite
    if ($env:GRAPHITE_PUBLISH -eq $true) {
        Send-GraphiteMetric -Metrics $powerMetrics | ForEach-Object { if ($Detailed.IsPresent) { $_ | Out-Host } }
        if ($signalStrengthMetrics) {
            Send-GraphiteMetric -Metrics $signalStrengthMetrics | ForEach-Object { if ($Detailed.IsPresent) { $_ | Out-Host } }
        }
    }
}

# Enable publish to Graphite
$env:GRAPHITE_PUBLISH = $false
if ($Publish.IsPresent) {
    $env:GRAPHITE_PUBLISH = $true
}

# Import required modules
# Import-Module -Name PSTibber -Force -PassThru
# Import-Module -Name PSGraphite -Force -PassThru
Invoke-Expression -Command $PSTibber
Invoke-Expression -Command $PSGraphite

# Get the home Id
$myHome = (Get-TibberHome -Fields 'id', 'appNickname')[0]
$homeId = $myHome.id
Write-Host "Home ID for '$($myHome.appNickname)': $homeId"

# Connect WebSocket and register a subscription
$connection = Connect-TibberWebSocket
$subscription = Register-TibberLiveConsumptionSubscription -Connection $connection -HomeId $homeId
Write-Host "New GraphQL subscription created: $($subscription.Id)"

# Read data stream
$result = Read-TibberWebSocket -Connection $connection -Callback ${function:Send-LiveMetricsToGraphite} -ReadUntil (([DateTime]::Now).AddHours(1) | Get-Date -Minute 0 -Second 0 -Millisecond 0)
Write-Host "Read $($result.NumberOfPackages) package(s) in $($result.ElapsedTimeInSeconds) seconds"

# Unregister subscription and close down the WebSocket connection
Unregister-TibberLiveConsumptionSubscription -Connection $connection -Subscription $subscription
Write-Host "New GraphQL subscription stopped: $($subscription.Id)"
Disconnect-TibberWebSocket -Connection $connection