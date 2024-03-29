﻿[CmdletBinding()]
param (
    [switch] $Daily,
    [switch] $Publish,
    [string] $TimeZone = [TimeZoneInfo]::Local.Id
)

# Import required modules
Import-Module -Name PSTibber -Force -PassThru
Import-Module -Name PSGraphite -Force -PassThru
Import-Module -Name $PSScriptRoot\tibber-pulse.psd1 -Force -PassThru

# Set log verbosity
$dbgpref = $global:DebugPreference
$vrbpref = $global:VerbosePreference
$global:DebugPreference = $DebugPreference
$global:VerbosePreference = $VerbosePreference

# Get the home Id
$homeId = Get-HomeId

if (-Not $Daily.IsPresent) {
    # Get hourly consumption
    $hourlyConsumptionMetrics = @()
    Write-Host "Hourly consumption ($TimeZone)..."
    Get-TibberConsumption -HomeId $homeId -Last 24 | ForEach-Object {
        $tibberTimestamp = $_.from
        $from = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($tibberTimestamp, [CultureInfo]::InvariantCulture), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm')
        $to = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($_.to, [CultureInfo]::InvariantCulture), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm')
        Write-Host "From $from to ${to}:"
        if ($_.consumption) {
            Write-Host "    $($_.consumption * 1000) Wh"
            Write-Host "    $(($_.cost).ToString("0.00")) $($_.currency)"

            $timestamp = Get-GraphiteTimestamp -Timestamp $tibberTimestamp
            $hourlyConsumptionMetrics += @(
                @{
                    name  = "$env:GRAPHITE_METRICS_PREFIX.hourly.consumption"
                    value = $_.consumption * 1000
                    time  = $timestamp
                }
                @{
                    name  = "$env:GRAPHITE_METRICS_PREFIX.hourly.cost"
                    value = $_.cost
                    time  = $timestamp
                }
            )
        } else {
            Write-Host "    No data"
        }
    }
    $hourlyConsumptionMetrics = Get-GraphiteMetric -Metrics $hourlyConsumptionMetrics -IntervalInSeconds 3600 # 1 hour
} else {
    # Get daily consumption
    $dailyConsumption = Get-TibberConsumption -HomeId $homeId -Resolution DAILY
    if ($dailyConsumption) {
        $tibberTimestamp = $dailyConsumption.to
        $from = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($dailyConsumption.from, [CultureInfo]::InvariantCulture), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm')
        $to = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($tibberTimestamp, [CultureInfo]::InvariantCulture), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).AddSeconds(-1).ToString('yyyy-MM-dd HH:mm')
        Write-Host "Daily consumption from $from to $to ($TimeZone):"
        Write-Host "    $($dailyConsumption.consumption * 1000) Wh"
        Write-Host "    $(($dailyConsumption.cost).ToString("0.00")) $($dailyConsumption.currency)"
        Write-Host "    $(($dailyConsumption.cost / $dailyConsumption.consumption).ToString("0.00")) $($dailyConsumption.currency)/kWh"

        $timestamp = Get-GraphiteTimestamp -Timestamp $tibberTimestamp -AddSeconds -3600 # 1 hour
        $dailyConsumptionMetrics = Get-GraphiteMetric -Metrics @(
            @{
                name  = "$env:GRAPHITE_METRICS_PREFIX.daily.consumption"
                value = $dailyConsumption.consumption * 1000
                time  = $timestamp
            }
            @{
                name  = "$env:GRAPHITE_METRICS_PREFIX.daily.cost"
                value = $dailyConsumption.cost
                time  = $timestamp
            }
            @{
                name  = "$env:GRAPHITE_METRICS_PREFIX.daily.myPriceAvg"
                value = ($dailyConsumption.cost / $dailyConsumption.consumption)
                time  = $timestamp
            }
        ) -IntervalInSeconds 86400 # 24 hours
    } else {
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
} else {
    if ($hourlyConsumptionMetrics) {
        $hourlyConsumptionMetrics | Out-File -FilePath "$PSScriptRoot\tibber-consumption-hourly.json" -Force
    }
    if ($dailyConsumptionMetrics) {
        $dailyConsumptionMetrics | Out-File -FilePath "$PSScriptRoot\tibber-consumption-daily.json" -Force
    }
}

# Reset log verbosity
$global:DebugPreference = $dbgpref
$global:VerbosePreference = $vrbpref
