# Output the ALB details
output "nginx_alb_dns" {
  description = "DNS name of the nginx ALB"
  value       = aws_lb.nginx_alb.dns_name
}

output "nginx_alb_arn" {
  description = "ARN of the nginx ALB"
  value       = aws_lb.nginx_alb.arn
}

output "nginx_alb_zone_id" {
  description = "Zone ID of the nginx ALB"
  value       = aws_lb.nginx_alb.zone_id
}


output "security_group_id" {
  description = "Name of the nginx ALB"
  value       = aws_security_group.nginx_alb.id
  
}