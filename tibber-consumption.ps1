param (
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

# Get hourly consumption
$hourlyConsumption = Get-TibberConsumption -HomeId $homeId

Write-Host "New hourly consumption from $($hourlyConsumption.from) to $($hourlyConsumption.to):"
Write-Host "    $($hourlyConsumption.consumption * 1000) W"
Write-Host "    $($hourlyConsumption.cost) $($hourlyConsumption.currency)"

$timestamp = Get-GraphiteTimestamp -Timestamp $hourlyConsumption.to
$hourlyConsumptionMetrics = Get-GraphiteMetric -Metrics @(
    @{
        name  = "tibber.hourly.consumption"
        value = $hourlyConsumption.consumption * 1000
    }
    @{
        name  = "tibber.hourly.cost"
        value = $hourlyConsumption.cost
    }
) -Timestamp $timestamp -IntervalInSeconds 3600 # 1 hour

# Get daily consumption
$from = ([DateTime]::Now).AddDays(-1) | Get-Date -Hour 0 -Minute 0 -Second 0 -Millisecond 0
$to = [DateTime]::Now | Get-Date -Hour 0 -Minute 0 -Second 0 -Millisecond 0
if (-Not (Find-GraphiteMetric -Metric 'tibber.daily.consumption' -From $from -To $to)) {
    $dailyConsumption = Get-TibberConsumption -HomeId $homeId -Resolution DAILY

    Write-Host "New daily consumption from $($dailyConsumption.from) to $($dailyConsumption.to):"
    Write-Host "    $($dailyConsumption.consumption * 1000) W"
    Write-Host "    $($dailyConsumption.cost) $($dailyConsumption.currency)"

    $timestamp = Get-GraphiteTimestamp -Timestamp $dailyConsumption.to
    $dailyConsumptionMetrics = Get-GraphiteMetric -Metrics @(
        @{
            name  = "tibber.daily.consumption"
            value = $dailyConsumption.consumption * 1000
        }
        @{
            name  = "tibber.daily.cost"
            value = $dailyConsumption.cost
        }
    ) -Timestamp $timestamp -IntervalInSeconds 86400 # 24 hours
}
else {
    Write-Host "Daily consumption already published"
}

# Send metrics to Graphite
if ($Publish.IsPresent) {
    $columns = @(
        @{ label = 'Status'; expression = { $_.StatusCode } }
        @{ label = '|'; expression = { $_.StatusDescription } }
        @{ label = 'Published/Invalid'; expression = { "$(($_.Content | ConvertFrom-Json).Published)/$(($_.Content | ConvertFrom-Json).Invalid)" } }
        @{ label = 'Length'; expression = { $_.RawContentLength } }
    )

    Send-GraphiteMetric -Metrics $hourlyConsumptionMetrics | Select-Object $columns | ForEach-Object { if ($Detailed.IsPresent) { $_ | Out-Host } }
    if ($dailyConsumptionMetrics) {
        Send-GraphiteMetric -Metrics $dailyConsumptionMetrics | Select-Object $columns | ForEach-Object { if ($Detailed.IsPresent) { $_ | Out-Host } }
    }
}
