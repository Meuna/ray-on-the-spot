variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prefect-on-the-spot"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "prefect_port" {
  description = "Port for Prefect API"
  type        = number
  default     = 4200
}

variable "server_instance_type" {
  description = "Instance type for the server"
  type        = string
  default     = "t3.medium"
}

variable "worker_fleet_min_cpu" {
  description = "Minimum number of vCPUs for the worker fleet"
  type        = number
  default     = 8
}

variable "spot_price_ratio" {
  description = "Maximum spot price as a percentage of the optimal on-demand price"
  type        = number
  default     = 50
}

variable "allowed_client_cidr" {
  description = "CIDR blocks allowed for client access"
  type        = list(string)
  default     = ["0.0.0.0/0"]   # Change your ip
}

variable "target_capacity" {
  description = "Total number of vCPUs requested"
  type        = number
}
