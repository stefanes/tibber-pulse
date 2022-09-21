param (
    [switch] $Today,
    [switch] $Publish,
    [switch] $Detailed
)

# Import required modules
Import-Module -Name PSTibber -Force -PassThru
Import-Module -Name PSGraphite -Force -PassThru

# Get the home Id
$myHome = (Get-TibberHome -Fields 'id', 'appNickname')[0]
$homeId = $myHome.id
Write-Host "Home ID for '$($myHome.appNickname)': $homeId"

# Get price info
$priceInfoMetrics = @()
$priceLevelMetrics = @()
$levels = @{
    VERY_CHEAP     = 10
    CHEAP          = 20
    NORMAL         = 30
    EXPENSIVE      = 40
    VERY_EXPENSIVE = 50
}
Write-Host "New energy prices:"
Get-TibberPriceInfo -HomeId $homeId -IncludeToday:$($Today.IsPresent) -IncludeTomorrow:$(-Not $Today.IsPresent) -ExcludeCurrent | ForEach-Object {
    $message = "    $($_.total) $($_.currency) at $($_.startsAt) [$($_.level)]"
    switch ($_.level) {
        # https://developer.tibber.com/docs/reference#pricelevel
        'VERY_CHEAP' {
            Write-Host $message -ForegroundColor Green
        }
        'CHEAP' {
            Write-Host $message
        }
        'NORMAL' {
            Write-Host $message -ForegroundColor Yellow
        }
        'EXPENSIVE' {
            Write-Host $message -ForegroundColor Red
        }
        'VERY_EXPENSIVE' {
            Write-Host $message -ForegroundColor DarkRed
        }
    }

    $timestamp = Get-GraphiteTimestamp -Timestamp $_.startsAt
    $priceInfoMetrics += @{
        value = $_.total
        time  = $timestamp
    }
    $priceLevelMetrics += @{
        value = $levels.$($_.level)
        time  = $timestamp
    }
}

# Send metrics to Graphite
if ($Publish.IsPresent) {
    $columns = @(
        @{ label = 'Status'; expression = { $_.StatusCode } }
        @{ label = '|'; expression = { $_.StatusDescription } }
        @{ label = 'Published'; expression = { "$(($_.Content | ConvertFrom-Json).Published)" } }
        @{ label = 'Invalid'; expression = { "$(($_.Content | ConvertFrom-Json).Invalid)" } }
    )

    if ($priceInfoMetrics) {
        $priceInfoMetrics = Get-GraphiteMetric -Metrics $priceInfoMetrics -Name 'tibber.hourly.price' -IntervalInSeconds 3600 # 1 hour
        Send-GraphiteMetric -Metrics $priceInfoMetrics | Select-Object $columns | ForEach-Object { if ($Detailed.IsPresent) { $_ | Out-Host } }
    }
    if ($priceLevelMetrics) {
        $priceLevelMetrics = Get-GraphiteMetric -Metrics $priceLevelMetrics -Name 'tibber.hourly.priceLevel' -IntervalInSeconds 3600 # 1 hour
        Send-GraphiteMetric -Metrics $priceLevelMetrics | Select-Object $columns | ForEach-Object { if ($Detailed.IsPresent) { $_ | Out-Host } }
    }
}
