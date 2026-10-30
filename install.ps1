# Mini IP Manager 설치: 바탕화면에 바로가기를 만든다. 설치.cmd가 실행한다.
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$app = Join-Path $dir 'MiniIpManager.ps1'
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Mini IP Manager.lnk'

Write-Host ''
Write-Host ' Mini IP Manager 설치'
Write-Host ' -------------------------------------------'
Write-Host " 설치 폴더: $dir"
Write-Host ' (설치한 뒤에는 이 폴더를 옮기거나 지우지 마세요)'
Write-Host ''

try {
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
    $s.TargetPath       = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $s.Arguments        = "-NoProfile -WindowStyle Hidden -File `"$app`""
    $s.WorkingDirectory = $dir
    $s.WindowStyle      = 7
    $s.IconLocation     = (Join-Path $env:SystemRoot 'System32\netshell.dll') + ',0'
    $s.Description      = 'Mini IP Manager - 고정 IP / 자동 IP 전환'
    $s.Save()
} catch {
    Write-Host " 바로가기를 만들지 못했습니다: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host " 바로가기를 만들었습니다: $lnk" -ForegroundColor Green
Write-Host ''
Write-Host ' 바탕화면의 [Mini IP Manager]를 더블클릭하고 관리자 권한을 허용하세요.'
Write-Host ' 처음 화면에서 내 네트워크 어댑터를 확인하고 내 고정 IP를 등록하면 됩니다.'
Write-Host ''
exit 0
