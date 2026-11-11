# AWS EKS lab environment

This directory defines the temporary EKS cluster used by the WMS laboratory.

- Region: `eu-north-1`
- Cluster: `wms-lab`
- Kubernetes: `1.37`
- Compute: one managed `c7i-flex.large` node (the smallest 4 GiB type
  permitted by this lab account's Free Tier allow-list)
- Managed node group: `wms-workers-ft`
- Storage: encrypted EBS `gp3`
- Lifetime tag: `expires-after=2026-11-14`

The EKS cluster is created by `eksctl` from `cluster.yaml`. The application
resources remain managed by the Terraform configuration in the parent `infra`
directory, using a dedicated `aws-wms-lab` Terraform workspace so the existing
Minikube state is not modified.

The frontend is exposed by an AWS LoadBalancer Service restricted to the CIDR
configured in `terraform.tfvars.aws`. Prometheus stays private and is accessed
with `kubectl port-forward`.

Destroy the Terraform application resources before deleting the EKS cluster so
AWS can clean up the Load Balancer and EBS volume correctly.

The AWS Organizations policy attached to this lab account explicitly blocks
IAM OpenID Connect provider reads. Therefore the EBS CSI policy is attached to
the temporary managed-node role and the managed EKS add-ons are installed via
the EKS API without IRSA. No long-lived AWS access keys are stored in this
repository.

## Create the cluster

```powershell
eksctl create cluster -f infra/aws/cluster.yaml
aws eks update-kubeconfig --region eu-north-1 --name wms-lab --alias wms-lab
```

The lab account cannot use an IAM OIDC provider. Install any missing managed
add-ons directly through the EKS API; the node role already carries the EBS CSI
policy required by this short-lived environment:

```powershell
$addons = "vpc-cni", "kube-proxy", "coredns", "metrics-server", "aws-ebs-csi-driver"
foreach ($addon in $addons) {
  aws eks describe-addon --region eu-north-1 --cluster-name wms-lab `
    --addon-name $addon 2>$null
  if ($LASTEXITCODE -ne 0) {
    aws eks create-addon --region eu-north-1 --cluster-name wms-lab `
      --addon-name $addon --resolve-conflicts OVERWRITE
  }
}
```

Copy `terraform.tfvars.example` to the ignored `terraform.aws.tfvars`, replace
the placeholders, select the `aws-wms-lab` workspace, and pass the database
password only through `TF_VAR_postgres_password`.

## Destroy the temporary environment

Run the guarded cleanup script from the repository root after the laboratory:

```powershell
.\infra\aws\destroy.ps1 -ConfirmDestroy
```

The script verifies AWS account `417392595043`, destroys the Terraform-managed
Load Balancer and EBS volume first, then deletes only `wms-lab` and the two WMS
ECR repositories.
