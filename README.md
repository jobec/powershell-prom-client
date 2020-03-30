# PowerShell Prometheus Client

This Powershell module makes it easy to build a custom prometheus exporter based on PowerShell.

It's inspired and based on the Go client and works in sort of the same way.

## Usage

First, import this module

```powershell
Import-Module PrometheusExporter
```

Next, define metric descriptors. These describe your metrics, their labels, type and helptext.

```powershell
$TotalConnections   = New-MetricDescriptor -Name "rras_connections_total" -Type counter -Help "Total connections since server start"
$CurrentConnections = New-MetricDescriptor -Name "rras_connections" -Type gauge -Help "Current established connections" -Labels "protocol"
```

The scraping is done via a collector function which returns metrics. Below is an example of scraping RRAS server statistics.

```powershell
function collector () {
    $RRASConnections = Get-RemoteAccessConnectionStatistics
    $TotalCurrent = $RRASConnections.count
    $IKEv2 = @($RRASConnections | Where-Object {$_.TunnelType -eq "Ikev2"}).count
    $SSTP = @($RRASConnections | Where-Object {$_.TunnelType -eq "Sstp"}).count
    $Cumulative = (Get-RemoteAccessConnectionStatisticsSummary).TotalCumulativeConnections

    @(
        New-Metric -MetricDesc $TotalConnections -Value $Cumulative
        New-Metric -MetricDesc $CurrentConnections -Value $TotalCurrent -Labels ("all")
        New-Metric -MetricDesc $CurrentConnections -Value $IKEv2 -Labels ("ikev2")
        New-Metric -MetricDesc $CurrentConnections -Value $SSTP -Labels ("sstp")
    )
}
```

A final step is building a new exporter and starting it:

```powershell
$exp = New-PrometheusExporter -Port 9700
Register-Collector -Exporter $exp -Collector $Function:collector
$exp.Start()
```

If you now open http://localhost:9700 in your browser, you will see the metrics displayed.

```
# HELP rras_connections_total Total connections since server start
# TYPE rras_connections_total counter
rras_connections_total 8487
# HELP rras_connections Current established connections
# TYPE rras_connections gauge
rras_connections{protocol="all"} 563
rras_connections{protocol="ikev2"} 439
rras_connections{protocol="sstp"} 124
```