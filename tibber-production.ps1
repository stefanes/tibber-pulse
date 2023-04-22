[CmdletBinding()]
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
    # Get hourly production
    $hourlyProductionMetrics = @()
    Write-Host "Hourly production ($TimeZone)..."
    Get-TibberProduction -HomeId $homeId -Last 24 | ForEach-Object {
        $tibberTimestamp = $_.from
        $from = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($tibberTimestamp, [CultureInfo]::InvariantCulture), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm')
        $to = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($_.to, [CultureInfo]::InvariantCulture), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm')
        Write-Host "From $from to ${to}:"
        if ($_.production) {
            Write-Host "    $($_.production * 1000) Wh"
            Write-Host "    $(($_.profit).ToString("0.00")) $($_.currency)"

            $timestamp = Get-GraphiteTimestamp -Timestamp $tibberTimestamp
            $hourlyProductionMetrics += @(
                @{
                    name  = "$env:GRAPHITE_METRICS_PREFIX.hourly.production"
                    value = $_.production * 1000
                    time  = $timestamp
                }
                @{
                    name  = "$env:GRAPHITE_METRICS_PREFIX.hourly.profit"
                    value = $_.profit
                    time  = $timestamp
                }
            )
        } else {
            Write-Host "    No data"
        }
    }

    if ($hourlyProductionMetrics) {
        $hourlyProductionMetrics = Get-GraphiteMetric -Metrics $hourlyProductionMetrics -IntervalInSeconds 3600 # 1 hour
    } else {
        Write-Warning "No hourly production available"
    }
} else {
    # Get daily production
    $dailyProduction = Get-TibberProduction -HomeId $homeId -Resolution DAILY
    if ($dailyProduction) {
        $tibberTimestamp = $dailyProduction.to
        $from = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($dailyProduction.from, [CultureInfo]::InvariantCulture), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm')
        $to = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($tibberTimestamp, [CultureInfo]::InvariantCulture), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).AddMinutes(-1).ToString('yyyy-MM-dd HH:mm')
        Write-Host "Daily production from $from to $to ($TimeZone):"
        Write-Host "    $($dailyProduction.production * 1000) Wh"
        Write-Host "    $(($dailyProduction.profit).ToString("0.00")) $($dailyProduction.currency)"
        Write-Host "    $(($dailyProduction.profit / $dailyProduction.production).ToString("0.00")) $($dailyProduction.currency)/kWh"

        $timestamp = Get-GraphiteTimestamp -Timestamp $tibberTimestamp -AddSeconds -3600 # 1 hour
        $dailyProductionMetrics = Get-GraphiteMetric -Metrics @(
            @{
                name  = "$env:GRAPHITE_METRICS_PREFIX.daily.production"
                value = $dailyProduction.production * 1000
                time  = $timestamp
            }
            @{
                name  = "$env:GRAPHITE_METRICS_PREFIX.daily.profit"
                value = $dailyProduction.profit
                time  = $timestamp
            }
            @{
                name  = "$env:GRAPHITE_METRICS_PREFIX.daily.myProfitAvg"
                value = ($dailyProduction.profit / $dailyProduction.production)
                time  = $timestamp
            }
        ) -IntervalInSeconds 86400 # 24 hours
    } else {
        Write-Warning "No daily production available"
    }
}

# Send metrics to Graphite
if ($Publish.IsPresent) {
    if ($hourlyProductionMetrics) {
        Send-Metrics $hourlyProductionMetrics

        # Add build tag(s)
        Write-Host "##[command][build.addbuildtag]hourly"
        Write-Host "##vso[build.addbuildtag]hourly"
    }
    if ($dailyProductionMetrics) {
        Send-Metrics $dailyProductionMetrics

        # Add build tag(s)
        Write-Host "##[command][build.addbuildtag]daily"
        Write-Host "##vso[build.addbuildtag]daily"
    }
} else {
    if ($hourlyProductionMetrics) {
        $hourlyProductionMetrics | Out-File -FilePath "$PSScriptRoot\tibber-production-hourly.json" -Force
    }
    if ($dailyProductionMetrics) {
        $dailyProductionMetrics | Out-File -FilePath "$PSScriptRoot\tibber-production-daily.json" -Force
    }
}

# Reset log verbosity
$global:DebugPreference = $dbgpref
$global:VerbosePreference = $vrbpref
