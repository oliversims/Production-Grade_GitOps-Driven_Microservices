# Copy official Online Boutique images into your GHCR.
# Run once before CI/CD to seed baseline v0.10.4 images.
#
# Prerequisites:
#   $env:GHCR_PAT = classic PAT with read:packages, write:packages, delete:packages
#
# Usage:
#   cd scripts
#   $env:GHCR_PAT = "ghp_..."
#   .\push-baseline-images-to-ghcr.ps1

$ErrorActionPreference = "Stop"

# --- Settings (override with env vars if needed) ---
$GHCR_OWNER = if ($env:GHCR_OWNER) { $env:GHCR_OWNER } else { "oliversims" }
$TAG        = if ($env:TAG) { $env:TAG } else { "v0.10.4" }
$SRC        = "us-central1-docker.pkg.dev/google-samples/microservices-demo"
$DST        = "ghcr.io/$GHCR_OWNER/microservices-demo"

# All 11 microservices referenced by the Helm chart
$SERVICES = @(
  "adservice", "cartservice", "checkoutservice", "currencyservice",
  "emailservice", "frontend", "loadgenerator", "paymentservice",
  "productcatalogservice", "recommendationservice", "shippingservice"
)

if (-not $env:GHCR_PAT) {
  throw "Set GHCR_PAT first (classic PAT with read/write/delete:packages)."
}

# Headers for GitHub REST API (list + delete packages)
$headers = @{
  Authorization          = "Bearer $env:GHCR_PAT"
  Accept                 = "application/vnd.github+json"
  "X-GitHub-Api-Version" = "2022-11-28"
}

Write-Host "=== Push baseline images to GHCR ==="
Write-Host "Target: ${DST}/<service>:${TAG}"
Write-Host ""

# Step 0: Confirm PAT is a classic token with write:packages
# (docker login can succeed even when push would 403 without this scope)
Write-Host "--- Step 0: Verify PAT ---"
$userResponse = Invoke-WebRequest -Uri "https://api.github.com/user" -Headers $headers -UseBasicParsing
$login  = ($userResponse.Content | ConvertFrom-Json).login
$scopes = $userResponse.Headers["X-OAuth-Scopes"]

if ($login -ne $GHCR_OWNER) {
  Write-Warning "PAT user is '$login' but GHCR_OWNER is '$GHCR_OWNER'. Using '$login'."
  $GHCR_OWNER = $login
  $DST = "ghcr.io/$login/microservices-demo"
}

if (-not $scopes) {
  throw "Fine-grained PAT detected. Use a classic PAT from https://github.com/settings/tokens"
}
if ($scopes -notmatch "write:packages") {
  throw "PAT missing write:packages. Docker login can succeed but push will 403."
}

Write-Host "Token user: $login"
Write-Host "Token scopes: $scopes"
Write-Host ""

# Step 1: Authenticate Docker with GHCR
Write-Host "--- Step 1: Docker login ---"
docker logout ghcr.io 2>$null
$env:GHCR_PAT | docker login ghcr.io -u $GHCR_OWNER --password-stdin
if ($LASTEXITCODE -ne 0) { throw "docker login failed" }
Write-Host "Docker login OK"
Write-Host ""

# Step 2: Remove old packages so a re-run starts clean
# If the API call fails, warn and skip — first-time push still works
Write-Host "--- Step 2: Delete existing packages (if any) ---"
$expectedNames = $SERVICES | ForEach-Object { "microservices-demo/$_" }

try {
  $packages = Invoke-RestMethod `
    -Uri "https://api.github.com/user/packages?package_type=container&per_page=100" `
    -Headers $headers

  $found = $false
  foreach ($pkg in $packages) {
    if ($expectedNames -contains $pkg.name) {
      $found = $true
      Write-Host "Deleting $($pkg.name) ..."
      $encoded = [uri]::EscapeDataString($pkg.name)
      try {
        Invoke-RestMethod -Method DELETE `
          -Uri "https://api.github.com/user/packages/container/$encoded" `
          -Headers $headers
        Write-Host "  Deleted."
      } catch {
        if ($_.Exception.Response.StatusCode.value__ -ne 404) { throw }
        Write-Host "  Already gone."
      }
    }
  }
  if (-not $found) {
    Write-Host "No existing packages to delete."
  }
} catch {
  Write-Warning "Could not list packages: $($_.Exception.Message)"
  Write-Warning "Skipping cleanup, continuing to push."
}
Write-Host ""

# Step 3: For each service — pull from Google, retag, push to GHCR
Write-Host "--- Step 3: Pull, tag, and push ---"
foreach ($SERVICE in $SERVICES) {
  Write-Host "--- $SERVICE ---"

  docker pull "${SRC}/${SERVICE}:${TAG}"
  if ($LASTEXITCODE -ne 0) { throw "docker pull failed: $SERVICE" }

  docker tag "${SRC}/${SERVICE}:${TAG}" "${DST}/${SERVICE}:${TAG}"

  docker push "${DST}/${SERVICE}:${TAG}"
  if ($LASTEXITCODE -ne 0) { throw "docker push failed: $SERVICE (check write:packages scope)" }

  Write-Host "Pushed ${DST}/${SERVICE}:${TAG}"
  Write-Host ""
}

Write-Host "=== Done: $($SERVICES.Count) images pushed ==="
Write-Host "Next: .\push-helm-chart-to-ghcr.ps1"
