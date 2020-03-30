Import-Module PrometheusExporter

$TotalConnections = New-MetricDescriptor -Name "rras_connections_total" -Type counter -Help "Total connections since server start"
$CurrentConnections = New-MetricDescriptor -Name "rras_connections" -Type gauge -Help "Current established connections" -Labels "protocol"

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

$exp = New-PrometheusExporter -Port 8081
Register-Collector -Exporter $exp -Collector $Function:collector
$exp.Start()