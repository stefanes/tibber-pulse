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

    $addHours = 4
    $minute = 5
    $second = 0

    # if ($Now.Minute -lt 30) {
    #     $minute += 30
    #     $addHours = 0
    # }

    # Output time
    $Now.AddHours($addHours) | Get-Date -Minute $minute -Second $second -Millisecond 0
}

function Get-PriceInfoMetrics {
    param (
        [Object] $PriceInfo,
        [string] $TimeZone
    )

    # Price level & score
    $level = @{
        VERY_CHEAP     = 10
        CHEAP          = 20
        NORMAL         = 30
        EXPENSIVE      = 40
        VERY_EXPENSIVE = 50
    }
    $score = @{
        LOW    = -1
        MEDIUM = 0
        HIGH   = 1
    }

    # Make sure we do not have duplicates
    $PriceInfo = $PriceInfo | Sort-Object { $_.startsAt } -Unique

    # Calculate price thresholds
    $sum = 0
    $PriceInfo | ForEach-Object { $sum += $_.total }
    $avgPrice = $sum / 24
    $highTh = $avgPrice * 1.1
    $lowTh = $avgPrice * 0.9

    # Split into buckets compared to the average price +/- 10%
    $priceScoreLow = @() # expensive
    $priceScoreMedium = @() # normal
    $priceScoreHigh = @() # cheap
    $PriceInfo | ForEach-Object {
        if ($_.total -gt $highTh) {
            $priceScoreLow += $_
        }
        elseif ($_.total -lt $lowTh) {
            $priceScoreHigh += $_
        }
        else {
            $priceScoreMedium += $_
        }
    }

    # Constrict price info metrics
    Write-Host "Energy price ($TimeZone):"
    $PriceInfoMetrics = @()
    $PriceInfo | ForEach-Object {
        # Calculate price level
        switch ($_.level) {
            # https://developer.tibber.com/docs/reference#pricelevel
            'VERY_CHEAP' {
                $priceLevel = $level.VERY_CHEAP
                $color = [ConsoleColor]::DarkGreen
            }
            'CHEAP' {
                $priceLevel = $level.CHEAP
                $color = [ConsoleColor]::Green
            }
            'NORMAL' {
                $priceLevel = $level.NORMAL
                $color = [ConsoleColor]::Yellow
            }
            'EXPENSIVE' {
                $priceLevel = $level.EXPENSIVE
                $color = [ConsoleColor]::Red
            }
            'VERY_EXPENSIVE' {
                $priceLevel = $level.VERY_EXPENSIVE
                $color = [ConsoleColor]::DarkRed
            }
        }

        # Calculate price score
        if ($priceScoreLow -contains $_) {
            $priceScore = $score.LOW # expensive
        }
        elseif ($priceScoreMedium -contains $_) {
            $priceScore = $score.MEDIUM # normal
        }
        elseif ($priceScoreHigh -contains $_) {
            $priceScore = $score.HIGH # cheap
        }

        $tibberTimestamp = $_.startsAt
        $time = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($tibberTimestamp, [CultureInfo]::InvariantCulture), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm')
        $message = "    $($_.total.ToString('0.0000')) $($_.currency) at $time [level = $priceLevel] [score = $priceScore]"
        Write-Host $message -ForegroundColor $color

        $timestamp = Get-GraphiteTimestamp -Timestamp $tibberTimestamp
        $PriceInfoMetrics += @(
            @{
                price      = $_.total
                priceLevel = $priceLevel
                priceScore = $priceScore
                timestamp  = $timestamp
                time       = $tibberTimestamp
            }
        )
    }

    $PriceInfoMetrics
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
