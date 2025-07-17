output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnets" {
  value = module.vpc.public_subnets
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "rke2_security_group_id" {
  description = "Security group ID for RKE2 server"
  value       = aws_security_group.rke2_server.id
}

