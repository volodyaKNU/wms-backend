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

## Terraform (AWS infrastructure as code)

The whole AWS environment, from the VPC to the application, is described in
`infra/terraform` as three layers. Each layer has its own remote state in S3,
so a change to the application never touches the network or the cluster.

```text
infra/terraform/
├── bootstrap/  S3 state bucket (versioned, encrypted, TLS-only, S3 native locking)
│               + IAM user wms-terraform-ci used by GitHub Actions
├── aws/        VPC (3 AZ, public + private subnets, single NAT gateway)
│               EKS cluster wms-eks + managed node group (c7i-flex.large)
│               add-ons: vpc-cni, kube-proxy, coredns, eks-pod-identity-agent,
│                        aws-ebs-csi-driver (Pod Identity), metrics-server
│               EKS access entries, ECR repositories, IAM user wms-github-deployer
└── k8s/        namespace wms, ConfigMaps, Secret, gp3 StorageClass, PostgreSQL
                StatefulSet + PVC, backend, frontend, Prometheus, LoadBalancers
```

| Layer | State key | Applied by |
|-------|-----------|------------|
| bootstrap | `bootstrap/terraform.tfstate` | locally, once (it creates the bucket and the CI user) |
| aws | `aws/terraform.tfstate` | GitHub Actions on `main`, or locally |
| k8s | `k8s/terraform.tfstate` | GitHub Actions on `main`, or locally |

The k8s layer reads the cluster endpoint and the ECR URLs from the aws layer
state (`terraform_remote_state`) and authenticates with `aws eks get-token`, so
no kubeconfig is required.

Account-specific constraints:

- The AWS Organizations SCP denies IAM OIDC providers. IRSA is therefore
  disabled (`enable_irsa = false`); the EBS CSI driver gets its permissions via
  **EKS Pod Identity**, and GitHub Actions uses IAM access keys instead of OIDC.
- Cluster admins are listed explicitly (`cluster_admin_role_arns` plus the
  Terraform CI user) instead of "whoever ran Terraform", so local and CI
  applies do not overwrite each other's access entries.
- The node type must be on the account's Free Tier allow-list.

### Running Terraform locally

```bash
aws login                                     # any admin session for the account
export TF_VAR_postgres_password='...'         # same value as the WMS_POSTGRES_PASSWORD secret

terraform -chdir=infra/terraform/aws init
terraform -chdir=infra/terraform/aws plan -out=tfplan
terraform -chdir=infra/terraform/aws apply tfplan

terraform -chdir=infra/terraform/k8s init
terraform -chdir=infra/terraform/k8s plan -out=tfplan
terraform -chdir=infra/terraform/k8s apply tfplan

terraform -chdir=infra/terraform/k8s output     # frontend_url, prometheus_url
aws eks update-kubeconfig --region eu-north-1 --name wms-eks --alias wms-eks
```

Creating the environment from scratch takes about 20 minutes: bootstrap (once),
then aws, then k8s. Destroy in reverse order: `k8s` first, so that Kubernetes
deletes the load balancers and the EBS volume, then `aws`.

### Terraform in GitHub Actions (`.github/workflows/terraform.yml`)

Triggered by changes under `infra/terraform/**`:

- **pull request**: `terraform plan` for aws and k8s; the plan is posted as a
  PR comment and in the job summary;
- **push to `main`**: `plan` + `apply` for aws, then for k8s (environment
  `terraform-lab`, add required reviewers there to gate applies).

`Backend CI/CD` additionally runs `terraform fmt -check` and `validate` for all
three layers on every push.

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
`wms-eks` cluster.

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
| Secret | `WMS_POSTGRES_PASSWORD` | backend | value of the `wms-db-secret` Kubernetes Secret (CD + Terraform) |
| Secret | `TF_AWS_ACCESS_KEY_ID`, `TF_AWS_SECRET_ACCESS_KEY` | backend | IAM user `wms-terraform-ci` (Terraform plan/apply) |
| Secret | `AWS_ROLE_ARN` (optional) | both | use GitHub OIDC instead of access keys |
| Variable | `ENABLE_EKS_CD=true` | both | enables the `deploy-eks` job |
| Variable | `AWS_REGION`, `EKS_CLUSTER_NAME` (optional) | both | defaults: `eu-north-1`, `wms-eks` |

The lab account's AWS Organizations SCP denies IAM OIDC providers, so GitHub
OIDC cannot be used here and the pipeline falls back to access keys. The
`wms-github-deployer` IAM user is limited to pushing the two WMS ECR
repositories and `eks:DescribeCluster` on `wms-eks` (managed in `infra/terraform/aws/iam-ci.tf`). Inside Kubernetes its EKS
access entry has `AmazonEKSEditPolicy` scoped to the `wms` namespace only.

No credentials are stored in the repository: Docker Compose requires
`POSTGRES_PASSWORD` (CI generates a throwaway one per run), Terraform takes
`TF_VAR_postgres_password`, and production values live only in GitHub Actions
secrets and the `wms-db-secret` Kubernetes Secret.

### Public endpoints on the AWS test stand

Both Services use an AWS LoadBalancer with no source-IP restriction
(`frontend_load_balancer_source_ranges = null`,
`prometheus_service_type = "LoadBalancer"`):

- WMS UI: `http://<frontend-lb-hostname>/` (`terraform -chdir=infra/terraform/k8s output frontend_url`)
- Prometheus UI: `http://<prometheus-lb-hostname>:9090/` (`terraform -chdir=infra/terraform/k8s output prometheus_url`)

Prometheus has no authentication, so this setup is meant only for the
temporary lab environment.
