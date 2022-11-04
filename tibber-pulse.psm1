function Get-HomeId {
    $myHome = (Get-TibberHome -Fields 'id', 'appNickname')[0]
    $homeId = $myHome.id
    Write-Host "Home ID for '$($myHome.appNickname)': $homeId"

    # Output object
    $homeId
}

function Get-ReadUntil {
    param (
        [DateTime] $Now = [DateTime]::Now
    )

    $addHours = 1
    $minute = 5
    $second = 0

    if ($Now.Minute -lt 30) {
        $minute += 30
        $addHours = 0
    }

    # Output time
    $Now.AddHours($addHours) | Get-Date -Minute $minute -Second $second -Millisecond 0
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

    Send-GraphiteMetric -Metrics $Metrics | Select-Object $columns | ForEach-Object { $_ | Out-Host }
    # Write-Host "Would publish metrics to Graphite: $Metrics" -ForegroundColor DarkYellow
}

function Send-LiveMetricsToGraphite {
    param (
        [Object] $MetricPoint,
        [bool] $Publish,
        [string] $TimeZone
    )

    $tibberTimestamp = $MetricPoint.payload.data.liveMeasurement.timestamp
    $time = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($tibberTimestamp, [CultureInfo]::InvariantCulture), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm:ss')
    Write-Host "Live metrics at ${time}:"

    # Get power metrics
    $timestamp = Get-GraphiteTimestamp -Timestamp $tibberTimestamp
    $powerMetrics = @()
    $global:fields | ForEach-Object {
        $value = $MetricPoint.payload.data.liveMeasurement.$_
        if (-Not $value) {
            $value = 0.0
        }

        Write-Host "    $($_): $value"
        $powerMetrics += @{
            name  = "$env:GRAPHITE_METRICS_PREFIX.live.$_"
            value = $value
            time  = $timestamp
        }
    }
    $powerMetrics = Get-GraphiteMetric -Metrics $powerMetrics -IntervalInSeconds 10

    # Get signal strength metrics
    $value = $MetricPoint.payload.data.liveMeasurement.signalStrength
    if ($value) {
        Write-Host "##[command]    signalStrength: $value" -ForegroundColor Blue
        $signalStrengthMetrics = Get-GraphiteMetric -Metrics @{
            name  = "$env:GRAPHITE_METRICS_PREFIX.live.signalStrength"
            value = $value
            time  = $timestamp
        } -IntervalInSeconds 120 # 2 min
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

function Wait-KeyPress {
    param (
        [Alias('Timeout')]
        [int] $TimeoutInSeconds = -1 # indefinately
    )

    # Keep session alive for a set time, or until space key is pressed
    $spaceKey = 0x20 # space
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $waitString = "for $TimeoutInSeconds seconds"
    if ($TimeoutInSeconds -eq -1) {
        $waitString = "indefinately"
    }
    Write-Host "Waiting $waitString, press space to exit..."
    while ($TimeoutInSeconds -eq -1 -Or $timer.Elapsed.TotalSeconds -lt $TimeoutInSeconds) {
        if ($host.UI.RawUI.KeyAvailable) {
            $pressedKey = $host.ui.RawUI.ReadKey("NoEcho,IncludeKeyUp")
            if ($pressedKey.VirtualKeyCode -eq $spaceKey) {
                Write-Host "Space key pressed, exiting" -ForegroundColor DarkGray
                break
            }
        }
        Start-Sleep -Seconds 3
    }
}

# Set default environment variables
$tibberDemoToken = '5K4MVS-OjfWhK_4yrjOlFe1F6kJXPVf7eQYggo8ebAE'
if (-Not $env:TIBBER_ACCESS_TOKEN) {
    $env:TIBBER_ACCESS_TOKEN = $tibberDemoToken
    Write-Warning "TIBBER_ACCESS_TOKEN set to '$tibberDemoToken'"
}

$tibberDemoMetrics = 'tibber-demo'
$tibberDefaultMetrics = 'tibber'
if ($env:TIBBER_ACCESS_TOKEN -eq $tibberDemoToken) {
    $env:GRAPHITE_METRICS_PREFIX = $tibberDemoMetrics
    Write-Warning "Using demo token, GRAPHITE_METRICS_PREFIX set to '$tibberDemoMetrics'"
}
else {
    if (-Not $env:GRAPHITE_METRICS_PREFIX -Or $env:GRAPHITE_METRICS_PREFIX -eq $tibberDemoMetrics) {
        $env:GRAPHITE_METRICS_PREFIX = $tibberDefaultMetrics
        Write-Warning "GRAPHITE_METRICS_PREFIX set to '$tibberDefaultMetrics'"
    }
}
