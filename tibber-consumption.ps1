param (
    [switch] $Daily,
    [switch] $IncludePrice,
    [switch] $Now,
    [switch] $Today,
    [switch] $Tomorrow,
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

if (-Not $Daily.IsPresent) {
    # Get hourly consumption
    $hourlyConsumptionMetrics = @()
    Get-TibberConsumption -HomeId $homeId -Last 24 | ForEach-Object {
        Write-Host "Hourly consumption from $($_.from) to $($_.to):"
        if ($_.consumption) {
            Write-Host "    $($_.consumption * 1000) W"
            Write-Host "    $(($_.cost).ToString("0.00")) $($_.currency)"

            $timestamp = Get-GraphiteTimestamp -Timestamp $_.to
            $hourlyConsumptionMetrics += @(
                @{
                    name  = "tibber.hourly.consumption"
                    value = $_.consumption * 1000
                    time  = $timestamp
                }
                @{
                    name  = "tibber.hourly.cost"
                    value = $_.cost
                    time  = $timestamp
                }
            )
        }
        else {
            Write-Host "    No data (yet)..."
        }
    }
    $hourlyConsumptionMetrics = Get-GraphiteMetric -Metrics $hourlyConsumptionMetrics -IntervalInSeconds 3600 # 1 hour
}
else {
    # Get daily consumption
    $dailyConsumption = Get-TibberConsumption -HomeId $homeId -Resolution DAILY
    Write-Host "Daily consumption from $($dailyConsumption.from) to $($dailyConsumption.to):"
    Write-Host "    $($dailyConsumption.consumption * 1000) W"
    Write-Host "    $(($dailyConsumption.cost).ToString("0.00")) $($dailyConsumption.currency)"

    $timestamp = Get-GraphiteTimestamp -Timestamp $dailyConsumption.to
    if ($dailyConsumption) {
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
        Write-Warning "No daily consumption available"
    }
}

# Get energy price
if ($IncludePrice.IsPresent) {
    $splat = @{
        Now      = $Now.IsPresent
        Today    = $Today.IsPresent
        Tomorrow = $Tomorrow.IsPresent
        Publish  = $Publish
        Detailed = $Detailed
    }
    & $PSScriptRoot\tibber-price.ps1 @splat
}

# Send metrics to Graphite
if ($Publish.IsPresent) {
    $columns = @(
        @{ label = 'Status'; expression = { $_.StatusCode } }
        @{ label = '|'; expression = { $_.StatusDescription } }
        @{ label = 'Published'; expression = { "$(($_.Content | ConvertFrom-Json).Published)" } }
        @{ label = 'Invalid'; expression = { "$(($_.Content | ConvertFrom-Json).Invalid)" } }
    )

    if ($hourlyConsumptionMetrics) {
        Send-GraphiteMetric -Metrics $hourlyConsumptionMetrics | Select-Object $columns | ForEach-Object { if ($Detailed.IsPresent) { $_ | Out-Host } }
        Write-Host "##[command][build.addbuildtag]hourly"
        Write-Host "##vso[build.addbuildtag]hourly"
    }
    if ($dailyConsumptionMetrics) {
        Send-GraphiteMetric -Metrics $dailyConsumptionMetrics | Select-Object $columns | ForEach-Object { if ($Detailed.IsPresent) { $_ | Out-Host } }
        Write-Host "##[command][build.addbuildtag]daily"
        Write-Host "##vso[build.addbuildtag]daily"
    }
}
