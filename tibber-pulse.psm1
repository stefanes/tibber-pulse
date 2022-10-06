function Get-ReadUntil {
    param (
        [DateTime] $Now = [DateTime]::Now
    )

    $addHours = 1
    $minute = 2

    if ($Now.Minute -lt 30) {
        $minute = 32
        $addHours = 0
    }

    # Output date/time
    $Now.AddHours($addHours) | Get-Date -Minute $minute -Second 30 -Millisecond 0
}

function Send-LiveMetricsToGraphite {
    param (
        [Object] $MetricPoint,
        [bool] $Publish,
        [bool] $Detailed,
        [string] $TimeZone
    )

    $tibberTimestamp = $MetricPoint.payload.data.liveMeasurement.timestamp
    $time = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($tibberTimestamp), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm:ss')
    Write-Host "Live metrics at ${time}:"

    # Get power metrics
    $timestamp = Get-GraphiteTimestamp -Timestamp $tibberTimestamp
    $powerMetrics = @()
    $global:fields | ForEach-Object {
        $value = $MetricPoint.payload.data.liveMeasurement.$_
        if (-Not $value) {
            $value = 0.0
        }

        if ($Detailed -Or $_ -like 'power*') {
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
        if ($Detailed) {
            Write-Host "##[command]    signalStrength: $value" -ForegroundColor Blue
        }
        $signalStrengthMetrics = Get-GraphiteMetric -Metrics @{
            name  = "tibber.live.signalStrength"
            value = $value
        } -Timestamp $timestamp -IntervalInSeconds 120 # 2 min
    }

    # Publish metrics to Graphite
    if ($Publish) {
        $columns = @(
            @{ label = 'Status'; expression = { $_.StatusCode } }
            @{ label = '|'; expression = { $_.StatusDescription } }
            @{ label = 'Published'; expression = { "$(($_.Content | ConvertFrom-Json).Published)" } }
            @{ label = 'Invalid'; expression = { "$(($_.Content | ConvertFrom-Json).Invalid)" } }
        )

        if ($powerMetrics) {
            Send-GraphiteMetric -Metrics $powerMetrics | Select-Object $columns | ForEach-Object { if ($Detailed) { $_ | Out-Host } }
        }
        if ($signalStrengthMetrics) {
            Send-GraphiteMetric -Metrics $signalStrengthMetrics | Select-Object $columns | ForEach-Object { if ($Detailed) { $_ | Out-Host } }
        }
    }
    else {
        Write-Host "Note: Not publishing metrics to Graphite..." -ForegroundColor DarkGray
    }
}
