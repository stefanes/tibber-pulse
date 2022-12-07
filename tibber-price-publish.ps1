[CmdletBinding(DefaultParameterSetName = 'Tomorrow')]
param (
    [string] $Path = '.',
    [switch] $Publish,
    [string] $TimeZone = [TimeZoneInfo]::Local.Id
)

# Import required modules
Import-Module -Name PSGraphite -Force -PassThru
Import-Module -Name $PSScriptRoot\tibber-pulse.psd1 -Force -PassThru

# Set Log verbosity
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
