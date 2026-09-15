# Builds the Phase 3 images with local tags for Docker Desktop Kubernetes.
# Docker Desktop shares the image store, so no load step is needed
# (manifests use imagePullPolicy: IfNotPresent + a non-latest tag).
# The Phase 2 notifications-api is NOT built: the Notifications Function replaced it.
#
# NOTE: we do NOT set $ErrorActionPreference='Stop' here, because `docker build`
# writes normal progress to stderr; under PowerShell that would abort the script.
# Instead we check $LASTEXITCODE after each build.
$root = Split-Path (Split-Path $PSScriptRoot)   # ...\Projects (parent of orchestration)

$images = @(
  @{ tag = "fcg-users-api:local";              path = "fiap-cloud-games-users-api" },
  @{ tag = "fcg-catalog-api:local";            path = "fiap-cloud-games-catalog-api" },
  @{ tag = "fcg-payments-api:local";           path = "fiap-cloud-games-payments-api" },
  @{ tag = "fcg-notifications-function:local"; path = "fiap-cloud-games-notifications-function" }
)

foreach ($i in $images) {
  Write-Host "Building $($i.tag) ..."
  docker build -t $i.tag "$root\$($i.path)"
  if ($LASTEXITCODE -ne 0) { throw "Build failed for $($i.tag)" }
}
Write-Host "Done: fcg-users-api:local, fcg-catalog-api:local, fcg-payments-api:local, fcg-notifications-function:local"
Write-Host "Already deployed? Restart to pick up the new images: kubectl -n fcg rollout restart deploy/users-api deploy/catalog-api deploy/payments-api deploy/notifications-function"

# For kind/minikube instead of Docker Desktop, load the images after building, e.g.:
#   kind load docker-image fcg-users-api:local
#   minikube image load fcg-users-api:local
