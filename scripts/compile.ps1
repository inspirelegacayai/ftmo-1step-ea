# Compiles an MQL5 source file with MetaEditor from the command line.
# MetaEditor's exit code is unreliable (it returns 1 even on a clean build),
# so success is decided by parsing the "Result: N errors" line of the log.
#
# Usage: powershell -File scripts/compile.ps1 path\to\File.mq5
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [string]$MetaEditor = "D:\Program Files (x86)\New folder\MetaEditor64.exe",
    [string]$DataFolder = "C:\Users\visio\AppData\Roaming\MetaQuotes\Terminal\FD4EE2C8A393414AD14B68905678707F"
)

$src = (Resolve-Path $Source).Path
$log = [IO.Path]::ChangeExtension($src, ".log")
if (Test-Path $log) { Remove-Item $log }

Start-Process -FilePath $MetaEditor -Wait -ArgumentList @(
    "/compile:`"$src`"",
    "/log:`"$log`"",
    "/inc:`"$DataFolder\MQL5`""
) | Out-Null

# MetaEditor writes the log as UTF-16 with a BOM; Get-Content detects it
$lines = Get-Content $log
$lines | Where-Object { $_ -match ' : (error|warning) ' } | ForEach-Object { Write-Host $_ }
$result = $lines | Where-Object { $_ -match '^Result:' } | Select-Object -Last 1
Write-Host $result

if ($result -match 'Result: 0 errors') { exit 0 } else { exit 1 }
