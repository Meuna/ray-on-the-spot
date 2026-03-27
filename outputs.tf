output "ray_api_url" {
  description = "Ray API url"
  value       = "http://${aws_instance.ray_server.public_ip}:${var.ray_api_port}"
}
