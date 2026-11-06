<#
  ============================================================
   RENEWABLE REVOLT - RR CHECKUP   (hardware + upgrade report)
  ------------------------------------------------------------
   Reads what THIS machine knows about itself and writes a
   plain-text "Upgrade Report" to your Desktop.  Read-only.

   Feed the report to the RR Upgrade Advisor (web chat) and it
   looks up YOUR exact model to tell you what's worth upgrading.

   It reports what software can see.  It canNOT see the PSU
   wattage or whether an empty M.2 slot exists - those need the
   model lookup, which is the Advisor's job.
  ============================================================
#>
#Requires -Version 5.1
$ErrorActionPreference = 'SilentlyContinue'
$R = New-Object System.Collections.Generic.List[string]
function W($t='',$c){ $R.Add($t); if ($c) { Write-Host $t -ForegroundColor $c } else { Write-Host $t } }
function H($t){ W ''; W ('== ' + $t + ' ' + ('=' * [Math]::Max(2,54-$t.Length))) }

Clear-Host
W "RENEWABLE REVOLT - RR CHECKUP (Upgrade Report)"
W (Get-Date)

# ---- machine identity (the lookup key) ----
$cs   = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$os   = Get-CimInstance Win32_OperatingSystem
$chassisCodes = (Get-CimInstance Win32_SystemEnclosure).ChassisTypes
$isLaptop = @($chassisCodes | Where-Object { $_ -in 8,9,10,11,12,14,18,21,30,31,32 }).Count -gt 0
$form = if ($isLaptop) { 'Laptop' } else { 'Desktop / All-in-One' }
H "MACHINE  (give the Advisor this exact model)"
W ("  Maker/Model : {0}  {1}" -f $cs.Manufacturer, $cs.Model)
W ("  Form factor : {0}" -f $form)
W ("  System SKU  : {0}" -f $cs.SystemSKUNumber)
W ("  Serial/Tag  : {0}" -f $bios.SerialNumber)
try { $bd = [Management.ManagementDateTimeConverter]::ToDateTime($bios.ReleaseDate); W ("  BIOS date   : {0:yyyy-MM-dd}  (rough age of the design)" -f $bd) } catch {}

# ---- CPU ----
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
H "PROCESSOR"
W ("  {0}" -f ($cpu.Name.Trim()))
W ("  Cores/Threads : {0} / {1}" -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)

# ---- RAM (upgradeable?) ----
H "MEMORY (RAM)"
$arr  = Get-CimInstance Win32_PhysicalMemoryArray | Select-Object -First 1
$mods = @(Get-CimInstance Win32_PhysicalMemory)
$totGB = [math]::Round((($mods | Measure-Object Capacity -Sum).Sum)/1GB,0)
$slots = $arr.MemoryDevices
$maxB  = if ($arr.MaxCapacityEx) { [double]$arr.MaxCapacityEx * 1KB } else { [double]$arr.MaxCapacity * 1KB }
$maxGB = [math]::Round($maxB/1GB,0)
$ddr = switch ([int]($mods[0].SMBIOSMemoryType)) { 24 {'DDR3'} 26 {'DDR4'} 34 {'DDR5'} default {'?'} }
W ("  Installed : {0} GB  {1} @ {2} MT/s" -f $totGB, $ddr, $mods[0].Speed)
W ("  Slots     : {0} used of {1} reported" -f $mods.Count, $slots)
if ($maxGB -gt 0) { W ("  Max (board reports): {0} GB   (SMBIOS value - verify on the Advisor)" -f $maxGB) }
if ($mods.Count -lt $slots) {
  if ($isLaptop) {
    W "  -> A second slot is REPORTED, so more RAM may be POSSIBLE." Yellow
    W "     But many laptops SOLDER their RAM - a reported 'slot' is often NOT a real,"
    W "     empty socket you can add to.  Treat this as 'possible, not likely' and"
    W "     confirm the exact model on the Advisor before buying anything." Yellow
  } else {
    W "  -> A free slot is reported - on a desktop this is usually a real socket." Green
    W "     Confirm the model/type on the Advisor before buying."
  }
} elseif ($isLaptop) {
  W "  -> Likely SOLDERED or fully populated - assume NOT upgradeable unless the Advisor confirms a real socket." Yellow
}

# ---- storage (the #1 upgrade) ----
H "STORAGE"
$disks = Get-PhysicalDisk | Sort-Object DeviceId
foreach ($d in $disks) {
  $gb = [math]::Round($d.Size/1GB,0)
  W ("  {0,-30} {1,-5} {2,-6} {3,6} GB  health: {4}" -f ($d.FriendlyName), $d.MediaType, $d.BusType, $gb, $d.HealthStatus)
}
$cvol = Get-Volume -DriveLetter C
if ($cvol) { W ("  C: free   : {0:N0} GB of {1:N0} GB" -f ($cvol.SizeRemaining/1GB), ($cvol.Size/1GB)) }
$hasNvme = @($disks | Where-Object { $_.BusType -eq 'NVMe' }).Count -gt 0
$hasHDD  = @($disks | Where-Object { $_.MediaType -eq 'HDD' }).Count -gt 0
if ($hasHDD)  { W "  -> A spinning HDD is here: moving to SSD/NVMe is the BIGGEST single upgrade." Yellow }

# ---- battery (laptops: tethered-to-cord test) ----
if ($isLaptop) {
  H "BATTERY"
  $des = $null; $full = $null
  try { $des  = @(Get-CimInstance -Namespace ROOT\WMI -ClassName BatteryStaticData).DesignedCapacity | Select-Object -First 1 } catch {}
  try { $full = @(Get-CimInstance -Namespace ROOT\WMI -ClassName BatteryFullChargedCapacity).FullChargedCapacity | Select-Object -First 1 } catch {}
  if ($des -and $full -and $des -gt 0) {
    $hp = [math]::Round($full/$des*100,0)
    W ("  Design capacity : {0} mWh" -f $des)
    W ("  Full-charge now : {0} mWh" -f $full)
    W ("  Battery health  : {0}%   {1}" -f $hp, $(if($hp -lt 60){'<-- worn; a new cell is a real upgrade'}elseif($hp -lt 80){'<-- aging'}else{'(healthy)'}))
  } else { W "  Could not read battery wear (some PCs hide it) - check on the Advisor." }
}

# ---- WiFi generation ----
H "WI-FI"
$drv = (netsh wlan show drivers) 2>$null
$name = ($drv | Select-String '^\s*Interface name|^\s*Driver' | Select-Object -First 1)
$radioLine = ($drv | Select-String 'Radio types supported') | Select-Object -First 1
$adapter = (Get-NetAdapter | Where-Object { $_.PhysicalMediaType -match '802.11' -or $_.Name -match 'Wi-?Fi|Wireless' } | Select-Object -First 1).InterfaceDescription
if ($adapter) { W ("  Adapter : {0}" -f $adapter) }
if ($radioLine) {
  $r = $radioLine.ToString()
  $gen = if ($r -match '802\.11be') {'Wi-Fi 7'} elseif ($r -match '802\.11ax') {'Wi-Fi 6 / 6E'} elseif ($r -match '802\.11ac') {'Wi-Fi 5'} elseif ($r -match '802\.11n') {'Wi-Fi 4'} else {'older'}
  W ("  {0}" -f ($r.Trim()))
  W ("  -> Generation: {0}" -f $gen) $(if($gen -match 'Wi-Fi 5|Wi-Fi 4|older'){'Yellow'}else{'Green'})
  if ($gen -match 'Wi-Fi 5|Wi-Fi 4|older') { W "     (A WiFi 6/6E M.2 card is a cheap, big real-world upgrade - IF the card is socketed.)" Yellow }
} else { W "  No Wi-Fi radio detected (desktop / Ethernet only?)." }

# ---- GPU ----
H "GRAPHICS"
foreach ($g in (Get-CimInstance Win32_VideoController)) {
  $v = if ($g.AdapterRAM) { [math]::Round($g.AdapterRAM/1GB,1) } else { 0 }
  W ("  {0}   (~{1} GB reported)" -f $g.Name, $v)
}
W "  (VRAM over 4 GB can read low here - a WMI quirk. Verify the model on the Advisor.)"

# ---- Windows / Win11 readiness ----
H "WINDOWS"
W ("  {0}  (build {1})" -f $os.Caption, $os.BuildNumber)
try { $sb = Confirm-SecureBootUEFI; W ("  Firmware : UEFI   Secure Boot: {0}" -f $sb) } catch { W "  Firmware : Legacy BIOS (no Secure Boot) - note for Win11" }
try { $tpm = Get-CimInstance -Namespace ROOT\CIMV2\Security\MicrosoftTpm -Class Win32_Tpm; W ("  TPM      : present={0}  ready={1}" -f $tpm.IsEnabled_InitialValue, $tpm.IsActivated_InitialValue) } catch { W "  TPM      : not detected" }

# ---- the three RR keys ----
H "THE 3 KEYS TO A SNAPPY REVOLT MACHINE"
W ("  [{0}] RR Turbo image (install our image)" -f '~')
W ("  [{0}] NVMe / SSD storage" -f $(if($hasNvme){'X'}elseif(-not $hasHDD){'~'}else{' '}))
$wifi6 = ($radioLine -and $radioLine.ToString() -match '802\.11ax|802\.11be')
W ("  [{0}] Wi-Fi 6 / 6E" -f $(if($wifi6){'X'}else{' '}))
if ($isLaptop) { W "  (+ a healthy battery - a laptop chained to the wall isn't an upgrade.)" }

# ---- what software cannot see ----
H "NOT VISIBLE TO SOFTWARE  (the Advisor looks these up by your model)"
W "  - PSU wattage / connectors (desktops) - the #1 upgrade limiter, invisible here."
W "  - Whether an empty M.2 / NVMe slot physically exists."
W "  - Whether the Wi-Fi card is socketed (replaceable) or soldered."
W "  - Physical space, cooling headroom, proprietary parts (small OEM desktops)."

# ---- save ----
$out = Join-Path ([Environment]::GetFolderPath('Desktop')) ("RR-Checkup-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmm'))
$R | Set-Content -Path $out -Encoding UTF8
W ''
W ("Saved: {0}" -f $out)
W "Open it, copy ALL the text, and paste it into the RR Upgrade Advisor."
W ''
Read-Host "Press Enter to close"
