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
    # Get hourly production
    $hourlyProductionMetrics = @()
    Write-Host "Hourly production ($TimeZone)..."
    Get-TibberProduction -HomeId $homeId -Last 24 | ForEach-Object {
        $tibberTimestamp = $_.to
        $to = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($tibberTimestamp), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm')
        $from = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($_.from), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm')
        Write-Host "From $from to ${to}:"
        if ($_.production) {
            Write-Host "    $($_.production * 1000) W"
            Write-Host "    $(($_.profit).ToString("0.00")) $($_.currency)"

            $timestamp = Get-GraphiteTimestamp -Timestamp $tibberTimestamp
            $hourlyProductionMetrics += @(
                @{
                    name  = "tibber.hourly.production"
                    value = $_.production * 1000
                    time  = $timestamp
                }
                @{
                    name  = "tibber.hourly.profit"
                    value = $_.profit
                    time  = $timestamp
                }
            )
        }
        else {
            Write-Host "    No data"
        }
    }

    if ($hourlyProductionMetrics) {
        $hourlyProductionMetrics = Get-GraphiteMetric -Metrics $hourlyProductionMetrics -IntervalInSeconds 3600 # 1 hour
    }
    else {
        Write-Warning "No hourly production available"
    }
}
else {
    # Get daily production
    $dailyProduction = Get-TibberProduction -HomeId $homeId -Resolution DAILY
    if ($dailyProduction) {
        $tibberTimestamp = $dailyProduction.to
        $to = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($tibberTimestamp), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm')
        $from = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($dailyProduction.from), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm')
        Write-Host "Daily production from $from to $to ($TimeZone):"
        Write-Host "    $($dailyProduction.production * 1000) W"
        Write-Host "    $(($dailyProduction.profit).ToString("0.00")) $($dailyProduction.currency)"

        $timestamp = Get-GraphiteTimestamp -Timestamp $tibberTimestamp
        $dailyProductionMetrics = Get-GraphiteMetric -Metrics @(
            @{
                name  = "tibber.daily.production"
                value = $dailyProduction.production * 1000
            }
            @{
                name  = "tibber.daily.profit"
                value = $dailyProduction.profit
            }
        ) -Timestamp $timestamp -IntervalInSeconds 86400 # 24 hours
    }
    else {
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
}

# Reset Log verbosity
$global:DebugPreference = $dbgpref
$global:VerbosePreference = $vrbpref
