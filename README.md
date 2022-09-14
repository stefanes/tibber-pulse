# Tibber Pulse

Scripts and [pipelines](https://dev.azure.com/stefanes/tibber-pulse/_build) for tracking energy prices and consumption using [the Tibber GraphQL API](https://developer.tibber.com/docs/reference):

| Pipeline | Build status |
| ---------| ------------ |
| [tibber-pulse](https://dev.azure.com/stefanes/tibber-pulse/_build?definitionId=199&_a=summary)       | [![Build Status](https://dev.azure.com/stefanes/tibber-pulse/_apis/build/status/tibber-cost?branchName=main)](https://dev.azure.com/stefanes/tibber-pulse/_build/latest?definitionId=199&branchName=main) |
| [tibber-consumption](https://dev.azure.com/stefanes/tibber-pulse/_build?definitionId=201&_a=summary) | [![Build Status](https://dev.azure.com/stefanes/tibber-pulse/_apis/build/status/tibber-consumption?branchName=main)](https://dev.azure.com/stefanes/tibber-pulse/_build/latest?definitionId=201&branchName=main) |
| [tibber-live](https://dev.azure.com/stefanes/tibber-pulse/_build?definitionId=200&_a=summary)        | [![Build Status](https://dev.azure.com/stefanes/tibber-pulse/_apis/build/status/stefanes.tibber-pulse?branchName=main)](https://dev.azure.com/stefanes/tibber-pulse/_build/latest?definitionId=200&branchName=main) |

## Installation

Before manually running the scripts in found in this repo you need to first install and setup the following PowerShell modules:

* [PSTibber](https://github.com/stefanes/PSTibber)
* [PSGraphite](https://github.com/stefanes/PSGraphite)

See [here](https://github.com/stefanes/PSTibber#authentication) and [here](https://github.com/stefanes/PSGraphite#authentication) for how to setup authentication.

## Usage examples

### Get today's or tomorrow's energy prices

Use `tibber-cost.ps1` to get tomorrow's (or today's) energy prices and publish the data (if the `-Publish` switch is provided) in the following Graphite series:

| Graphite series       | Measurement   | Resolution |
| --------------------- | ------------- | ---------- |
| `tibber.price.hourly` | `total`       | 1 hour     |
| `tibber.price.level`  | _See below_   | 1 hour     |

The `tibber.price.level` series contains the price levels as defined [here](https://developer.tibber.com/docs/reference#pricelevel), translated into the following values:

| Price level      | Value |
| ---------------- | ----- |
| `VERY_CHEAP`     | 10    |
| `CHEAP`          | 20    |
| `NORMAL`         | 30    |
| `EXPENSIVE`      | 40    |
| `VERY_EXPENSIVE` | 50    |

Tomorrow's energy prices:

```powershell
PS> .\tibber-cost.ps1 -Publish
Home ID for 'Vitahuset': 96a14971-525a-4420-aae9-e5aedaa129ff
New energy prices:
    1.2851 SEK at 09/10/2022 00:00:00 [VERY_CHEAP]
    1.2748 SEK at 09/10/2022 01:00:00 [VERY_CHEAP]
    ...
    3.861 SEK at 09/10/2022 22:00:00 [NORMAL]
    2.8 SEK at 09/10/2022 23:00:00 [CHEAP]

Content           : {"Invalid":0,"Published":24,"ValidationErrors":{}}
...
StatusCode        : 200
StatusDescription : OK
...
RelationLink      : {}


Content           : {"Invalid":0,"Published":24,"ValidationErrors":{}}
...
StatusCode        : 200
StatusDescription : OK
...
RelationLink      : {}
```

Today's energy prices:

```powershell
PS> .\tibber-cost.ps1 -Today
Home ID for 'Vitahuset': 96a14971-525a-4420-aae9-e5aedaa129ff
New energy prices:
    1.1431 SEK at 09/09/2022 00:00:00 [VERY_CHEAP]
    1.1176 SEK at 09/09/2022 01:00:00 [VERY_CHEAP]
    ...
    2.2321 SEK at 09/09/2022 22:00:00 [VERY_CHEAP]
    1.1728 SEK at 09/09/2022 23:00:00 [VERY_CHEAP]
```

### Get billed consumption

Use `tibber-consumption.ps1` to get the billed consumption and publish the data (if the `-Publish` switch is provided) in the following Graphite series:

| Graphite series             | Measurement   | Resolution |
| ----------------------------| ------------- | ---------- |
| `tibber.hourly.consumption` | `consumption` | 1 hour     |
| `tibber.hourly.cost`        | `cost`        | 1 hour     |

### Get live measurements

Use `tibber-live.ps1` to get live measurements and publish the data (if the `-Publish` switch is provided) in the following Graphite series:

| Graphite series               | Measurement       | Resolution |
| ----------------------------- | ----------------- | ---------- |
| `tibber.live.power`           | `power`           | 10 seconds |
| `tibber.live.powerProduction` | `powerProduction` | 10 seconds |
| `tibber.live.voltagePhase1`   | `voltagePhase1`   | 10 seconds |
| `tibber.live.voltagePhase2`   | `voltagePhase2`   | 10 seconds |
| `tibber.live.voltagePhase3`   | `voltagePhase3`   | 10 seconds |
| `tibber.live.currentL1`       | `currentL1`       | 10 seconds |
| `tibber.live.currentL2`       | `currentL2`       | 10 seconds |
| `tibber.live.currentL3`       | `currentL3`       | 10 seconds |
| `tibber.live.signalStrength`  | `signalStrength`  | 2 minutes  |
