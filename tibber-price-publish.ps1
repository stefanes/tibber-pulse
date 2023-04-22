[CmdletBinding(DefaultParameterSetName = 'Tomorrow')]
param (
    [string] $Path = '.',
    [switch] $SkipPublish
)

# Import required modules
Import-Module -Name PSGraphite -Force -PassThru
Import-Module -Name $PSScriptRoot\tibber-pulse.psd1 -Force -PassThru

# Set log verbosity
$dbgpref = $global:DebugPreference
$vrbpref = $global:VerbosePreference
$global:DebugPreference = $DebugPreference
$global:VerbosePreference = $VerbosePreference

$priceInfo = Get-Content -Raw -Path "$Path\tibber-price.json" | ConvertFrom-Json

$priceInfoMetrics = @()
$priceInfo | ForEach-Object {
    if ($_.price) {
        $priceInfoMetrics += @(
            @{
                name  = "$env:GRAPHITE_METRICS_PREFIX.hourly.price"
                value = $_.price
                time  = $_.timestamp
            }
            @{
                name  = "$env:GRAPHITE_METRICS_PREFIX.hourly.priceLevel"
                value = $_.priceLevel
                time  = $_.timestamp
            }
            @{
                name  = "$env:GRAPHITE_METRICS_PREFIX.hourly.priceScore"
                value = $_.priceScore
                time  = $_.timestamp
            }
            @{
                name  = "$env:GRAPHITE_METRICS_PREFIX.hourly.priceAvg"
                value = $_.priceAvg
                time  = $_.timestamp
            }
        )
    }

    if ($_.priceAvgToday) {
        $priceInfoMetrics += @(
            @{
                name     = "$env:GRAPHITE_METRICS_PREFIX.daily.priceAvg"
                value    = $_.priceAvgToday
                time     = $_.timestamp
                interval = 86400 # 1 day
            }
        )
    }

    if ($_.priceAvgTomorrow) {
        $priceInfoMetrics += @(
            @{
                name     = "$env:GRAPHITE_METRICS_PREFIX.daily.priceAvg"
                value    = $_.priceAvgTomorrow
                time     = $_.timestamp
                interval = 86400 # 1 day
            }
        )
    }
}

$priceInfoMetrics = Get-GraphiteMetric -Metrics $priceInfoMetrics -IntervalInSeconds 3600 # 1 hour
if (-Not $SkipPublish.IsPresent) {
    # Send metrics to Graphite
    Send-Metrics $priceInfoMetrics
} else {
    $priceInfoMetrics | Out-File -FilePath "$PSScriptRoot\tibber-price-publish.json" -Force
}

# Reset log verbosity
$global:DebugPreference = $dbgpref
$global:VerbosePreference = $vrbpref
