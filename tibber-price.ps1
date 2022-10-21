[CmdletBinding(DefaultParameterSetName = 'Tomorrow')]
param (
    [Parameter(Mandatory = $true, ParameterSetName = 'Today')]
    [switch] $Today,
    [Parameter(Mandatory = $true, ParameterSetName = 'Tomorrow')]
    [switch] $Tomorrow,
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
$homeId = Get-HomeId

# Get price info
$level = @{
    VERY_CHEAP     = 10
    CHEAP          = 20
    NORMAL         = 30
    EXPENSIVE      = 40
    VERY_EXPENSIVE = 50
}
$score = @{
    LOW    = -10
    MEDIUM = 0
    HIGH   = 10
}
$splat = @{
    HomeId          = $homeId
    IncludeToday    = $Today.IsPresent
    IncludeTomorrow = $Tomorrow.IsPresent
    ExcludeCurrent  = $true
    # Temporary workaround for missing price info
    Last            = 10
}
$priceInfo = Get-TibberPriceInfo @splat

# Sort by 'total' and split into buckets
$priceSorted = $priceInfo | Sort-Object -Property total -Descending
$priceScoreLow = $priceSorted[0..7] # expensive
$priceScoreMedium = $priceSorted[8..15] # normal
$priceScoreHigh = $priceSorted[16..23] # cheap

# Constrict price info metrics
Write-Host "Energy price ($TimeZone):"
$priceInfoMetrics = @()
$priceInfo | ForEach-Object {
    # Calculate price level
    switch ($_.level) {
        # https://developer.tibber.com/docs/reference#pricelevel
        'VERY_CHEAP' {
            $priceLevel = $level.VERY_CHEAP
            $color = [ConsoleColor]::DarkGreen
        }
        'CHEAP' {
            $priceLevel = $level.CHEAP
            $color = [ConsoleColor]::Green
        }
        'NORMAL' {
            $priceLevel = $level.NORMAL
            $color = [ConsoleColor]::Yellow
        }
        'EXPENSIVE' {
            $priceLevel = $level.EXPENSIVE
            $color = [ConsoleColor]::Red
        }
        'VERY_EXPENSIVE' {
            $priceLevel = $level.VERY_EXPENSIVE
            $color = [ConsoleColor]::DarkRed
        }
    }

    # Calculate price score
    if ($priceScoreLow -contains $_) {
        $priceScore = $score.LOW # expensive
    }
    elseif ($priceScoreMedium -contains $_) {
        $priceScore = $score.MEDIUM # normal
    }
    elseif ($priceScoreHigh -contains $_) {
        $priceScore = $score.HIGH # cheap
    }

    $tibberTimestamp = $_.startsAt
    $time = ([TimeZoneInfo]::ConvertTime([DateTime]::Parse($tibberTimestamp), [TimeZoneInfo]::FindSystemTimeZoneById($TimeZone))).ToString('yyyy-MM-dd HH:mm')
    $message = "    $($_.total.ToString('0.0000')) $($_.currency) at $time [level = $priceLevel] [score = $priceScore]"
    Write-Host $message -ForegroundColor $color

    $timestamp = Get-GraphiteTimestamp -Timestamp $tibberTimestamp
    $priceInfoMetrics += @(
        @{
            name  = "$env:GRAPHITE_METRICS_PREFIX.hourly.price"
            value = $_.total
            time  = $timestamp
        }
        @{
            name  = "$env:GRAPHITE_METRICS_PREFIX.hourly.priceLevel"
            value = $priceLevel
            time  = $timestamp
        }
        @{
            name  = "$env:GRAPHITE_METRICS_PREFIX.hourly.priceScore"
            value = $priceScore
            time  = $timestamp
        }
    )
}
$priceInfoMetrics = Get-GraphiteMetric -Metrics $priceInfoMetrics -IntervalInSeconds 3600 # 1 hour

# Send metrics to Graphite
if ($Publish.IsPresent) {
    if ($priceInfoMetrics) {
        Send-Metrics $priceInfoMetrics

        # Add build tag(s)
        if ($Today.IsPresent) {
            Write-Host "##[command][build.addbuildtag]today"
            Write-Host "##vso[build.addbuildtag]today"
        }
        if ($Tomorrow.IsPresent) {
            Write-Host "##[command][build.addbuildtag]tomorrow"
            Write-Host "##vso[build.addbuildtag]tomorrow"
        }
    }
}

# Reset Log verbosity
$global:DebugPreference = $dbgpref
$global:VerbosePreference = $vrbpref
