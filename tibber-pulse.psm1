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

    # Output time
    $Now.AddHours($addHours) | Get-Date -Minute $minute -Second 30 -Millisecond 0
}

function Send-Metrics {
    param (
        [Parameter(Position = 0)]
        [string] $Metrics
    )
    $columns = '*'
    if ($DebugPreference -eq [Management.Automation.ActionPreference]::SilentlyContinue) {
        $columns = @(
            @{ label = 'Status'; expression = { $_.StatusCode } }
            @{ label = '|'; expression = { $_.StatusDescription } }
            @{ label = 'Published'; expression = { "$(($_.Content | ConvertFrom-Json).Published)" } }
            @{ label = 'Invalid'; expression = { "$(($_.Content | ConvertFrom-Json).Invalid)" } }
        )
    }

    $outHost = $VerbosePreference -ne [Management.Automation.ActionPreference]::SilentlyContinue -Or $DebugPreference -ne [Management.Automation.ActionPreference]::SilentlyContinue
    Send-GraphiteMetric -Metrics $Metrics | Select-Object $columns | ForEach-Object { if ($outHost) { $_ | Out-Host } }
}

function Send-LiveMetricsToGraphite {
    param (
        [Object] $MetricPoint,
        [bool] $Publish,
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

        if ($VerbosePreference -ne [Management.Automation.ActionPreference]::SilentlyContinue -Or $_ -like 'power*') {
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
        if ($VerbosePreference -ne [Management.Automation.ActionPreference]::SilentlyContinue) {
            Write-Host "##[command]    signalStrength: $value" -ForegroundColor Blue
        }
        $signalStrengthMetrics = Get-GraphiteMetric -Metrics @{
            name  = "tibber.live.signalStrength"
            value = $value
        } -Timestamp $timestamp -IntervalInSeconds 120 # 2 min
    }

    # Publish metrics to Graphite
    if ($Publish) {
        if ($powerMetrics) {
            Send-Metrics $powerMetrics
        }
        if ($signalStrengthMetrics) {
            Send-Metrics $signalStrengthMetrics
        }
    }
    else {
        Write-Host "Note: Not publishing metrics to Graphite..." -ForegroundColor DarkGray
    }
}
