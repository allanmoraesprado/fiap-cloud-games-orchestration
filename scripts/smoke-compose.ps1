<#
.SYNOPSIS
  FIAP Cloud Games - smoke test for the Docker Compose stack, through the Kong gateway.

.DESCRIPTION
  Assumes the stack is already running from this repository:
      docker compose up -d --build
  Exercises the main flow through Kong (register, login, cached games list, approved purchase,
  payment status query, library), optionally a rejected purchase, the Elasticsearch search
  (exact, fuzzy, empty, validation, create/update/delete synchronization, reindex and, with
  -SearchOutage, an engine outage followed by recovery), then checks the Prometheus
  targets and the Notifications Function logs in Loki. Calls are paced (~0.7 s) to stay under
  the Kong rate limit (5 req/s). Exit code 0 = every check passed, 1 = at least one failed.
  Windows PowerShell 5.1 compatible. Only local/dev placeholders are used.

.EXAMPLE
  .\scripts\smoke-compose.ps1
  .\scripts\smoke-compose.ps1 -GatewayUrl http://localhost:8000 -SkipRejected -SkipLoki
  .\scripts\smoke-compose.ps1 -SearchOutage
#>
param(
  [string]$GatewayUrl    = "http://localhost:8000",
  [string]$PrometheusUrl = "http://localhost:9090",
  [string]$LokiUrl       = "http://localhost:3100",
  # Seeded local/dev administrator (placeholder credentials of the local stack).
  [string]$AdminEmail    = "admin@fcg.com",
  [string]$AdminPassword = "Admin@123",
  [switch]$SkipRejected,
  [switch]$SkipSearch,
  [switch]$SearchOutage,
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
    return @{ Status = [int]$resp.StatusCode; Headers = $resp.Headers; Body = $content }
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

function Get-AdminToken() {
  if (-not $script:adminToken) {
    $r = Invoke-Api "POST" "$GatewayUrl/api/auth/login" $null (@{ email = $AdminEmail; password = $AdminPassword } | ConvertTo-Json -Compress)
    if ($r.Status -eq 200) { $script:adminToken = ($r.Body | ConvertFrom-Json).token }
  }
  return $script:adminToken
}

# docker writes progress to stderr; under PowerShell 5.1 with ErrorActionPreference=Stop that
# would abort the script, so it is relaxed for the call. Honors COMPOSE_PROJECT_NAME.
function Invoke-Compose([string[]]$ComposeArgs) {
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try { & docker compose @ComposeArgs 2>&1 | Out-Null } finally { $ErrorActionPreference = $previous }
}

function Search-Games([string]$Text, [string]$Token, [string]$Extra = "") {
  return Invoke-Api "GET" ("$GatewayUrl/api/games/search?q=" + [uri]::EscapeDataString($Text) + $Extra) $Token $null
}

# Parsed items of a search response (empty when the call did not return 200). Callers wrap the
# result in @() because PowerShell 5.1 unrolls single-item arrays and PSCustomObject has no Count.
function Get-SearchItems($response) {
  if ($response.Status -ne 200) { return @() }
  $parsed = $response.Body | ConvertFrom-Json
  return @($parsed.items)
}

Write-Host ""
Write-Host "== FCG smoke test (Docker Compose, through Kong at $GatewayUrl)" -ForegroundColor Cyan
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
    $adminToken = Get-AdminToken
    if ($adminToken) {
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

# 12) Search (Elasticsearch) through Kong
if (-not $SkipSearch) {
  Write-Host "[12] Search (Elasticsearch) through Kong"
  $anonSearch = Invoke-Api "GET" "$GatewayUrl/api/games/search?q=cosmic" $null $null
  if ($anonSearch.Status -eq 401) { Pass "GET /api/games/search without token -> 401 from Kong" } else { Fail "search without token: expected 401, got $($anonSearch.Status)" }

  # On a fresh stack the reconciliation job fills the index a few seconds after startup.
  $exact = $null
  for ($i = 0; $i -lt 20; $i++) {
    $exact = Search-Games "Cosmic Odyssey" $token
    if (@(Get-SearchItems $exact).Count -gt 0) { break }
    Start-Sleep -Seconds 3
  }
  $items = @(Get-SearchItems $exact)
  $top = if ($items.Count -gt 0) { $items[0].title } else { "-" }
  if ($top -eq "Cosmic Odyssey") { Pass "exact 'Cosmic Odyssey' -> top hit '$top' (score $($items[0].score), total $(($exact.Body | ConvertFrom-Json).total))" } else { Fail "exact search: status $($exact.Status), top hit '$top'" }

  $typo = Search-Games "Cosmik Odisey" $token
  $items = @(Get-SearchItems $typo)
  $top = if ($items.Count -gt 0) { $items[0].title } else { "-" }
  if ($top -eq "Cosmic Odyssey") { Pass "fuzzy 'Cosmik Odisey' -> top hit '$top'" } else { Fail "fuzzy search: status $($typo.Status), top hit '$top'" }

  $none = Search-Games "zzqxv blorpt" $token
  if ($none.Status -eq 200 -and ($none.Body | ConvertFrom-Json).total -eq 0) { Pass "unknown terms -> 200 with total 0" } else { Fail "no-result search: status $($none.Status) $($none.Body)" }

  $bad = Search-Games "a" $token
  if ($bad.Status -eq 400) { Pass "q='a' -> 400 (validation)" } else { Fail "invalid query: expected 400, got $($bad.Status)" }
  $badPage = Search-Games "cosmic" $token "&pageSize=500"
  if ($badPage.Status -eq 400) { Pass "pageSize=500 -> 400 (validation)" } else { Fail "invalid page size: expected 400, got $($badPage.Status)" }

  $adminToken = Get-AdminToken
  if (-not $adminToken) { Fail "admin login failed; index synchronization checks skipped" } else {
    $title = "Nebula Smoke $stamp"
    $create = Invoke-Api "POST" "$GatewayUrl/api/games" $adminToken (@{ title = $title; description = "Created by the smoke test."; genre = "Simulation"; price = 19.9; releaseDate = "2026-01-01T00:00:00Z" } | ConvertTo-Json -Compress)
    if ($create.Status -eq 201) {
      $newId = ($create.Body | ConvertFrom-Json).id
      $hit = @(Get-SearchItems (Search-Games "Nebla Smoke $stamp" $token)) | Where-Object { $_.id -eq $newId }
      if ($hit) { Pass "created '$title' -> found right away by the misspelled 'Nebla Smoke $stamp'" } else { Fail "created game not found in the index" }

      $newTitle = "Quasar Smoke $stamp"
      $update = Invoke-Api "PUT" "$GatewayUrl/api/games/$newId" $adminToken (@{ title = $newTitle; description = "Updated by the smoke test."; genre = "Simulation"; price = 24.9; releaseDate = "2026-01-01T00:00:00Z" } | ConvertTo-Json -Compress)
      $updItems = @(Get-SearchItems (Search-Games $newTitle $token))
      if ($update.Status -eq 200 -and $updItems.Count -gt 0 -and $updItems[0].id -eq $newId -and $updItems[0].title -eq $newTitle -and [decimal]$updItems[0].price -eq 24.9) { Pass "updated to '$newTitle' -> index returns the new title and price" } else { Fail "update not reflected in the index (PUT $($update.Status))" }

      $del = Invoke-Api "DELETE" "$GatewayUrl/api/games/$newId" $adminToken $null
      $still = @(Get-SearchItems (Search-Games $newTitle $token)) | Where-Object { $_.id -eq $newId }
      if ($del.Status -eq 204 -and -not $still) { Pass "deleted game -> no longer returned by search" } else { Fail "deleted game still searchable (DELETE $($del.Status))" }
    } else { Fail "admin create game: expected 201, got $($create.Status) $($create.Body)" }

    $reindex = Invoke-Api "POST" "$GatewayUrl/api/games/search/reindex" $adminToken $null
    if ($reindex.Status -eq 200) { Pass "POST /api/games/search/reindex (Admin) -> 200, indexed $(($reindex.Body | ConvertFrom-Json).indexed) games" } else { Fail "reindex: expected 200, got $($reindex.Status)" }
    $reindexUser = Invoke-Api "POST" "$GatewayUrl/api/games/search/reindex" $token $null
    if ($reindexUser.Status -eq 403) { Pass "reindex as a regular user -> 403" } else { Fail "reindex as user: expected 403, got $($reindexUser.Status)" }

    if ($SearchOutage) {
      Write-Host "[12b] Search engine outage (docker compose stop/start elasticsearch)"
      Invoke-Compose @("stop", "elasticsearch")
      $down = Search-Games "Cosmic Odyssey" $token
      $retry = if ($down.Headers) { [string]$down.Headers["Retry-After"] } else { "" }
      if ($down.Status -eq 503) { Pass "search with Elasticsearch stopped -> 503 (Retry-After: $retry)" } else { Fail "search during outage: expected 503, got $($down.Status)" }
      $outTitle = "Outage Smoke $stamp"
      $outCreate = Invoke-Api "POST" "$GatewayUrl/api/games" $adminToken (@{ title = $outTitle; description = "Created while the search engine was down."; genre = "Test"; price = 9.9; releaseDate = "2026-01-01T00:00:00Z" } | ConvertTo-Json -Compress)
      if ($outCreate.Status -eq 201) { Pass "create game during the outage -> 201 (database first, index deferred)" } else { Fail "create during outage: expected 201, got $($outCreate.Status)" }
      Invoke-Compose @("start", "elasticsearch")
      $outId = if ($outCreate.Status -eq 201) { ($outCreate.Body | ConvertFrom-Json).id } else { "" }
      $recovered = $false
      $sw = [Diagnostics.Stopwatch]::StartNew()
      while (-not $recovered -and $sw.Elapsed.TotalSeconds -lt 180) {
        Start-Sleep -Seconds 5
        $recovered = [bool](@(Get-SearchItems (Search-Games $outTitle $token)) | Where-Object { $_.id -eq $outId })
      }
      if ($recovered) { Pass "engine back: reconciliation indexed the game created during the outage ($([int]$sw.Elapsed.TotalSeconds)s)" } else { Fail "game created during the outage not indexed within 180s" }
    }
  }
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
