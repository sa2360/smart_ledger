param(
    [string]$Flutter = 'flutter',
    [switch]$NoPub
)

$ErrorActionPreference = 'Stop'
$ledgerRoot = Split-Path -Parent $PSScriptRoot
$ledgerConfig = Join-Path $ledgerRoot 'config/production.json'
$ledgerValues = Get-Content -LiteralPath $ledgerConfig -Raw | ConvertFrom-Json
foreach ($ledgerName in @('LLM_RELAY_URL', 'ASR_RELAY_URL')) {
    $ledgerUri = $null
    if (-not [Uri]::TryCreate($ledgerValues.$ledgerName, [UriKind]::Absolute, [ref]$ledgerUri) -or
        $ledgerUri.Scheme -ne 'https' -or -not $ledgerUri.Host -or
        $ledgerUri.UserInfo -or $ledgerUri.Query -or $ledgerUri.Fragment) {
        throw "$ledgerName 必须是有效的 HTTPS 服务地址"
    }
}
if ([string]::IsNullOrWhiteSpace($ledgerValues.LLM_MODEL)) {
    throw '缺少 LLM_MODEL'
}
$ledgerArgs = @('build', 'apk', '--release', "--dart-define-from-file=$ledgerConfig")
if ($NoPub) { $ledgerArgs += '--no-pub' }
Push-Location $ledgerRoot
try {
    & $Flutter @ledgerArgs
    if ($LASTEXITCODE -ne 0) { throw "Flutter 构建失败（退出码 $LASTEXITCODE）" }
} finally {
    Pop-Location
}
