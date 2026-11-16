locals {
  cluster_admins = merge(var.cluster_admin_role_arns, {
    terraform-ci = data.terraform_remote_state.bootstrap.outputs.terraform_ci_user_arn
  })
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access  = true
  endpoint_private_access = true

  # Access is managed only through EKS access entries (no aws-auth ConfigMap).
  authentication_mode = "API"

  # Explicit admins instead of "whoever ran terraform", so local and CI applies
  # do not keep replacing each other's access.
  enable_cluster_creator_admin_permissions = false
  kms_key_administrators                   = values(local.cluster_admins)

  # The account's AWS Organizations SCP denies IAM OIDC providers, so IRSA is
  # disabled. Add-ons that need AWS permissions use EKS Pod Identity instead.
  enable_irsa = false

  enabled_log_types                      = ["audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 7

  access_entries = merge(
    {
      for name, arn in local.cluster_admins : name => {
        principal_arn = arn
        policy_associations = {
          admin = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    },
    {
      github-deployer = {
        principal_arn = aws_iam_user.github_deployer.arn
        policy_associations = {
          edit = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
            access_scope = {
              type       = "namespace"
              namespaces = [var.app_namespace]
            }
          }
        }
      }
    }
  )

  addons = {
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    coredns    = {}
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs_csi.arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
    metrics-server = {}
  }

  eks_managed_node_groups = {
    wms = {
      instance_types = [var.node_instance_type]
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      desired_size = var.node_desired_size
      max_size     = var.node_max_size

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 20
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      labels = {
        workload = "wms"
      }
    }
  }
}

################################################################################
# EBS CSI driver permissions via EKS Pod Identity
################################################################################

data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
