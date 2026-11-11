[CmdletBinding()]
param(
    [switch]$ConfirmDestroy,
    [string]$EksctlPath = "eksctl"
)

$ErrorActionPreference = "Stop"
$clusterName = "wms-lab"
$region = "eu-north-1"
$expectedAccountId = "417392595043"
$terraformWorkspace = "aws-wms-lab"
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$infraDirectory = Split-Path -Parent $scriptDirectory

if (-not $ConfirmDestroy) {
    throw "Refusing to delete AWS resources. Re-run with -ConfirmDestroy after checking cluster=$clusterName and region=$region."
}

$accountId = aws sts get-caller-identity --query Account --output text
if ($LASTEXITCODE -ne 0 -or $accountId -ne $expectedAccountId) {
    throw "Expected AWS account $expectedAccountId, but the active account is '$accountId'."
}

if ($EksctlPath -eq "eksctl") {
    $bundledEksctl = Join-Path (Split-Path (Split-Path (Split-Path $scriptDirectory -Parent) -Parent) -Parent) ".tools\eksctl.exe"
    if (Test-Path -LiteralPath $bundledEksctl) {
        $EksctlPath = $bundledEksctl
    }
}

aws eks update-kubeconfig --region $region --name $clusterName --alias $clusterName | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Unable to update kubeconfig for $clusterName."
}

$kubectl = Get-Command kubectl -ErrorAction SilentlyContinue
if (-not $kubectl) {
    $bundledKubectl = Join-Path (Split-Path (Split-Path (Split-Path $scriptDirectory -Parent) -Parent) -Parent) ".tools\kubectl-1.37.exe"
    if (-not (Test-Path -LiteralPath $bundledKubectl)) {
        throw "kubectl was not found."
    }
    $kubectlCommand = $bundledKubectl
} else {
    $kubectlCommand = $kubectl.Source
}

$encodedPassword = & $kubectlCommand --context $clusterName get secret wms-db-secret -n wms -o "jsonpath={.data.POSTGRES_PASSWORD}"
if ($LASTEXITCODE -eq 0 -and $encodedPassword) {
    $env:TF_VAR_postgres_password = [Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String($encodedPassword)
    )
} else {
    $bytes = New-Object byte[] 24
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }
    $env:TF_VAR_postgres_password = [Convert]::ToBase64String($bytes)
}

& terraform "-chdir=$infraDirectory" workspace select $terraformWorkspace
if ($LASTEXITCODE -ne 0) {
    throw "Terraform workspace $terraformWorkspace was not found."
}

& terraform "-chdir=$infraDirectory" destroy -auto-approve "-var-file=aws/terraform.aws.tfvars"
if ($LASTEXITCODE -ne 0) {
    throw "Terraform destroy failed. The EKS cluster was intentionally left in place."
}

& $EksctlPath delete cluster --name $clusterName --region $region --wait
if ($LASTEXITCODE -ne 0) {
    throw "eksctl failed to delete $clusterName. Check CloudFormation before continuing."
}

foreach ($repository in @("wms-backend", "wms-frontend")) {
    aws ecr delete-repository --region $region --repository-name $repository --force | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to delete ECR repository $repository."
    }
}

Remove-Item Env:TF_VAR_postgres_password -ErrorAction SilentlyContinue
Write-Output "Deleted WMS Terraform resources, EKS cluster $clusterName, its VPC/NAT resources, and both WMS ECR repositories."
