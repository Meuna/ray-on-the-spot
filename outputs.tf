output "ray_api_url" {
  description = "Ray API url"
  value       = "http://${aws_instance.ray_server.public_ip}:${var.ray_port}/api"
}

output "ray_dashboard_url" {
  description = "Ray dashboard url"
  value       = "http://${aws_instance.ray_server.public_ip}:${var.ray_port}"
}
