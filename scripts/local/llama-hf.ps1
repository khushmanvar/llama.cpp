<#
.SYNOPSIS
    Run a Hugging Face GGUF model with llama.cpp.

.DESCRIPTION
    llama's built-in -hf downloader cannot complete the TLS handshake with
    us.aws.cdn.hf.co, where Hugging Face redirects model weights. The corporate
    Zscaler proxy intercepts that host and presents a chain rooted at
    "Amdocs RSA Root CA", and llama.cpp <= b10121 verifies with OpenSSL against
    an empty default trust store, so every download dies with "status code: -1".
    curl.exe verifies with Schannel and trusts that root from the Windows store,
    so we fetch with curl and hand the local file to llama.

    Drop this script once llama.cpp b10122 or later is installed: cpp-httplib
    0.51.0 turns on Schannel verification by default and plain -hf will work.

.EXAMPLE
    .\llama-hf.ps1 ggml-org/gemma-3-270m-it-qat-GGUF:Q4_0

.EXAMPLE
    .\llama-hf.ps1 ggml-org/gemma-3-270m-it-qat-GGUF:Q4_0 --port 9090 -c 8192

.EXAMPLE
    $env:LLAMA_CMD = 'cli'; .\llama-hf.ps1 ggml-org/gemma-3-270m-it-qat-GGUF:Q4_0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Model,

    [Parameter(ValueFromRemainingArguments)]
    [string[]] $LlamaArgs
)

$ErrorActionPreference = 'Stop'

$repo  = $Model
$quant = 'Q4_K_M'
if ($Model -match '^(?<repo>[^:]+):(?<quant>.+)$') {
    $repo  = $Matches.repo
    $quant = $Matches.quant
}

$cache = if ($env:LLAMA_CACHE) { $env:LLAMA_CACHE } else { Join-Path $env:LOCALAPPDATA 'llama.cpp' }
New-Item -ItemType Directory -Force -Path $cache | Out-Null

$ggufs = (Invoke-RestMethod "https://huggingface.co/api/models/$repo").siblings.rfilename |
    Where-Object { $_ -like '*.gguf' }
if (-not $ggufs) {
    throw "no .gguf files found in $repo"
}

$file = $ggufs | Where-Object { $_ -like "*$quant*" } | Select-Object -First 1
if (-not $file) {
    throw "no .gguf matching quant '$quant'. available: $($ggufs -join ', ')"
}

# llama's own cache naming, so a later native -hf run reuses the same file
$target = Join-Path $cache ((('{0}_{1}' -f $repo, $file)) -replace '[\\/]', '_')

if (-not (Test-Path $target) -or (Get-Item $target).Length -eq 0) {
    Write-Host "llama-hf: downloading $repo/$file" -ForegroundColor Cyan
    & curl.exe -L --fail --retry 3 -C - -o "$target.part" "https://huggingface.co/$repo/resolve/main/$file"
    if ($LASTEXITCODE -ne 0) {
        throw "download failed with exit code $LASTEXITCODE"
    }
    Move-Item -LiteralPath "$target.part" -Destination $target -Force
}

$command = if ($env:LLAMA_CMD) { $env:LLAMA_CMD } else { 'serve' }
& llama $command -m $target @LlamaArgs
