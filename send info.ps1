param(
  [string]$Webhook = "https://n8n.srv1034252.hstgr.cloud/webhook/079ca5a3-ceac-41d9-bdb7-a59f114a89f4",
  [int]$IntervalSec = 120
)

$ErrorActionPreference = 'SilentlyContinue'
try {
  $sp = [Net.ServicePointManager]::SecurityProtocol
  [Net.ServicePointManager]::SecurityProtocol = $sp -bor [Net.SecurityProtocolType]::Tls12
} catch {}

# --- Win32 interop para ventana activa ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FGW {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out int pid);
}
"@

function Get-ActiveApp {
  $h = [FGW]::GetForegroundWindow()
  if ($h -eq [IntPtr]::Zero) { return @{ process = $null; title = $null } }
  $sb = New-Object System.Text.StringBuilder 512
  [void][FGW]::GetWindowText($h, $sb, $sb.Capacity)
  $fgPid = 0
  [void][FGW]::GetWindowThreadProcessId($h, [ref]$fgPid)
  try { $p = Get-Process -Id $fgPid -ErrorAction Stop } catch { $p = $null }
  return @{ process = $p?.ProcessName; title = $sb.ToString() }
}

function Get-WifiSsid {
  try {
    $m = (netsh wlan show interfaces) | Select-String -Pattern '^\s*SSID\s*:\s*(.+)$'
    if ($m) { return $m.Matches[0].Groups[1].Value.Trim() }
  } catch {}
  return $null
}

function Get-NetworkSnapshot {
  $ssid = Get-WifiSsid
  $adapters = @()
  $statsAvailable = [bool](Get-Command Get-NetAdapterStatistics -ErrorAction SilentlyContinue)
  $netAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne $null }

  foreach ($na in $netAdapters) {
    $ipv4 = Get-NetIPAddress -InterfaceAlias $na.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Select-Object IPAddress, PrefixLength, AddressState, Type

    $tx = $null; $rx = $null
    if ($statsAvailable) {
      $s = Get-NetAdapterStatistics -Name $na.Name -ErrorAction SilentlyContinue
      if ($s) { $tx = [int64]$s.OutboundBytes; $rx = [int64]$s.InboundBytes }
    }

    $adapters += [pscustomobject]@{
      name       = $na.Name
      desc       = $na.InterfaceDescription
      status     = $na.Status
      linkSpeed  = $na.LinkSpeed
      mac        = $na.MacAddress
      ipv4       = @($ipv4)
      bytesSent  = $tx
      bytesRecv  = $rx
    }
  }

  [pscustomobject]@{ wifiSsid = $ssid; adapters = $adapters }
}

function SafeUptimeSeconds {
  try {
    $os = Get-CimInstance Win32_OperatingSystem
    $raw = $os.LastBootUpTime
    $boot = $null
    if ($raw -is [datetime]) {
      $boot = $raw
    } elseif ($raw -is [string] -and $raw.Length -ge 14) {
      try { $boot = [System.Management.ManagementDateTimeConverter]::ToDateTime($raw) } catch {}
    }
    if ($boot -and $boot -le (Get-Date)) {
      return [int]((Get-Date) - $boot).TotalSeconds
    }
  } catch {}
  return [int]([Environment]::TickCount64 / 1000)
}

function SafeCpuPercent {
  try {
    $v = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop).CounterSamples.CookedValue
    return [math]::Round($v,1)
  } catch {
    try {
      $avg = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
      if ($avg -ne $null) { return [math]::Round([double]$avg,1) }
    } catch {}
  }
  return $null
}

function Snapshot {
  $os    = Get-CimInstance Win32_OperatingSystem
  $cs    = Get-CimInstance Win32_ComputerSystem
  $cpu   = Get-CimInstance Win32_Processor
  $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select DeviceID,FileSystem,Size,FreeSpace,VolumeName

  $cpuPct  = SafeCpuPercent
  $totalMB = [math]::Round($os.TotalVisibleMemorySize/1024,0)
  $freeMB  = [math]::Round($os.FreePhysicalMemory/1024,0)
  $usedMB  = [int]($totalMB - $freeMB)
  $ramPct  = if ($totalMB -gt 0) { [math]::Round(($usedMB / $totalMB) * 100,1) } else { $null }

  $uptime = SafeUptimeSeconds
  $fg     = Get-ActiveApp
  $net    = Get-NetworkSnapshot

  [pscustomobject]@{
    collectedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    computer = @{
      machineName = $env:COMPUTERNAME
      userName    = $env:USERNAME
      manufacturer= $cs.Manufacturer
      model       = $cs.Model
      os = @{
        caption     = $os.Caption
        version     = $os.Version
        buildNumber = $os.BuildNumber
        architecture= $env:PROCESSOR_ARCHITECTURE
      }
    }
    activeApp = @{
      process = $fg.process
      title   = $fg.title
    }
    cpu = @{
      name = ($cpu.Name -join ', ')
      totalPct = $cpuPct
      logicalProcessors = ($cpu.NumberOfLogicalProcessors -join ',')
    }
    ram = @{
      totalMB = $totalMB
      freeMB  = $freeMB
      usedMB  = $usedMB
      usedPct = $ramPct
    }
    storage = @{ logicalDisks = @($disks) }
    network = $net
    uptimeSeconds = $uptime
  }
}

# --- Envío por GET robusto ---
# Asegura que el webhook no tenga espacios/saltos ocultos
$Webhook = $Webhook.Trim()

# (Opcional) Valida formato de URI
if (-not [Uri]::IsWellFormedUriString($Webhook, [UriKind]::Absolute)) {
  Write-Host "El Webhook no es una URI absoluta bien formada:" $Webhook
}

# Para construir query de forma segura
Add-Type -AssemblyName System.Web

Write-Host "Enviando snapshot (GET) cada $IntervalSec segundos a $Webhook ..."
while ($true) {
  try {
    $json = Snapshot | ConvertTo-Json -Depth 10 -Compress

    # Usa UriBuilder + HttpUtility.ParseQueryString para encodar correctamente
    $ub = [System.UriBuilder]::new($Webhook)
    $qs = [System.Web.HttpUtility]::ParseQueryString($ub.Query)
    $qs.Set('d', $json)            # 'd' contendrá el JSON (URL-encoded automáticamente)
    $ub.Query = $qs.ToString()
    $uri = $ub.Uri.AbsoluteUri

    # GET sin cuerpo
    $null = Invoke-WebRequest -Uri $uri -Method GET -UseBasicParsing

    Write-Host ("[{0}] Enviado correctamente (GET, URL {1} chars)" -f (Get-Date), $uri.Length)
  } catch {
    Write-Host ("[{0}] Error al enviar: {1}" -f (Get-Date), $_.Exception.Message)
    try { Write-Host "Última URL generada:" $uri } catch {}
  }
  Start-Sleep -Seconds $IntervalSec
}
