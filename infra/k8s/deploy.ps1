[CmdletBinding()]
param(
  [string]$PostgresPassword = $env:WMS_POSTGRES_PASSWORD,
  [switch]$SkipImageBuild
)

$ErrorActionPreference = 'Stop'

$k8sDirectory = $PSScriptRoot
$backendDirectory = (Resolve-Path (Join-Path $k8sDirectory '..\..')).Path
$workspaceDirectory = Split-Path $backendDirectory -Parent
$frontendDirectory = Join-Path $workspaceDirectory 'wms-frontend'

foreach ($commandName in @('docker', 'kubectl', 'minikube')) {
  if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
    throw "Required command '$commandName' was not found in PATH."
  }
}

if (-not (Test-Path -LiteralPath $frontendDirectory)) {
  throw "Frontend repository was not found at '$frontendDirectory'."
}

$minikubeHost = (& minikube status --format='{{.Host}}' 2>$null)
if ($LASTEXITCODE -ne 0 -or $minikubeHost -ne 'Running') {
  Write-Host 'Starting Minikube with the Docker driver...'
  & minikube start --driver=docker
  if ($LASTEXITCODE -ne 0) {
    throw 'Minikube failed to start.'
  }
}

if (-not $SkipImageBuild) {
  Write-Host 'Building backend image inside Minikube...'
  & minikube image build -t wms-backend:local $backendDirectory
  if ($LASTEXITCODE -ne 0) {
    throw 'Backend image build failed.'
  }

  Write-Host 'Building frontend image inside Minikube...'
  & minikube image build -t wms-frontend:local $frontendDirectory
  if ($LASTEXITCODE -ne 0) {
    throw 'Frontend image build failed.'
  }
}

& kubectl apply -f (Join-Path $k8sDirectory 'namespace.yaml')
if ($LASTEXITCODE -ne 0) {
  throw 'Failed to create the wms namespace.'
}

$secretName = (& kubectl get secret wms-db-secret -n wms --ignore-not-found -o name)
$secretExists = $secretName -eq 'secret/wms-db-secret'

if ([string]::IsNullOrWhiteSpace($PostgresPassword)) {
  if (-not $secretExists) {
    throw 'Set WMS_POSTGRES_PASSWORD or pass -PostgresPassword before the first deployment.'
  }
  Write-Host 'Reusing the existing wms-db-secret.'
} else {
  $secretYaml = & kubectl create secret generic wms-db-secret `
    --namespace wms `
    --from-literal="POSTGRES_PASSWORD=$PostgresPassword" `
    --dry-run=client `
    -o yaml
  if ($LASTEXITCODE -ne 0) {
    throw 'Failed to generate the database Secret.'
  }

  $secretYaml | & kubectl apply -f -
  if ($LASTEXITCODE -ne 0) {
    throw 'Failed to apply the database Secret.'
  }
}

& kubectl apply -k $k8sDirectory
if ($LASTEXITCODE -ne 0) {
  throw 'Failed to apply the Kubernetes manifests.'
}

if (-not $SkipImageBuild) {
  & kubectl rollout restart deployment/wms-backend deployment/wms-frontend -n wms
  if ($LASTEXITCODE -ne 0) {
    throw 'Failed to restart the application deployments.'
  }
}

Write-Host 'Waiting for PostgreSQL...'
& kubectl rollout status statefulset/wms-db -n wms --timeout=180s
if ($LASTEXITCODE -ne 0) {
  throw 'PostgreSQL did not become ready in time.'
}

Write-Host 'Waiting for the backend...'
& kubectl rollout status deployment/wms-backend -n wms --timeout=180s
if ($LASTEXITCODE -ne 0) {
  throw 'Backend did not become ready in time.'
}

Write-Host 'Waiting for the frontend...'
& kubectl rollout status deployment/wms-frontend -n wms --timeout=180s
if ($LASTEXITCODE -ne 0) {
  throw 'Frontend did not become ready in time.'
}

Write-Host 'Waiting for Prometheus...'
& kubectl rollout status deployment/wms-prometheus -n wms --timeout=180s
if ($LASTEXITCODE -ne 0) {
  throw 'Prometheus did not become ready in time.'
}

& kubectl get pods,services,pvc -n wms
Write-Host ''
Write-Host 'WMS is ready. Open it with:'
Write-Host 'minikube service wms-frontend-service -n wms'
Write-Host 'Prometheus: minikube service wms-prometheus-service -n wms'
