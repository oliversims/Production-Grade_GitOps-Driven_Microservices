# Package and push the Helm chart to GHCR.
# Run AFTER push-baseline-images-to-ghcr.ps1
#
# Prerequisites:
#   $env:GHCR_PAT | helm registry login ghcr.io -u oliversims --password-stdin
#
# Usage:
#   cd scripts
#   .\push-helm-chart-to-ghcr.ps1

$ErrorActionPreference = "Stop"

# --- Settings (override with env vars if needed) ---
$GHCR_OWNER    = if ($env:GHCR_OWNER) { $env:GHCR_OWNER } else { "oliversims" }
$CHART_VERSION = "0.10.4"
$CHART_DIR     = Join-Path $PSScriptRoot "..\helm-chart" | Resolve-Path

Write-Host "=== Push Helm chart to GHCR ==="
Write-Host "Chart: oci://ghcr.io/${GHCR_OWNER}/onlineboutique:${CHART_VERSION}"
Write-Host ""

Set-Location $CHART_DIR

# Step 1: Build onlineboutique-0.10.4.tgz from the local chart
Write-Host "--- Step 1: Package chart ---"
helm package .
if ($LASTEXITCODE -ne 0) { throw "helm package failed" }
Write-Host ""

# Step 2: Upload the .tgz to GHCR as an OCI artifact
Write-Host "--- Step 2: Push to GHCR ---"
helm push "onlineboutique-${CHART_VERSION}.tgz" "oci://ghcr.io/${GHCR_OWNER}"
if ($LASTEXITCODE -ne 0) { throw "helm push failed (run helm registry login first)" }

Write-Host ""
Write-Host "=== Done ==="
Write-Host "Chart: oci://ghcr.io/${GHCR_OWNER}/onlineboutique:${CHART_VERSION}"
