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
$consumption = Get-TibberConsumption -HomeId $homeId

Write-Host "New consumption from $($consumption.from) to $($consumption.to):"
Write-Host "    $($consumption.consumption * 1000) W"
Write-Host "    $($consumption.cost) $($consumption.currency)"

$timestamp = Get-GraphiteTimestamp -Timestamp $consumption.from
$consumptionMetrics = @(
    @{
        name  = "tibber.consumption.consumption"
        value = $consumption.consumption * 1000
    }
    @{
        name  = "tibber.consumption.cost"
        value = $consumption.cost
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

    $consumptionMetrics = Get-GraphiteMetric -Metrics $consumptionMetrics -Timestamp $timestamp -IntervalInSeconds 3600 # 1 hour
    Send-GraphiteMetric -Metrics $consumptionMetrics | Select-Object $columns | ForEach-Object { if ($Detailed.IsPresent) { $_ | Out-Host } }
}
