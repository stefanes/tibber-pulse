param (
    [switch] $Today
)

# Get home Id
$myHome = (Get-TibberHome -Fields 'id', 'appNickname')[0]
$homeId = $myHome.id
Write-Host "Home ID for '$($myHome.appNickname)': $homeId"

# Get price info
$priceInfoMetrics = @()
$priceLevelMetrics = @()
Write-Host "New energy prices:"
Get-TibberPriceInfo -HomeId $homeId -IncludeToday:$($Today.IsPresent) -IncludeTomorrow:$(-Not $Today.IsPresent) -ExcludeCurrent | ForEach-Object {
    $message = "    $($_.total) $($_.currency) at $($_.startsAt) [$($_.level)]"
    switch ($_.level) {
        # https://developer.tibber.com/docs/reference#pricelevel
        'NORMAL' {
            Write-Host $message -ForegroundColor Yellow
        }
        'CHEAP' {
            Write-Host $message
        }
        'VERY_CHEAP' {
            Write-Host $message -ForegroundColor Green
        }
        'EXPENSIVE' {
            Write-Host $message -ForegroundColor Red
        }
        'VERY_EXPENSIVE' {
            Write-Host $message -ForegroundColor DarkRed
        }
    }

    $metricDataPoint = @{
        value = $_.total
        time  = Get-GraphiteTimestamp -Timestamp $_.startsAt
    }
    $priceInfoMetrics += $metricDataPoint.Clone()
    $metricDataPoint.tags = @(
        "level=$($_.level)"
    )
    $priceLevelMetrics += $metricDataPoint
}

# # Send metrics to Graphite
# $priceInfoMetrics = Get-GraphiteMetric -Metrics $priceInfoMetrics -Name 'tibber.price.hourly' -IntervalInSeconds 3600 # 1 hour
# Send-GraphiteMetric -Metrics $priceInfoMetrics

# $priceLevelMetrics = Get-GraphiteMetric -Metrics $priceLevelMetrics -Name 'tibber.price.level' -IntervalInSeconds 3600 # 1 hour
# Send-GraphiteMetric -Metrics $priceLevelMetrics
