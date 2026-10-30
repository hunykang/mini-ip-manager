<#
  Mini IP Manager
  사내 고정 IP(여러 개 저장, 기본값 지정) <-> 외근 DHCP 전환 로컬 웹서비스
  버튼을 누르면 Windows 네트워크 설정(IP, 마스크, 게이트웨이, DNS 2개)만 바꾼다.
  실행: 관리자 권한으로 다시 실행됨 -> http://localhost:8765
#>
param(
    [int]$Port = 8765,
    [switch]$NoElevate,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$Root       = $PSScriptRoot
$ConfigPath = Join-Path $Root 'config.json'
$LogPath    = Join-Path $Root 'mini-ip-manager.log'
$IndexPath  = Join-Path $Root 'index.html'

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$script:IsAdmin = Test-Admin
if (-not $script:IsAdmin -and -not $NoElevate) {
    $argList = @('-NoProfile', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"", '-Port', $Port)
    if ($NoBrowser) { $argList += '-NoBrowser' }
    Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList $argList
    exit
}

# 주소창 없는 Edge 앱 창으로 연다. Edge가 없으면 기본 브라우저로 연다.
function Open-AppWindow {
    $url = "http://localhost:$Port/"
    $edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
              "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($edge) { Start-Process $edge -ArgumentList "--app=$url", '--window-size=560,760' }
    else { Start-Process $url }
}

function Write-Log([string]$msg, [string]$level = 'info') {
    $line = "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) [$level] $msg"
    try { Add-Content -Path $LogPath -Value $line -Encoding UTF8 } catch {}
    Write-Host $line
}

# ---------- 검증 ----------
function Test-IPv4([string]$s) {
    if ($s -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { return $false }
    foreach ($o in $s.Split('.')) { if ([int]$o -gt 255) { return $false } }
    $true
}

function Test-Mask([string]$s) {
    if (-not (Test-IPv4 $s)) { return $false }
    $bits = ($s.Split('.') | ForEach-Object { [Convert]::ToString([int]$_, 2).PadLeft(8, '0') }) -join ''
    $bits -match '^1+0*$'
}

# ---------- 설정 ----------
function New-DefaultConfig {
    [pscustomobject]@{ adapterIndex = 0; defaultProfileId = ''; profiles = @() }
}

function ConvertTo-Config($b) {
    if (-not $b) { throw '설정 내용이 비어 있습니다.' }
    $profiles = @()
    $n = 0
    foreach ($p in @($b.profiles)) {
        if (-not $p) { continue }
        $n++
        $name = "$($p.name)".Trim()
        if (-not $name) { $name = "고정 IP $n" }
        $prof = [pscustomobject]@{
            id      = if ("$($p.id)".Trim()) { "$($p.id)".Trim() } else { [guid]::NewGuid().ToString('N').Substring(0, 8) }
            name    = $name
            ip      = "$($p.ip)".Trim()
            mask    = "$($p.mask)".Trim()
            gateway = "$($p.gateway)".Trim()
            dns1    = "$($p.dns1)".Trim()
            dns2    = "$($p.dns2)".Trim()
        }
        if (-not (Test-IPv4 $prof.ip))   { throw "[$name] IP 주소가 올바르지 않습니다: '$($prof.ip)'" }
        if (-not (Test-Mask $prof.mask)) { throw "[$name] 서브넷 마스크가 올바르지 않습니다: '$($prof.mask)'" }
        if ($prof.gateway -and -not (Test-IPv4 $prof.gateway)) { throw "[$name] 기본 게이트웨이가 올바르지 않습니다: '$($prof.gateway)'" }
        if ($prof.dns1 -and -not (Test-IPv4 $prof.dns1)) { throw "[$name] 기본 설정 DNS 서버가 올바르지 않습니다: '$($prof.dns1)'" }
        if ($prof.dns2 -and -not (Test-IPv4 $prof.dns2)) { throw "[$name] 보조 DNS 서버가 올바르지 않습니다: '$($prof.dns2)'" }
        if ($prof.dns2 -and -not $prof.dns1) { throw "[$name] 보조 DNS만 입력할 수는 없습니다. 기본 설정 DNS를 먼저 입력하세요." }
        $profiles += $prof
    }

    $defaultId = "$($b.defaultProfileId)"
    if (-not ($profiles | Where-Object { $_.id -eq $defaultId })) {
        $defaultId = if ($profiles.Count) { $profiles[0].id } else { '' }
    }

    [pscustomobject]@{
        adapterIndex     = [int]$b.adapterIndex
        defaultProfileId = $defaultId
        profiles         = @($profiles)
    }
}

function Get-Config {
    if (Test-Path $ConfigPath) {
        try { return ConvertTo-Config (Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
        catch { Write-Log "config.json을 읽지 못해 기본 설정으로 시작합니다: $($_.Exception.Message)" 'warn' }
    }
    New-DefaultConfig
}

function Save-Config($cfg) {
    $json = ConvertTo-Json -InputObject $cfg -Depth 6
    [IO.File]::WriteAllText($ConfigPath, $json, (New-Object Text.UTF8Encoding $false))
}

function Get-Profile([string]$id) {
    if (-not $id) { $id = $script:Config.defaultProfileId }
    $p = @($script:Config.profiles) | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if (-not $p) { throw '적용할 고정 IP가 없습니다. 설정에서 고정 IP를 추가하세요.' }
    $p
}

# ---------- 상태 조회 ----------
function Get-WifiSsid {
    $map = @{}
    try {
        $ErrorActionPreference = 'Continue'
        $out = & netsh.exe wlan show interfaces 2>$null
    } catch { return $map }
    # 항목 이름(Name/이름)은 언어·인코딩마다 달라서, 값이 어댑터 이름과 같은 줄로 인터페이스를 찾는다
    $names = @(Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name)" })
    $name = $null
    foreach ($line in $out) {
        if ($line -match '^\s*SSID\s*:\s*(.+)$') { if ($name) { $map[$name] = $Matches[1].Trim() } }
        elseif ($line -match '^\s*[^:]+?\s*:\s*(.+?)\s*$' -and $names -contains $Matches[1]) { $name = $Matches[1] }
    }
    $map
}

function ConvertTo-MaskFromPrefix([int]$len) {
    $bits = ('1' * $len).PadRight(32, '0')
    (0..3 | ForEach-Object { [Convert]::ToInt32($bits.Substring($_ * 8, 8), 2) }) -join '.'
}

function Get-AdapterInfo($a, $ssids) {
    $idx   = $a.ifIndex
    $ipif  = Get-NetIPInterface -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $addr  = @(Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    $route = Get-NetRoute -InterfaceIndex $idx -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
             Sort-Object RouteMetric | Select-Object -First 1
    $dns   = (Get-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses

    $dhcp = [bool]($ipif -and "$($ipif.Dhcp)" -eq 'Enabled')
    $ip   = if ($addr.Count) { "$($addr[0].IPAddress)" } else { '' }
    $mask = if ($addr.Count) { ConvertTo-MaskFromPrefix $addr[0].PrefixLength } else { '' }

    $mode = 'dhcp'; $profileId = ''; $profileName = ''
    if (-not $dhcp) {
        $match = @($script:Config.profiles) | Where-Object { $_.ip -eq $ip } | Select-Object -First 1
        if ($match) { $mode = 'static'; $profileId = $match.id; $profileName = $match.name }
        else { $mode = 'static-other' }
    }

    [ordered]@{
        index       = [int]$idx
        name        = "$($a.Name)"
        description = "$($a.InterfaceDescription)"
        status      = "$($a.Status)"
        dhcp        = $dhcp
        ip          = $ip
        mask        = $mask
        gateway     = if ($route) { "$($route.NextHop)" } else { '' }
        dns         = @($dns | ForEach-Object { "$_" })
        ssid        = "$($ssids["$($a.Name)"])"
        mode        = $mode
        profileId   = $profileId
        profileName = $profileName
    }
}

function Get-Status {
    $ssids = Get-WifiSsid
    $list = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Sort-Object ifIndex |
              ForEach-Object { Get-AdapterInfo $_ $ssids })
    [ordered]@{
        isAdmin  = $script:IsAdmin
        adapters = $list
        config   = $script:Config
    }
}

# ---------- IP 변경 ----------
function Invoke-Netsh {
    $ErrorActionPreference = 'Continue'
    $out = (& netsh.exe @args 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "netsh $($args -join ' ') 실패: $out" }
}

function Assert-Admin {
    if (-not $script:IsAdmin) { throw '관리자 권한이 아니어서 IP를 바꿀 수 없습니다. 관리자 권한으로 다시 실행하세요.' }
}

function Get-TargetAdapter {
    $index = [int]$script:Config.adapterIndex
    if (-not $index) { throw '설정에서 네트워크 어댑터를 먼저 선택하세요.' }
    $a = Get-NetAdapter -InterfaceIndex $index -ErrorAction SilentlyContinue
    if (-not $a) { throw "네트워크 어댑터(index $index)를 찾을 수 없습니다." }
    $a
}

function Set-StaticMode([string]$profileId) {
    Assert-Admin
    $a = Get-TargetAdapter
    $p = Get-Profile $profileId
    $i = $a.ifIndex

    if ($p.gateway) {
        Invoke-Netsh interface ipv4 set address "name=$i" source=static "address=$($p.ip)" "mask=$($p.mask)" "gateway=$($p.gateway)" gwmetric=1
    } else {
        Invoke-Netsh interface ipv4 set address "name=$i" source=static "address=$($p.ip)" "mask=$($p.mask)" gateway=none
    }

    if ($p.dns1) {
        Invoke-Netsh interface ipv4 set dnsservers "name=$i" source=static "address=$($p.dns1)" register=primary validate=no
        if ($p.dns2) { Invoke-Netsh interface ipv4 add dnsservers "name=$i" "address=$($p.dns2)" index=2 validate=no }
    } else {
        Invoke-Netsh interface ipv4 set dnsservers "name=$i" source=static address=none register=primary
    }

    $dnsText = (@($p.dns1, $p.dns2) | Where-Object { $_ }) -join ', '
    Write-Log "[$($a.Name)] 고정 IP '$($p.name)' 적용: $($p.ip) / $($p.mask), GW $($p.gateway), DNS $dnsText"
}

function Set-DhcpMode {
    Assert-Admin
    $a = Get-TargetAdapter
    $i = $a.ifIndex
    $ipif = Get-NetIPInterface -InterfaceIndex $i -AddressFamily IPv4
    if ("$($ipif.Dhcp)" -ne 'Enabled') {
        Invoke-Netsh interface ipv4 set address "name=$i" source=dhcp
    }
    try { Invoke-Netsh interface ipv4 set dnsservers "name=$i" source=dhcp } catch { Write-Log $_.Exception.Message 'warn' }
    Start-Process ipconfig.exe -ArgumentList '/renew', "`"$($a.Name)`"" -WindowStyle Hidden
    Write-Log "[$($a.Name)] 자동 IP(DHCP) 적용"
}

# ---------- HTTP ----------
function Send-Response($ctx, [int]$code, [byte[]]$bytes, [string]$type) {
    $res = $ctx.Response
    $res.StatusCode = $code
    $res.ContentType = $type
    $res.Headers['Cache-Control'] = 'no-store'
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
    $res.OutputStream.Close()
}

function Send-Json($ctx, $obj, [int]$code = 200) {
    $json = ConvertTo-Json -InputObject $obj -Depth 8 -Compress
    Send-Response $ctx $code ([Text.Encoding]::UTF8.GetBytes($json)) 'application/json; charset=utf-8'
}

function Invoke-Request($ctx) {
    $req = $ctx.Request
    $path = $req.Url.AbsolutePath
    try {
        if ($req.HttpMethod -eq 'GET') {
            if ($path -eq '/' -or $path -eq '/index.html') {
                Send-Response $ctx 200 ([IO.File]::ReadAllBytes($IndexPath)) 'text/html; charset=utf-8'; return
            }
            if ($path -eq '/api/status') { Send-Json $ctx (Get-Status); return }
        }
        elseif ($req.HttpMethod -eq 'POST') {
            # 다른 웹사이트가 localhost로 요청을 보내지 못하게 막는다
            $origin = $req.Headers['Origin']
            if ($req.Headers['X-MiniIp'] -ne '1' -or ($origin -and $origin -notin @("http://localhost:$Port", "http://127.0.0.1:$Port"))) {
                Send-Json $ctx @{ error = 'forbidden' } 403; return
            }
            $reader = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
            $raw = $reader.ReadToEnd(); $reader.Close()
            $body = if ($raw) { $raw | ConvertFrom-Json } else { $null }

            switch ($path) {
                '/api/config' {
                    $script:Config = ConvertTo-Config $body
                    Save-Config $script:Config
                    Write-Log "설정 저장 (고정 IP $(@($script:Config.profiles).Count)개)"
                    Send-Json $ctx (Get-Status); return
                }
                '/api/apply' {
                    if ($body.mode -eq 'static') { Set-StaticMode "$($body.profileId)" }
                    elseif ($body.mode -eq 'dhcp') { Set-DhcpMode }
                    else { throw "알 수 없는 모드: $($body.mode)" }
                    Start-Sleep -Seconds 2
                    Send-Json $ctx (Get-Status); return
                }
                '/api/shutdown' {
                    Send-Json $ctx @{ ok = $true }
                    $script:Running = $false; return
                }
            }
        }
        Send-Json $ctx @{ error = 'not found' } 404
    } catch {
        $msg = $_.Exception.Message
        Write-Log $msg 'error'
        try { Send-Json $ctx @{ error = $msg } 400 } catch {}
    }
}

# ---------- 시작 ----------
$script:Config = Get-Config
$script:Running = $true

$listener = New-Object Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
if ($script:IsAdmin) { $listener.Prefixes.Add("http://127.0.0.1:$Port/") }
try { $listener.Start() }
catch {
    # 이미 실행 중이면 창만 다시 연다
    Write-Host "포트 $Port 을(를) 열 수 없습니다. 이미 실행 중일 수 있습니다: $($_.Exception.Message)"
    if (-not $NoBrowser) { Open-AppWindow }
    exit 1
}

Write-Log "Mini IP Manager 시작 - http://localhost:$Port (관리자 권한: $($script:IsAdmin))"
if (-not $NoBrowser) { Open-AppWindow }

$pending = $null
try {
    while ($script:Running) {
        if (-not $pending) { $pending = $listener.GetContextAsync() }
        if ($pending.Wait(1000)) {
            $ctx = $pending.Result
            $pending = $null
            Invoke-Request $ctx
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
    Write-Log 'Mini IP Manager 종료'
}
