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

Write-Host "New consumption from $($hourlyConsumption.from) to $($hourlyConsumption.to):"
Write-Host "    $($hourlyConsumption.consumption * 1000) W"
Write-Host "    $($hourlyConsumption.cost) $($hourlyConsumption.currency)"

$timestamp = Get-GraphiteTimestamp -Timestamp $hourlyConsumption.from
$hourlyConsumptionMetrics = @(
    @{
        name  = "tibber.hourly.consumption"
        value = $hourlyConsumption.consumption * 1000
    }
    @{
        name  = "tibber.hourly.cost"
        value = $hourlyConsumption.cost
    }
)

# Send metrics to Graphite
if ($Publish.IsPresent) {
    $columns = @(
        @{ label = 'Status'; expression = { $_.StatusCode } }
        @{ label = '|'; expression = { $_.StatusDescription } }
        @{ label = 'Published/Invalid'; expression = { "$(($_.Content | ConvertFrom-Json).Published)/$(($_.Content | ConvertFrom-Json).Invalid)" } }
        @{ label = 'Length'; expression = { $_.RawContentLength } }
    )

    $hourlyConsumptionMetrics = Get-GraphiteMetric -Metrics $hourlyConsumptionMetrics -Timestamp $timestamp -IntervalInSeconds 3600 # 1 hour
    Send-GraphiteMetric -Metrics $hourlyConsumptionMetrics | Select-Object $columns | ForEach-Object { if ($Detailed.IsPresent) { $_ | Out-Host } }
}
