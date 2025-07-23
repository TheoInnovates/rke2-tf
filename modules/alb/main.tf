locals {
  # Handle case where target group/load balancer name exceeds 32 character limit without creating illegal names
  alb_name = "${substr(var.name, 0, 18)}-rke2-alb"

}

# Security group for the ALB
resource "aws_security_group" "nginx_alb" {
  name        = "${local.alb_name}-nginx-alb"
  description = "Security group for nginx ALB"
  vpc_id      = var.vpc_id
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({
    Name = "${local.alb_name}-nginx-alb"
  }, var.tags)
}

# Create the ALB
resource "aws_lb" "nginx_alb" {
  name                             = local.alb_name
  internal                         = var.internal
  load_balancer_type               = "application"
  security_groups                  = [aws_security_group.nginx_alb.id]
  subnets                          = var.subnets
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  enable_deletion_protection = false

  access_logs {
    # the bucket name isn't allowed to be empty in this block, so use its default value as the flag
    bucket  = var.access_logs_bucket
    enabled = var.access_logs_bucket != "disabled"
  }

  # These tags are CRITICAL - the load balancer controller uses them
  tags = merge({
    "elbv2.k8s.aws/cluster"    = var.name
    "ingress.k8s.aws/resource" = "LoadBalancer"
    "ingress.k8s.aws/stack"    = "nginx"
  }, var.tags)
}

# Add rule to allow ALB to communicate with cluster nodes
/* resource "aws_security_group_rule" "alb_to_cluster" {
type                     = "ingress"
from_port                = 0
to_port                  = 65535
protocol                 = "tcp"
security_group_id        = aws_security_group.cluster.id
source_security_group_id = aws_security_group.nginx_alb.id
} */

