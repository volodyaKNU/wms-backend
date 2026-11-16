# wms-backend

Node.js/Express API and Docker Compose infrastructure for the WMS individual
project.

## Requirements

- Node.js 22+
- PostgreSQL

## Setup

```bash
npm install
cp .env.example .env
psql "$DATABASE_URL" -f infra/schema.sql
npm start
```

Health check:

```bash
GET /health
```

Prometheus metrics:

```bash
GET /metrics
```

## Docker Compose

Clone `wms-backend` and `wms-frontend` as sibling folders, then run from the
parent folder. The database password has no default and must come from the
shell or an ignored `infra/.env` file (see `infra/.env.example`):

```bash
export POSTGRES_PASSWORD="$(openssl rand -hex 24)"
docker compose -f wms-backend/infra/docker-compose.yml up -d --build --wait
```

The command starts PostgreSQL, the Express backend, and the Nginx frontend. Open
<http://localhost:5173>; the API health endpoint is available at
<http://localhost:4000/health>.

Stop the stack while keeping database data:

```bash
docker compose -f wms-backend/infra/docker-compose.yml down
```

Add `-v` to also delete the PostgreSQL volume.

API:

```text
GET    /api/products
GET    /api/products/:id
POST   /api/products
PUT    /api/products/:id
DELETE /api/products/:id
POST   /api/products/:id/income
POST   /api/products/:id/writeoff
GET    /api/movements
```

## Kubernetes (Minikube)

The manifests in `infra/k8s` deploy the frontend, backend, PostgreSQL, and
Prometheus to the `wms` namespace. PostgreSQL uses a persistent volume, while
liveness and readiness probes let Kubernetes track the health of every
component. Prometheus scrapes `wms-backend-service:4000/metrics` every 15
seconds.

Start Docker Desktop, then run from the repository root in PowerShell:

```powershell
$env:WMS_POSTGRES_PASSWORD = 'choose-a-local-password'
.\infra\k8s\deploy.ps1
```

The script starts Minikube when needed, builds both application images inside
Minikube, creates the Kubernetes Secret without writing it to disk, applies the
manifests, and waits for all three workloads to become ready.

Inspect the deployment and open the frontend:

```powershell
kubectl get all,pvc -n wms
minikube service wms-frontend-service -n wms
```

To reapply manifests without rebuilding images, use
`kubectl apply -k infra/k8s`. Database data remains in the
`wms-db-data` PersistentVolumeClaim when pods restart.

## Terraform

The Terraform configuration in `infra` reproduces the same Namespace,
ConfigMaps, Secret, Services, Deployments, PostgreSQL StatefulSet, and
PersistentVolumeClaim. Build the local images with the Kubernetes deployment
script first, then apply the infrastructure from `infra`:

```powershell
$env:TF_VAR_postgres_password = 'choose-a-local-password'
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=wms.tfplan
terraform apply wms.tfplan
```

The password is a sensitive input and must be supplied through an environment
variable or an ignored `terraform.tfvars` file. Do not commit real credentials.
The CI workflow runs `terraform fmt -check -recursive` and `terraform validate`
for every push and pull request.

After apply completes, inspect the resources and open the frontend:

```powershell
kubectl get pods,services,pvc -n wms
minikube service wms-frontend-service -n wms
minikube service wms-prometheus-service -n wms
```

## CI and container image

Pull requests build the full three-container stack and run frontend Cypress
tests. A successful push to `main` publishes
`ghcr.io/volodyaknu/wms-backend:latest` and an immutable image tagged with the
commit SHA.

After publishing on `main`, the `deploy` job updates only the backend image in
the existing `wms` namespace and waits for the rollout. The frontend repository
has the equivalent job for `wms-frontend`. These jobs use a self-hosted runner
because a local Minikube API is not reachable from a GitHub-hosted runner.

Register the machine that owns Minikube as a repository or organization
self-hosted runner with the `wms-minikube` label, give it `kubectl` access to
the `minikube` context, and set the repository variable
`ENABLE_MINIKUBE_CD=true`. Until that variable is enabled, the deploy job is
skipped so a missing local runner cannot leave the main workflow queued. The
cross-repository integration checkout uses the `CROSS_REPO_TOKEN` GitHub
Actions secret when the default `GITHUB_TOKEN` cannot read the sibling
repository. Database credentials are never committed: `deploy.ps1` creates the
`wms-db-secret` Kubernetes Secret from `WMS_POSTGRES_PASSWORD`, and Terraform
accepts the same value through the sensitive `TF_VAR_postgres_password`
variable.

## Continuous deployment to AWS EKS

Every push to `main` in `wms-backend` or `wms-frontend` runs the full pipeline:
tests → image build → push to Amazon ECR (`<account>.dkr.ecr.eu-north-1.amazonaws.com/wms-<app>:<commit-sha>`,
also mirrored to GHCR) → the `deploy-eks` job updates the Deployment in the
`wms-lab` cluster.

The `deploy-eks` job:

1. authenticates to AWS and runs `aws eks update-kubeconfig`;
2. (backend only) syncs the `wms-db-secret` Kubernetes Secret from the
   `WMS_POSTGRES_PASSWORD` GitHub Actions secret;
3. runs `kubectl set image` with the immutable commit-SHA tag and waits for
   `kubectl rollout status`;
4. verifies the release: the backend checks `/metrics` and that the Prometheus
   `wms-backend` scrape target is `up`; the frontend checks the SPA and the
   `/api` proxy;
5. on any failure restores the previous Secret value and runs
   `kubectl rollout undo`.

Terraform ignores the container image of both Deployments
(`lifecycle.ignore_changes`), so `terraform apply` never reverts a version
rolled out by CI.

### GitHub configuration

| Kind | Name | Repositories | Purpose |
|------|------|--------------|---------|
| Secret | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | both | IAM user `wms-github-deployer` |
| Secret | `WMS_POSTGRES_PASSWORD` | backend | value of the `wms-db-secret` Kubernetes Secret |
| Secret | `AWS_ROLE_ARN` (optional) | both | use GitHub OIDC instead of access keys |
| Variable | `ENABLE_EKS_CD=true` | both | enables the `deploy-eks` job |
| Variable | `AWS_REGION`, `EKS_CLUSTER_NAME` (optional) | both | defaults: `eu-north-1`, `wms-lab` |

The lab account's AWS Organizations SCP denies IAM OIDC providers, so GitHub
OIDC cannot be used here and the pipeline falls back to access keys. The
`wms-github-deployer` IAM user is limited to pushing the two WMS ECR
repositories and `eks:DescribeCluster` on `wms-lab`. Inside Kubernetes its EKS
access entry has `AmazonEKSEditPolicy` scoped to the `wms` namespace only.

No credentials are stored in the repository: Docker Compose requires
`POSTGRES_PASSWORD` (CI generates a throwaway one per run), Terraform takes
`TF_VAR_postgres_password`, and production values live only in GitHub Actions
secrets and the `wms-db-secret` Kubernetes Secret.

### Public endpoints on the AWS test stand

Both Services use an AWS LoadBalancer with no source-IP restriction
(`frontend_load_balancer_source_ranges = null`,
`prometheus_service_type = "LoadBalancer"`):

- WMS UI: `http://<frontend-lb-hostname>/` (`terraform output frontend_load_balancer_hostname`)
- Prometheus UI: `http://<prometheus-lb-hostname>:9090/` (`terraform output prometheus_load_balancer_hostname`)

Prometheus has no authentication, so this setup is meant only for the
temporary lab environment.
