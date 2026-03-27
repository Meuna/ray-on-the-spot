output "prefect_api_url" {
  description = "Prefect API url"
  value       = "http://${aws_instance.prefect_server.public_ip}:${var.prefect_port}/api"
}

output "prefect_dashboard_url" {
  description = "Prefect dashboard url"
  value       = "http://${aws_instance.prefect_server.public_ip}:${var.prefect_port}"
}
