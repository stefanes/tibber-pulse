[CmdletBinding()]
param (
    [switch] $Daily,
    [switch] $Publish,
    [string] $TimeZone = [TimeZoneInfo]::Local.Id
)

# Import required modules
Import-Module -Name PSTibber -Force -PassThru
Import-Module -Name PSGraphite -Force -PassThru
Import-Module -Name $PSScriptRoot\tibber-pulse.psm1 -Force -PassThru

# Set Log verbosity
$dbgpref = $global:DebugPreference
$vrbpref = $global:VerbosePreference
$global:DebugPreference = $DebugPreference
$global:VerbosePreference = $VerbosePreference

# Get the home Id
$myHome = (Get-TibberHome -Fields 'id', 'appNickname')[0]
$homeId = $myHome.id
Write-Host "Home ID for '$($myHome.appNickname)': $homeId"

if (-Not $Daily.IsPresent) {
    # Get hourly consumption
    $hourlyConsumptionMetrics = @()
    Write-Host "Hourly consumption ($TimeZone)..."
    Get-TibberConsumption -HomeId $homeId -Last 24 | ForEach-Object {
        $tibberTimestamp = $_.to
        $to = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($tibberTimestamp), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm')
        $from = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($_.from), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm')
        Write-Host "From $from to ${to}:"
        if ($_.consumption) {
            Write-Host "    $($_.consumption * 1000) W"
            Write-Host "    $(($_.cost).ToString("0.00")) $($_.currency)"

            $timestamp = Get-GraphiteTimestamp -Timestamp $tibberTimestamp
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
            Write-Host "    No data"
        }
    }
    $hourlyConsumptionMetrics = Get-GraphiteMetric -Metrics $hourlyConsumptionMetrics -IntervalInSeconds 3600 # 1 hour
}
else {
    # Get daily consumption
    $dailyConsumption = Get-TibberConsumption -HomeId $homeId -Resolution DAILY
    if ($dailyConsumption) {
        $tibberTimestamp = $dailyConsumption.to
        $to = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($tibberTimestamp), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm')
        $from = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($dailyConsumption.from), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm')
        Write-Host "Daily consumption from $from to $to ($TimeZone):"
        Write-Host "    $($dailyConsumption.consumption * 1000) W"
        Write-Host "    $(($dailyConsumption.cost).ToString("0.00")) $($dailyConsumption.currency)"

        $timestamp = Get-GraphiteTimestamp -Timestamp $tibberTimestamp
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

# Send metrics to Graphite
if ($Publish.IsPresent) {
    if ($hourlyConsumptionMetrics) {
        Send-Metrics $hourlyConsumptionMetrics

        # Add build tag(s)
        Write-Host "##[command][build.addbuildtag]hourly"
        Write-Host "##vso[build.addbuildtag]hourly"
    }
    if ($dailyConsumptionMetrics) {
        Send-Metrics $dailyConsumptionMetrics

        # Add build tag(s)
        Write-Host "##[command][build.addbuildtag]daily"
        Write-Host "##vso[build.addbuildtag]daily"
    }
}

# Reset Log verbosity
$global:DebugPreference = $dbgpref
$global:VerbosePreference = $vrbpref
