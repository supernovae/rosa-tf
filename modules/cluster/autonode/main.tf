#------------------------------------------------------------------------------
# AutoNode (Karpenter) Private Preview - IAM and Subnet Discovery
#
# Creates the IAM resources required for the ROSA HCP AutoNode private preview:
# 1. Karpenter controller IAM policy (EC2, IAM, SSM, SQS, Pricing)
# 2. Karpenter IAM role with OIDC trust for kube-system:karpenter SA
# 3. ec2:CreateTags inline policy on the control-plane-operator role
# 4. Karpenter discovery tags on private subnets
#
# After terraform apply, the user must manually run:
#   rosa edit cluster -c <cluster_id> --autonode=enabled \
#     --autonode-iam-role-arn=<karpenter_role_arn>
#------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id

  karpenter_service_account = "system:serviceaccount:kube-system:karpenter"

  control_plane_operator_role_name = substr(
    "${var.operator_role_prefix}-kube-system-control-plane-operator",
    0, 64
  )
}

#------------------------------------------------------------------------------
# 1. Karpenter Controller IAM Policy
#
# Grants permissions for the Karpenter controller to manage EC2 instances,
# launch templates, instance profiles, and related resources.
# Policy statements are scoped with conditions (karpenter.sh/nodepool,
# karpenter.k8s.aws/ec2nodeclass) to limit blast radius.
#------------------------------------------------------------------------------

resource "aws_iam_policy" "karpenter" {
  #checkov:skip=CKV_AWS_290:Karpenter requires EC2 write actions (RunInstances, CreateFleet) scoped by karpenter.sh/nodepool condition tags. AWS Describe/List/SQS actions inherently require Resource="*".
  #checkov:skip=CKV_AWS_355:AWS EC2 Describe*, pricing:GetProducts, and sqs:ReceiveMessage do not support resource-level constraints and require Resource="*". This is the AWS-documented Karpenter controller policy.
  name        = "${var.cluster_name}-autonode-karpenter"
  description = "ROSA HCP AutoNode private preview - Karpenter controller permissions"
  path        = "/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowScopedEC2InstanceAccessActions"
        Effect = "Allow"
        Resource = [
          "arn:*:ec2:*::image/*",
          "arn:*:ec2:*::snapshot/*",
          "arn:*:ec2:*:*:security-group/*",
          "arn:*:ec2:*:*:subnet/*"
        ]
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]
      },
      {
        Sid      = "AllowScopedEC2LaunchTemplateAccessActions"
        Effect   = "Allow"
        Resource = "arn:*:ec2:*:*:launch-template/*"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]
      },
      {
        Sid    = "AllowScopedEC2InstanceActionsWithTags"
        Effect = "Allow"
        Resource = [
          "arn:*:ec2:*:*:fleet/*",
          "arn:*:ec2:*:*:instance/*",
          "arn:*:ec2:*:*:volume/*",
          "arn:*:ec2:*:*:network-interface/*",
          "arn:*:ec2:*:*:launch-template/*",
          "arn:*:ec2:*:*:spot-instances-request/*"
        ]
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate"
        ]
        Condition = {
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedResourceCreationTagging"
        Effect = "Allow"
        Resource = [
          "arn:*:ec2:*:*:fleet/*",
          "arn:*:ec2:*:*:instance/*",
          "arn:*:ec2:*:*:volume/*",
          "arn:*:ec2:*:*:network-interface/*",
          "arn:*:ec2:*:*:launch-template/*",
          "arn:*:ec2:*:*:spot-instances-request/*"
        ]
        Action = "ec2:CreateTags"
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = [
              "RunInstances",
              "CreateFleet",
              "CreateLaunchTemplate"
            ]
          }
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedResourceTagging"
        Effect   = "Allow"
        Resource = "arn:*:ec2:*:*:instance/*"
        Action   = "ec2:CreateTags"
        Condition = {
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedDeletion"
        Effect = "Allow"
        Resource = [
          "arn:*:ec2:*:*:instance/*",
          "arn:*:ec2:*:*:launch-template/*"
        ]
        Action = [
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate"
        ]
        Condition = {
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid      = "AllowRegionalReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets"
        ]
      },
      {
        Sid      = "AllowSSMReadActions"
        Effect   = "Allow"
        Resource = "arn:*:ssm:*::parameter/aws/service/*"
        Action   = "ssm:GetParameter"
      },
      {
        Sid      = "AllowPricingReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action   = "pricing:GetProducts"
      },
      {
        Sid      = "AllowInterruptionQueueActions"
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage"
        ]
      },
      {
        Sid      = "AllowPassingInstanceRole"
        Effect   = "Allow"
        Resource = "arn:*:iam::*:role/*"
        Action   = "iam:PassRole"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = [
              "ec2.amazonaws.com",
              "ec2.amazonaws.com.cn"
            ]
          }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileCreationActions"
        Effect   = "Allow"
        Resource = "arn:*:iam::*:instance-profile/*"
        Action   = ["iam:CreateInstanceProfile"]
        Condition = {
          StringLike = {
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileTagActions"
        Effect   = "Allow"
        Resource = "arn:*:iam::*:instance-profile/*"
        Action   = ["iam:TagInstanceProfile"]
        Condition = {
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"  = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileActions"
        Effect   = "Allow"
        Resource = "arn:*:iam::*:instance-profile/*"
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile"
        ]
        Condition = {
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },
      {
        Sid      = "AllowInstanceProfileReadActions"
        Effect   = "Allow"
        Resource = "arn:*:iam::*:instance-profile/*"
        Action   = "iam:GetInstanceProfile"
      }
    ]
  })

  tags = merge(var.tags, {
    Name      = "${var.cluster_name}-autonode-karpenter"
    autonode  = "private-preview"
  })
}

#------------------------------------------------------------------------------
# 2. Karpenter IAM Role with OIDC Trust
#
# Allows the kube-system:karpenter service account in the cluster to
# assume this role via web identity federation (IRSA pattern).
#------------------------------------------------------------------------------

data "aws_iam_policy_document" "karpenter_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:oidc-provider/${var.oidc_endpoint_url}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_endpoint_url}:sub"
      values   = [local.karpenter_service_account]
    }
  }
}

resource "aws_iam_role" "karpenter" {
  name               = "${var.cluster_name}-autonode-karpenter"
  assume_role_policy = data.aws_iam_policy_document.karpenter_trust.json
  path               = "/"

  tags = merge(var.tags, {
    Name     = "${var.cluster_name}-autonode-karpenter"
    autonode = "private-preview"
  })
}

resource "aws_iam_role_policy_attachment" "karpenter" {
  role       = aws_iam_role.karpenter.name
  policy_arn = aws_iam_policy.karpenter.arn
}

#------------------------------------------------------------------------------
# 2b. ECR Pull Policy (Optional)
#
# Grants Karpenter-launched nodes permission to pull container images from
# ECR. Required when GPU or other pools need OCI model images from ECR.
#------------------------------------------------------------------------------

resource "aws_iam_role_policy" "karpenter_ecr_pull" {
  #checkov:skip=CKV_AWS_355:ecr:GetAuthorizationToken requires Resource="*" per AWS docs. Remaining ECR read actions are scoped to pull-only (no push/delete). Karpenter nodes need access to pull images from any ECR repo.
  count = var.enable_ecr_pull ? 1 : 0
  name  = "autonode-ecr-pull"
  role  = aws_iam_role.karpenter.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# 3. Control Plane Operator - ec2:CreateTags Permission
#
# HyperShift needs ec2:CreateTags on the control-plane-operator role so it
# can automatically tag the cluster's default security group with the
# Karpenter discovery tag. Without this, the default EC2NodeClass will
# report SecurityGroupsReady=False.
#------------------------------------------------------------------------------

resource "aws_iam_role_policy" "control_plane_create_tags" {
  name = "autonode-ec2-create-tags"
  role = local.control_plane_operator_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowCreateTagsOnManagedResources"
        Effect   = "Allow"
        Action   = ["ec2:CreateTags"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/red-hat-managed" = "true"
          }
        }
      }
    ]
  })
}

#------------------------------------------------------------------------------
# 4. Karpenter Subnet Discovery Tags
#
# Tags each private subnet with karpenter.sh/discovery = <cluster_id>
# so the Karpenter controller can auto-discover subnets for node placement.
# The cluster_id (OCM internal ID) is used as the discovery value.
#------------------------------------------------------------------------------

resource "aws_ec2_tag" "karpenter_subnet_discovery" {
  count = length(var.private_subnet_ids)

  resource_id = var.private_subnet_ids[count.index]
  key         = "karpenter.sh/discovery"
  value       = var.cluster_id
}
