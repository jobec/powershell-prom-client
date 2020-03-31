# List of valid metric types
enum MetricType {
    counter
    gauge
    histogram
    summary
}

# Metric descriptor class
class MetricDesc {
    [String]     $Name
    [String]     $Help
    [MetricType] $Type
    [string[]]   $Labels

    MetricDesc([String] $Name, [MetricType] $Type, [String] $Help, [string[]] $Labels) {
        if (-Not $this.isValidName($Name)) {
            throw "Not a valid metric name: $Name"
        }
        foreach ($Label in $Labels) {
            if (-Not $this.isValidName($Label)) {
                throw "Not a valid label name: $Label"
            }
        }
        $this.Name = $Name
        $this.Type = $Type
        $this.Help = $Help -replace "[\r\n]+", " "  # Strip out new lines
        $this.Labels = $Labels
    }

    hidden [bool] isValidName([string] $Name) {
        # Notice the : is removed from the regex as those should not be used by exporters
        # according to the documentation
        return $Name -match "^[a-zA-Z_][a-zA-Z0-9_]*$"
    }
}

class Metric {
    [MetricDesc] $Descriptor
    [float]      $Value
    [string[]]   $Labels

    Metric([MetricDesc] $Descriptor, [Float] $Value, [string[]] $Labels) {
        $this.Descriptor = $Descriptor
        $this.Value = $Value
        $this.Labels = $Labels
    }

    [String] ToString() {
        $FinalLabels = [System.Collections.Generic.List[String]]::new()
        if ($this.Descriptor.Labels.Count -gt 0) {
            if ($this.Descriptor.Labels.Count -ne $this.Labels.Count) {
                throw "Less metric labels specified than there are labels in the descriptor"
            }
            for ($i = 0; $i -lt $this.Descriptor.Labels.Count; $i++) {
                $l = $this.Descriptor.Labels[$i]
                $v = $this.Labels[$i]
                $v = $v.Replace("\", "\\").Replace("""", "\""").Replace("`n", "\n")
                $FinalLabels.Add("$l=`"$v`"")
            }
            $StringLabels = $FinalLabels -join ","
            $StringLabels = "{$StringLabels}"
        } else {
            $StringLabels = ""
        }

        return $this.Descriptor.Name + $StringLabels + " " + $this.Value
    }
}

class Channel {
    $Metrics = [System.Collections.Generic.List[Metric]]::new()

    AddMetrics([Metric[]] $Metrics) {
        $this.Metrics.AddRange($Metrics)
    }

    [String] ToString() {
        $Lines = [System.Collections.Generic.List[String]]::new()
        $LastDescriptor = $null
        foreach ($m in $this.Metrics) {
            if ($m.Descriptor -ne $LastDescriptor) {
                $LastDescriptor = $m.Descriptor
                $name = $LastDescriptor.Name
                $help = $LastDescriptor.Help
                $type = $LastDescriptor.Type
                $Lines.Add("# HELP $name $help")
                $Lines.Add("# TYPE $name $type")
            }
            $Lines.Add([String]$m)
        }
        return $Lines -join "`n"
    }
}

class Exporter {
    $Collectors = [System.Collections.Generic.List[ScriptBlock]]::new()
    [UInt32] $Port

    Exporter ([UInt32] $Port) {
        $this.Port = $Port
    }

    Register ([ScriptBlock] $Collector) {
        $this.Collectors.Add($Collector)
    }

    [String] Collect () {
        $ch = [Channel]::new()
        foreach ($c in $this.Collectors) {
            $ch.AddMetrics($c.Invoke())
        }
        return [String]$ch
    }

    Start () {
        [Console]::TreatControlCAsInput = $True

        $Http = [System.Net.HttpListener]::new()
        $Prefix = 'http://+:{0}/' -f $this.Port
        $Http.Prefixes.Add($Prefix)
        $Http.Start()
        $Error.Clear()

        New-LogMessage -Msg ("Exporter started listening on $Prefix")

        try {
            while ($Http.IsListening) {
                $ContextAsync = $http.GetContextAsync()
                while (-not $ContextAsync.AsyncWaitHandle.WaitOne(200)) {
                    if ([console]::KeyAvailable) {
                        $key = [system.console]::readkey($true)
                        if (($key.modifiers -band [consolemodifiers]"control") -and ($key.key -eq "C")) {
                            Write-Warning "Quitting, user pressed control C..."
                            Return
                        }
                    }
                }
                $Context = $ContextAsync.GetAwaiter().GetResult()
                $Request = $Context.Request
                $Response = $Context.Response

                $Response.StatusCode = 200

                if ($Request.HttpMethod -eq "GET" -and $Request.Url.LocalPath -in ("/", "/metrics")) {
                    Try {
                        $PromResponse = $this.Collect()
                        $Response.AddHeader("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
                    } catch {
                        write-host $_
                        $Response.StatusCode = 500
                        $PromResponse = 'Internal Server Error'
                    }
                } else {
                    $Response.StatusCode = 404
                    $PromResponse = 'Page not found'
                }

                # return results
                $Buffer = [Text.Encoding]::UTF8.GetBytes($PromResponse)
                $Response.ContentLength64 = $Buffer.Length
                $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
                $Response.Close()

                $StatusCode = $Response.StatusCode
                $Method = $Request.HttpMethod
                $Path = $Request.Url.LocalPath
                if ($null -eq $Request.RemoteEndPoint) {
                    $RemoteAddr = "-"
                } else {
                    $RemoteAddr = $Request.RemoteEndPoint.ToString()
                }
                New-LogMessage -Msg "$RemoteAddr ""$Method $Path"" $StatusCode"
            }
        } finally {
            New-LogMessage -Msg "Stopping exporter."
            $Http.Stop()
            $Http.Close()
        }
    }
}

function New-LogMessage([String] $Msg) {
    Write-Host "$(Get-Date -Format o) $Msg"
}

function New-MetricDescriptor(
    [Parameter(Mandatory = $true)][String] $Name,
    [Parameter(Mandatory = $true)][MetricType] $Type,
    [Parameter(Mandatory = $true)][String] $Help,
    [string[]] $Labels
) {
    return [MetricDesc]::new($Name, $Type, $Help, $Labels)
}
function New-PrometheusExporter(
    [Parameter(Mandatory = $true)][uint32] $Port
) {
    return [Exporter]::new($Port)
}

function Register-Collector (
    [Parameter(Mandatory = $true)][Exporter] $Exporter,
    [Parameter(Mandatory = $true)][ScriptBlock] $Collector
) {
    $exporter.Register($Collector)
}

function New-Metric (
    [Parameter(Mandatory = $true)][MetricDesc] $MetricDesc,
    [Parameter(Mandatory = $true)][float] $Value,
    [string[]] $Labels
) {
    return [Metric]::new($MetricDesc, $Value, $Labels)
}

Export-ModuleMember -Function New-MetricDescriptor, New-PrometheusExporter, New-Metric, Register-Collector
