

locals {
  # Create a unique cluster name we'll prefix to all resources created and ensure it's lowercase
  uname = var.unique_suffix ? lower("${var.cluster_name}-${random_string.uid.result}") : lower(var.cluster_name)

  default_tags = {
    "ClusterType" = "rke2",
  }

  ccm_tags = {
    "kubernetes.io/cluster/${local.uname}" = "owned"
  }

  cluster_data = {
    name       = local.uname
    server_url = module.cp_lb.dns
    cluster_sg = aws_security_group.cluster.id
    token      = module.statestore.token
  }

  lb_subnets        = module.vpc.private_subnets
  alb_subnets       = module.vpc.public_subnets
  target_group_arns = module.cp_lb.target_group_arns
}

resource "random_string" "uid" {
  # NOTE: Don't get too crazy here, several aws resources have tight limits on lengths (such as load balancers), in practice we are also relying on users to uniquely identify their cluster names
  length  = 3
  special = false
  lower   = true
  upper   = false
  numeric = true
}

#
# Cluster join token
#
resource "random_password" "token" {
  length  = 40
  special = false
}

module "statestore" {
  source     = "./modules/statestore"
  name       = local.uname
  create_acl = var.create_acl
  token      = random_password.token.result
  tags       = merge(local.default_tags, var.tags)

  attach_deny_insecure_transport_policy = var.statestore_attach_deny_insecure_transport_policy
}

#
# Controlplane Load Balancer
#
module "cp_lb" {
  source  = "./modules/nlb"
  name    = local.uname
  vpc_id  = module.vpc.vpc_id
  subnets = local.lb_subnets

  enable_cross_zone_load_balancing = var.controlplane_enable_cross_zone_load_balancing
  internal                         = var.controlplane_internal
  access_logs_bucket               = var.controlplane_access_logs_bucket

  cp_ingress_cidr_blocks            = var.controlplane_allowed_cidrs
  cp_supervisor_ingress_cidr_blocks = var.controlplane_allowed_cidrs

  tags = merge({}, local.default_tags, local.default_tags, var.tags)
}

#
# Security Groups
#

# Allow ALB to reach nginx on port 80 (if using IP target type)
resource "aws_security_group_rule" "alb_to_cluster_http" {

  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = module.nginx_alb.security_group_id
  description              = "Allow ALB to reach pods on port 80"
}

# Allow ALB to reach full NodePort range (for flexibility)
resource "aws_security_group_rule" "alb_to_cluster_nodeport_range" {

  type                     = "ingress"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = module.nginx_alb.security_group_id
  description              = "Allow ALB to reach NodePort services (30000-32767)"
}

# Allow ALB to reach specific nginx NodePort (more restrictive)
resource "aws_security_group_rule" "alb_to_nginx_nodeport" {

  type                     = "ingress"
  from_port                = var.nginx_nodeport
  to_port                  = var.nginx_nodeport
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = module.nginx_alb.security_group_id
  description              = "Allow ALB to reach nginx NodePort ${var.nginx_nodeport}"
}

# Shared Cluster Security Group
resource "aws_security_group" "cluster" {
  name        = "${local.uname}-rke2-cluster"
  description = "Shared ${local.uname} cluster security group"
  vpc_id      = module.vpc.vpc_id

  tags = merge({
    "shared" = "true",
  }, local.default_tags, var.tags)
}

resource "aws_security_group_rule" "cluster_shared" {
  description       = "Allow all inbound traffic between ${local.uname} cluster nodes"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.cluster.id
  type              = "ingress"

  self = true
}

resource "aws_security_group_rule" "cluster_egress" {
  description       = "Allow all outbound traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.cluster.id
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Server Security Group
resource "aws_security_group" "server" {
  name        = "${local.uname}-rke2-server"
  vpc_id      = module.vpc.vpc_id
  description = "${local.uname} rke2 server node pool"
  tags        = merge(local.default_tags, var.tags)
}

resource "aws_security_group_rule" "server_cp" {
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.server.id
  type                     = "ingress"
  source_security_group_id = module.cp_lb.security_group
}

resource "aws_security_group_rule" "server_cp_supervisor" {
  from_port                = 9345
  to_port                  = 9345
  protocol                 = "tcp"
  security_group_id        = aws_security_group.server.id
  type                     = "ingress"
  source_security_group_id = module.cp_lb.security_group
}

#
# IAM Role
#
module "iam" {
  count = var.iam_instance_profile == "" ? 1 : 0

  source = "./modules/policies"
  name   = "${local.uname}-rke2-server"

  permissions_boundary = var.iam_permissions_boundary

  tags = merge({}, local.default_tags, var.tags)
}

#
# Policies
#
resource "aws_iam_role_policy" "aws_required" {
  count = var.iam_instance_profile == "" ? 1 : 0

  name   = "${local.uname}-rke2-server-aws-introspect"
  role   = module.iam[count.index].role
  policy = data.aws_iam_policy_document.aws_required[count.index].json
}

resource "aws_iam_role_policy" "ssm_session" {
  count = var.iam_instance_profile == "" ? 1 : 0

  name   = "${local.uname}-rke2-server-ssm-session"
  role   = module.iam[count.index].role
  policy = data.aws_iam_policy_document.ssm_session.json
}


resource "aws_iam_role_policy" "aws_ccm" {
  count = var.iam_instance_profile == "" && var.enable_ccm ? 1 : 0

  name   = "${local.uname}-rke2-server-aws-ccm"
  role   = module.iam[count.index].role
  policy = data.aws_iam_policy_document.aws_ccm[count.index].json
}

resource "aws_iam_role_policy" "aws_autoscaler" {
  count = var.iam_instance_profile == "" && var.enable_autoscaler ? 1 : 0

  name   = "${local.uname}-rke2-server-aws-autoscaler"
  role   = module.iam[count.index].role
  policy = data.aws_iam_policy_document.aws_autoscaler[count.index].json
}

resource "aws_iam_role_policy" "get_token" {
  #count = var.iam_instance_profile == "" ? 1 : 0

  name   = "${local.uname}-rke2-server-get-token"
  role   = var.iam_instance_profile == "" ? module.iam[0].role : data.aws_iam_role.provided[0].name
  policy = module.statestore.token.policy_document
}

resource "aws_iam_role_policy" "put_kubeconfig" {
  #count = var.iam_instance_profile == "" ? 1 : 0

  name   = "${local.uname}-rke2-server-put-kubeconfig"
  role   = var.iam_instance_profile == "" ? module.iam[0].role : data.aws_iam_role.provided[0].name
  policy = module.statestore.kubeconfig_put_policy
}

#
# Server Nodepool
#
module "servers" {
  source = "./modules/nodepool"
  name   = "${local.uname}-server"

  vpc_id                      = module.vpc.vpc_id
  subnets                     = module.vpc.private_subnets
  ami                         = var.ami
  instance_type               = var.instance_type
  block_device_mappings       = var.block_device_mappings
  extra_block_device_mappings = var.extra_block_device_mappings
  vpc_security_group_ids = concat(
    [aws_security_group.cluster.id, aws_security_group.server.id],
  var.extra_security_group_ids)
  spot                        = var.spot
  target_group_arns           = local.target_group_arns
  wait_for_capacity_timeout   = var.wait_for_capacity_timeout
  metadata_options            = var.metadata_options
  associate_public_ip_address = var.associate_public_ip_address

  # Overrideable variables
  userdata             = data.cloudinit_config.this.rendered
  iam_instance_profile = var.iam_instance_profile == "" ? module.iam[0].iam_instance_profile : var.iam_instance_profile

  # Don't allow something not recommended within etcd scaling, set max deliberately and only control desired
  asg = {
    min                  = 1
    max                  = 7
    desired              = var.servers
    suspended_processes  = var.suspended_processes
    termination_policies = var.termination_policies
  }

  # TODO: Ideally set this to `length(var.servers)`, but currently blocked by: https://github.com/rancher/rke2/issues/349
  min_elb_capacity = 1

  tags = merge({
    "Role" = "server",
  }, local.ccm_tags, var.tags)
}

#
# Agent/Worker Nodepool
#
module "agents" {
  depends_on = [module.servers]
  source     = "./modules/agent-nodepool"

  name    = "${local.uname}-agent"
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.private_subnets
  ami     = var.ami

  instance_type = var.instance_type

  spot                        = var.spot
  wait_for_capacity_timeout   = var.wait_for_capacity_timeout
  metadata_options            = var.metadata_options
  associate_public_ip_address = var.associate_public_ip_address

  asg = {
    min                  = 1
    max                  = 7
    desired              = 1
    suspended_processes  = var.suspended_processes
    termination_policies = var.termination_policies
  }

  min_elb_capacity = 1

  enable_autoscaler   = var.enable_autoscaler
  enable_ccm          = var.enable_ccm
  ssh_authorized_keys = var.ssh_authorized_keys
  cluster_data        = local.cluster_data
  rke2_channel        = var.rke2_channel

  tags = merge({
    "Role" = "agent",
  }, local.ccm_tags, var.tags)
}

module "vpc" {
  source   = "./modules/vpc"
  name     = "${local.uname}-rke2-vpc"
  vpc_cidr = var.vpc_cidr

}

module "bastion" {
  depends_on = [module.servers, module.agents]
  source     = "./modules/bastion"

  ami_id              = var.ami
  vpc_id              = module.vpc.vpc_id
  instance_type       = "t3.micro"
  private_subnet_ids  = module.vpc.private_subnets
  kubeconfig_path_arn = "${module.statestore.bucket_arn}/rke2.yaml"
  kubeconfig_path     = "s3://${module.statestore.bucket}/rke2.yaml"
  cluster_name        = local.uname
}

module "nginx_alb" {
  source  = "./modules/alb"
  name    = local.uname
  subnets = local.alb_subnets
  vpc_id  = module.vpc.vpc_id

  enable_cross_zone_load_balancing = var.alb_enable_cross_zone_load_balancing
  internal                         = var.alb_internal
  access_logs_bucket               = var.alb_access_logs_bucket
  alb_ingress_cidr_blocks          = var.alb_allowed_cidrs

  tags = merge({}, local.default_tags, var.tags)
}

