<#
.SYNOPSIS
  FIAP Cloud Games - Phase 3 smoke test for the Docker Compose stack, through the Kong gateway.

.DESCRIPTION
  Assumes the stack is already running from this repository:
      docker compose up -d --build
  Exercises the main flow through Kong (register, login, cached games list, approved purchase,
  payment status query, library), optionally a rejected purchase, then checks the Prometheus
  targets and the Notifications Function logs in Loki. Calls are paced (~0.7 s) to stay under
  the Kong rate limit (5 req/s). Exit code 0 = every check passed, 1 = at least one failed.
  Windows PowerShell 5.1 compatible. Only local/dev placeholders are used.

.EXAMPLE
  .\scripts\smoke-compose.ps1
  .\scripts\smoke-compose.ps1 -GatewayUrl http://localhost:8000 -SkipRejected -SkipLoki
#>
param(
  [string]$GatewayUrl    = "http://localhost:8000",
  [string]$PrometheusUrl = "http://localhost:9090",
  [string]$LokiUrl       = "http://localhost:3100",
  [switch]$SkipRejected,
  [switch]$SkipPrometheus,
  [switch]$SkipLoki
)

$ErrorActionPreference = "Stop"
$script:failures = 0

function Pass([string]$msg) { Write-Host ("  PASS  " + $msg) -ForegroundColor Green }
function Fail([string]$msg) { Write-Host ("  FAIL  " + $msg) -ForegroundColor Red; $script:failures++ }
function Info([string]$msg) { Write-Host ("        " + $msg) -ForegroundColor DarkGray }
function Pace() { Start-Sleep -Milliseconds 700 }

# Calls the API and always returns @{ Status; Headers; Body }, also for 4xx/5xx (no exception).
function Invoke-Api([string]$Method, [string]$Url, [string]$Token, [string]$Body) {
  $headers = @{}
  if ($Token) { $headers["Authorization"] = "Bearer $Token" }
  try {
    $params = @{ Method = $Method; Uri = $Url; Headers = $headers; UseBasicParsing = $true; TimeoutSec = 30 }
    if ($Body) { $params["ContentType"] = "application/json"; $params["Body"] = $Body }
    $r = Invoke-WebRequest @params
    return @{ Status = [int]$r.StatusCode; Headers = $r.Headers; Body = [string]$r.Content }
  } catch {
    $resp = $_.Exception.Response
    if ($null -eq $resp) { throw }
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $content = $reader.ReadToEnd()
    return @{ Status = [int]$resp.StatusCode; Headers = @{}; Body = $content }
  } finally {
    Pace
  }
}

function Get-CacheHeader($response) {
  if ($response.Headers -and $response.Headers["X-FCG-Cache"]) { return [string]$response.Headers["X-FCG-Cache"] }
  return "-"
}

function Wait-Payment([string]$OrderId, [string]$Token) {
  # PaymentsAPI writes the document after consuming the Kafka event; poll up to ~15 s.
  for ($i = 0; $i -lt 12; $i++) {
    $p = Invoke-Api "GET" "$GatewayUrl/api/payments/order/$OrderId" $Token $null
    if ($p.Status -eq 200) { return $p }
    Start-Sleep -Milliseconds 600
  }
  return $p
}

Write-Host ""
Write-Host "== FCG Phase 3 smoke test (Docker Compose, through Kong at $GatewayUrl)" -ForegroundColor Cyan
$stamp    = Get-Date -Format "yyyyMMddHHmmss"
$email    = "smoke.$stamp@fcg.com"
$password = "Smoke@123"

# 0) Gateway reachable and protecting routes
Write-Host "[0] Gateway"
$anon = Invoke-Api "GET" "$GatewayUrl/api/games" $null $null
if ($anon.Status -eq 401) { Pass "GET /api/games without token -> 401 from Kong" } else { Fail "GET /api/games without token: expected 401, got $($anon.Status)" }

# 1) Register
Write-Host "[1] Register through Kong"
$reg = Invoke-Api "POST" "$GatewayUrl/api/auth/register" $null (@{ name = "Smoke User"; email = $email; password = $password } | ConvertTo-Json -Compress)
if ($reg.Status -eq 201) { Pass "POST /api/auth/register -> 201 ($email)" } else { Fail "register: expected 201, got $($reg.Status) $($reg.Body)" }

# 2) Login
Write-Host "[2] Login through Kong"
$login = Invoke-Api "POST" "$GatewayUrl/api/auth/login" $null (@{ email = $email; password = $password } | ConvertTo-Json -Compress)
$token = $null
if ($login.Status -eq 200) { $token = ($login.Body | ConvertFrom-Json).token }
if ($token) { Pass "POST /api/auth/login -> 200, JWT received" } else { Fail "login: expected 200 with token, got $($login.Status)"; Write-Host "Aborting: no token."; exit 1 }

# 3/4) Games list twice + cache header
Write-Host "[3] GET /api/games twice (Redis cache)"
$g1 = Invoke-Api "GET" "$GatewayUrl/api/games" $token $null
$g2 = Invoke-Api "GET" "$GatewayUrl/api/games" $token $null
$c1 = Get-CacheHeader $g1; $c2 = Get-CacheHeader $g2
if ($g1.Status -eq 200 -and $g2.Status -eq 200) { Pass "both calls 200" } else { Fail "games list: got $($g1.Status) / $($g2.Status)" }
if ($c2 -eq "HIT") { Pass "X-FCG-Cache: first=$c1, second=$c2" } elseif ($c2 -eq "BYPASS") { Fail "X-FCG-Cache second call is BYPASS (Redis unavailable?)" } else { Fail "X-FCG-Cache: first=$c1, second=$c2 (expected HIT on the second call)" }
# PowerShell 5.1: assign the parsed array to a variable first (piping it straight into @() nests the array).
$games = @()
if ($g2.Status -eq 200) { $parsedGames = $g2.Body | ConvertFrom-Json; $games = @($parsedGames) }
$game = $games | Where-Object { $_.title -eq "Pixel Racers" } | Select-Object -First 1
if (-not $game) { $game = $games | Where-Object { $_.price -le 1000 } | Sort-Object price | Select-Object -First 1 }
if (-not $game) { Fail "no affordable game found in the catalog"; Write-Host "Aborting."; exit 1 }
Info ("purchasing '" + $game.title + "' (" + $game.price + ") id " + $game.id)

# 5) Approved purchase
Write-Host "[5] Approved purchase"
$acq = Invoke-Api "POST" "$GatewayUrl/api/library/acquire/$($game.id)" $token $null
$orderId = $null
if ($acq.Status -eq 202) { $orderId = ($acq.Body | ConvertFrom-Json).orderId; Pass "POST /api/library/acquire -> 202, orderId $orderId" } else { Fail "acquire: expected 202, got $($acq.Status) $($acq.Body)"; Write-Host "Aborting."; exit 1 }

# 6/7) Payment status
Write-Host "[6] GET /api/payments/order/{orderId} (MongoDB payment history)"
$pay = Wait-Payment $orderId $token
if ($pay.Status -eq 200) {
  $status = ($pay.Body | ConvertFrom-Json).status
  if ($status -eq "Approved") { Pass "payment status Approved (reason: $(($pay.Body | ConvertFrom-Json).reason))" } else { Fail "payment status: expected Approved, got $status" }
} else { Fail "payment query: expected 200, got $($pay.Status) $($pay.Body)" }

# 8) Library
Write-Host "[8] GET /api/library/my-games"
$lib = Invoke-Api "GET" "$GatewayUrl/api/library/my-games" $token $null
$owned = $false
if ($lib.Status -eq 200) { $libItems = $lib.Body | ConvertFrom-Json; $owned = @($libItems) | Where-Object { $_.gameId -eq $game.id } }
if ($owned) { Pass "library contains '$($game.title)' (X-FCG-Cache: $(Get-CacheHeader $lib))" } else { Fail "library does not contain the purchased game (status $($lib.Status))" }

# 9) Rejected purchase (optional)
if (-not $SkipRejected) {
  Write-Host "[9] Rejected purchase (price above the 1000 limit)"
  $expensive = $games | Where-Object { $_.price -gt 1000 } | Select-Object -First 1
  if (-not $expensive) {
    $adminLogin = Invoke-Api "POST" "$GatewayUrl/api/auth/login" $null '{"email":"admin@fcg.com","password":"Admin@123"}'
    if ($adminLogin.Status -eq 200) {
      $adminToken = ($adminLogin.Body | ConvertFrom-Json).token
      $created = Invoke-Api "POST" "$GatewayUrl/api/games" $adminToken '{"title":"Smoke Expensive Game","description":"Priced above the payment limit (smoke test).","genre":"Test","price":1500,"releaseDate":"2026-01-01T00:00:00Z"}'
      if ($created.Status -eq 201) { $expensive = $created.Body | ConvertFrom-Json; Info "created 'Smoke Expensive Game' (1500) as admin" }
    }
  }
  if ($expensive) {
    $acq2 = Invoke-Api "POST" "$GatewayUrl/api/library/acquire/$($expensive.id)" $token $null
    if ($acq2.Status -eq 202) {
      $orderId2 = ($acq2.Body | ConvertFrom-Json).orderId
      $pay2 = Wait-Payment $orderId2 $token
      $status2 = $null
      if ($pay2.Status -eq 200) { $status2 = ($pay2.Body | ConvertFrom-Json).status }
      if ($status2 -eq "Rejected") { Pass "payment status Rejected for orderId $orderId2" } else { Fail "rejected purchase: expected Rejected, got $status2 (HTTP $($pay2.Status))" }
    } else { Fail "acquire (expensive): expected 202, got $($acq2.Status)" }
  } else { Fail "no game above 1000 available and could not create one" }
}

# 10) Prometheus targets
if (-not $SkipPrometheus) {
  Write-Host "[10] Prometheus targets ($PrometheusUrl)"
  try {
    $targets = (Invoke-WebRequest -UseBasicParsing -Uri "$PrometheusUrl/api/v1/targets" -TimeoutSec 15).Content | ConvertFrom-Json
    $active = @($targets.data.activeTargets)
    $down = @($active | Where-Object { $_.health -ne "up" })
    $jobs = ($active | ForEach-Object { $_.labels.job }) -join ", "
    if ($active.Count -ge 4 -and $down.Count -eq 0) { Pass "$($active.Count) targets up: $jobs" } else { Fail "targets: $($active.Count) active, $($down.Count) not up ($jobs)" }
  } catch { Fail "Prometheus not reachable: $($_.Exception.Message)" }
}

# 11) Loki: notification logs for this run
if (-not $SkipLoki) {
  Write-Host "[11] Loki: Notifications Function logs ($LokiUrl)"
  $queries = @(
    @{ name = "[WELCOME EMAIL] for $email";           expr = "{compose_service=`"notifications-function`"} |= `"[WELCOME EMAIL]`" |= `"$email`"" },
    @{ name = "[PURCHASE CONFIRMATION] for $orderId"; expr = "{compose_service=`"notifications-function`"} |= `"[PURCHASE CONFIRMATION]`" |= `"$orderId`"" }
  )
  foreach ($q in $queries) {
    $lines = 0
    for ($i = 0; $i -lt 10 -and $lines -eq 0; $i++) {
      try {
        $url = "$LokiUrl/loki/api/v1/query_range?limit=10&query=" + [uri]::EscapeDataString($q.expr)
        $res = (Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 15).Content | ConvertFrom-Json
        foreach ($stream in @($res.data.result)) { $lines += @($stream.values).Count }
      } catch { $lines = -1; break }
      if ($lines -eq 0) { Start-Sleep -Seconds 2 }
    }
    if ($lines -gt 0) { Pass "$($q.name): $lines line(s) in Loki" } elseif ($lines -eq -1) { Fail "Loki not reachable" } else { Fail "$($q.name): not found in Loki" }
  }
}

Write-Host ""
if ($script:failures -eq 0) {
  Write-Host "== SMOKE PASSED (0 failures)" -ForegroundColor Green
  exit 0
} else {
  Write-Host "== SMOKE FAILED ($($script:failures) failure(s))" -ForegroundColor Red
  exit 1
}
