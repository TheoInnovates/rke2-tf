module "init" {
  source = "./modules/userdata"

  server_url    = module.cp_lb.dns
  token_bucket  = module.statestore.bucket
  token_object  = module.statestore.token_object
  config        = var.rke2_config
  pre_userdata  = var.pre_userdata
  post_userdata = var.post_userdata
  ccm           = var.enable_ccm
  ccm_external  = var.ccm_external
  agent         = false
  rke2_start    = var.rke2_start
  nginx_replica_count  = var.nginx_replica_count
  nlb_scheme          = var.nlb_scheme
  nginx_cpu_limit     = var.nginx_cpu_limit
  nginx_memory_limit  = var.nginx_memory_limit
  nginx_cpu_request   = var.nginx_cpu_request
  nginx_memory_request = var.nginx_memory_request
  public_subnets              = join(",", module.vpc.public_subnets)
}

data "cloudinit_config" "this" {
  gzip          = true
  base64_encode = true

  # Main cloud-init config file
  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/modules/nodepool/files/cloud-config.yaml", {
      ssh_authorized_keys       = var.ssh_authorized_keys
      extra_cloud_config_config = var.extra_cloud_config_config
    })
  }

  part {
    filename     = "00_pre.sh"
    content_type = "text/x-shellscript"
    content      = module.init.pre_templated
  }

  dynamic "part" {
    for_each = var.download ? [1] : []
    content {
      filename     = "10_download.sh"
      content_type = "text/x-shellscript"
      content = templatefile("${path.module}/modules/common/download.sh", {
        # Must not use `version` here since that is reserved
        rke2_channel            = var.rke2_channel
        rke2_version            = var.rke2_version
        type                    = "server"
        rke2_install_script_url = var.rke2_install_script_url
        awscli_url              = var.awscli_url
        unzip_rpm_url           = var.unzip_rpm_url
      })
    }
  }

  part {
    filename     = "20_rke2.sh"
    content_type = "text/x-shellscript"
    content      = module.init.rke2_templated
  }

  part {
    filename     = "99_post.sh"
    content_type = "text/x-shellscript"
    content      = module.init.post_templated
  }
}

#
# IAM Policies
#
data "aws_iam_policy_document" "aws_required" {
  count = var.iam_instance_profile == "" ? 1 : 0

  # "Leader election" requires querying the instances autoscaling group/instances
  statement {
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
    ]
  }
}

data "aws_iam_policy_document" "ssm_session" {
  statement {
    effect = "Allow"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssm:DescribeInstanceInformation",
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
      "ssm:ListCommands",
      "ssm:SendCommand",
      "ssm:StartSession",
      "ssm:TerminateSession",
      "ssm:DescribeSessions",
      "ssm:GetSession",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2:DescribeInstances"
    ]

    resources = ["*"]
  }
}

# Required IAM Policy for AWS CCM
data "aws_iam_policy_document" "aws_ccm" {
  count = var.iam_instance_profile == "" && var.enable_ccm ? 1 : 0

  statement {
    effect    = "Allow"
    resources = ["*"]
    actions = [
      # Auto Scaling permissions
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "autoscaling:DescribeAutoScalingInstances",

      # EC2 permissions
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVolumes",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeNetworkInterfaceAttribute",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcEndpoints",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeCoipPools",
      "ec2:GetCoipPoolUsage",

      # EC2 modification permissions
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:CreateNetworkInterface",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyVolume",
      "ec2:ModifyNetworkInterfaceAttribute",
      "ec2:AttachVolume",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteVolume",
      "ec2:DeleteNetworkInterface",
      "ec2:DetachVolume",
      "ec2:RevokeSecurityGroupIngress",

      # ELB Classic permissions
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:AttachLoadBalancerToSubnets",
      "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateLoadBalancerPolicy",
      "elasticloadbalancing:CreateLoadBalancerListeners",
      "elasticloadbalancing:ConfigureHealthCheck",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancerListeners",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeLoadBalancerPolicies",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DetachLoadBalancerFromSubnets",
      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
      "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
      "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",

      # ELB v2 (ALB/NLB) permissions
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeListenerAttributes",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:SetWebAcl",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:SetIpAddressType",

      # IAM permissions
      "iam:CreateServiceLinkedRole",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
      "iam:PassRole",

      # ACM permissions
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "acm:GetCertificate",

      # WAF permissions
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "waf-regional:GetWebACL",
      "waf-regional:GetWebACLForResource",
      "waf-regional:AssociateWebACL",
      "waf-regional:DisassociateWebACL",

      # Shield permissions
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DescribeSubscription",

      # KMS permissions
      "kms:DescribeKey"
    ]
  }
}

data "aws_iam_policy_document" "aws_autoscaler" {
  count = var.enable_autoscaler ? 1 : 0

  statement {
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions"
    ]
    effect    = "Allow"
    resources = ["*"]
  }

  statement {
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeImages",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup"
    ]
    effect    = "Allow"
    resources = ["*"]
  }
}

# Need to add getter/setter for statestore if provided with role
data "aws_iam_role" "provided" {
  count = var.iam_instance_profile == "" ? 0 : 1

  name = var.iam_instance_profile
}
