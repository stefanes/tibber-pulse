# Tibber Pulse

Scripts (and [Azure Pipelines](https://dev.azure.com/stefanes/tibber-pulse/_build)) for tracking energy prices and consumption using [the Tibber GraphQL API](https://developer.tibber.com/docs/reference).

## Installation

Before manually running the scripts in found in this repo you need to first install and setup the following PowerShell modules:

* [PSTibber](https://github.com/stefanes/PSTibber)
* [PSGraphite](https://github.com/stefanes/PSGraphite)

See [here](https://github.com/stefanes/PSTibber#authentication) and [here](https://github.com/stefanes/PSGraphite#authentication) for how to setup authentication.

## Usage examples

### Get today's or tomorrow's energy prices

The script `tibber-cost.ps1` will get tomorrow's (or today's) energy prices and publish the data in two Graphite series, `tibber.price.hourly` and `tibber.price.level`. The `tibber.price.level` series contains the price levels as defined [here](https://developer.tibber.com/docs/reference#pricelevel), translated into the following values:

| Price level      | Value |
| ---------------- | ----- |
| `VERY_CHEAP`     | 10    |
| `CHEAP`          | 20    |
| `NORMAL`         | 30    |
| `EXPENSIVE`      | 40    |
| `VERY_EXPENSIVE` | 50    |

Tomorrow's energy prices:

```powershell
PS> .\tibber-cost.ps1
Home ID for 'Vitahuset': 96a14971-525a-4420-aae9-e5aedaa129ff
New energy prices:
    1.2851 SEK at 09/10/2022 00:00:00 [VERY_CHEAP]
    1.2748 SEK at 09/10/2022 01:00:00 [VERY_CHEAP]
    1.2867 SEK at 09/10/2022 02:00:00 [VERY_CHEAP]
    1.3141 SEK at 09/10/2022 03:00:00 [VERY_CHEAP]
    1.3383 SEK at 09/10/2022 04:00:00 [VERY_CHEAP]
    1.3874 SEK at 09/10/2022 05:00:00 [VERY_CHEAP]
    1.2088 SEK at 09/10/2022 06:00:00 [VERY_CHEAP]
    1.4152 SEK at 09/10/2022 07:00:00 [VERY_CHEAP]
    2.6117 SEK at 09/10/2022 08:00:00 [CHEAP]
    3.2653 SEK at 09/10/2022 09:00:00 [CHEAP]
    3.5252 SEK at 09/10/2022 10:00:00 [NORMAL]
    3.6865 SEK at 09/10/2022 11:00:00 [NORMAL]
    3.796 SEK at 09/10/2022 12:00:00 [NORMAL]
    3.7967 SEK at 09/10/2022 13:00:00 [NORMAL]
    3.7967 SEK at 09/10/2022 14:00:00 [NORMAL]
    4.0556 SEK at 09/10/2022 15:00:00 [NORMAL]
    3.9302 SEK at 09/10/2022 16:00:00 [NORMAL]
    4.5522 SEK at 09/10/2022 17:00:00 [EXPENSIVE]
    4.7272 SEK at 09/10/2022 18:00:00 [EXPENSIVE]
    4.727 SEK at 09/10/2022 19:00:00 [EXPENSIVE]
    4.8493 SEK at 09/10/2022 20:00:00 [VERY_EXPENSIVE]
    4.4987 SEK at 09/10/2022 21:00:00 [EXPENSIVE]
    3.861 SEK at 09/10/2022 22:00:00 [NORMAL]
    2.8 SEK at 09/10/2022 23:00:00 [CHEAP]

Content           : {"Invalid":0,"Published":24,"ValidationErrors":{}}
...

Content           : {"Invalid":0,"Published":24,"ValidationErrors":{}}
...
```

Today's energy prices:

```powershell
PS> .\tibber-cost.ps1 -Today
Home ID for 'Vitahuset': 96a14971-525a-4420-aae9-e5aedaa129ff
New energy prices:
    1.1431 SEK at 09/09/2022 00:00:00 [VERY_CHEAP]
    1.1176 SEK at 09/09/2022 01:00:00 [VERY_CHEAP]
...
```
