# Outputs for AWS DevOps Demo
# Exposes key resource details for reference and monitoring

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.ecs_alb.dns_name
}

output "counter_url" {
  description = "The URL to access the live counter"
  value       = "http://${aws_lb.ecs_alb.dns_name}"
}
