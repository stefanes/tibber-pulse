[CmdletBinding(DefaultParameterSetName = 'Tomorrow')]
param (
    [string] $Path = '.'
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
    )
}

# Send metrics to Graphite
$priceInfoMetrics = Get-GraphiteMetric -Metrics $priceInfoMetrics -IntervalInSeconds 3600 # 1 hour
Send-Metrics $priceInfoMetrics

# Reset log verbosity
$global:DebugPreference = $dbgpref
$global:VerbosePreference = $vrbpref
