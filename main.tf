terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Retrieve caller infos
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Define locals to fix circles dependencies
locals {
  asg_name = "${var.environment}-autoscaling-group"
  lifecycle_hook_name        = "${var.environment}-drain-hook"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.environment}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.environment}-igw"
  }
}

# Subnet
resource "aws_subnet" "pub" {
  count                   = length(data.aws_availability_zones.available.names)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.environment}-pub-subnet-${count.index}"
  }
}

# Route Table
resource "aws_route_table" "pub" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.environment}-pub-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "main" {
  count          = length(aws_subnet.pub)
  subnet_id      = aws_subnet.pub[count.index].id
  route_table_id = aws_route_table.pub.id
}

# Security Group to allow all outbound traffic
resource "aws_security_group" "out_all" {
  name   = "${var.environment}-out-all-sg"
  vpc_id = aws_vpc.main.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-out-all-sg"
  }
}

# Security Group to support Ray clustering
# The documentation refer to random ports, so we set it to 1025-65535
resource "aws_security_group" "ray_cluster" {
  name   = "${var.environment}-ray-cluster-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 1025
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = {
    Name = "${var.environment}-ray-cluster-sg"
  }
}

# Security Group to support Ray API access
#   - ray_api_port (default to 8265): dashboard and API access
#   - ray_client_port (default to 10001): client mode access
resource "aws_security_group" "in_ray" {
  name   = "${var.environment}-in-ray-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = var.ray_api_port
    to_port     = var.ray_api_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_client_cidr
  }

  ingress {
    from_port   = var.ray_client_port
    to_port     = var.ray_client_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_client_cidr
  }

  tags = {
    Name = "${var.environment}-in-ray-sg"
  }
}

# Security Group to allow SSH access
resource "aws_security_group" "in_ssh" {
  name   = "${var.environment}-in-ssh-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_client_cidr
  }

  tags = {
    Name = "${var.environment}-in-ssh-sg"
  }
}

# Key Pair for SSH access
resource "aws_key_pair" "user" {
  key_name   = "${var.environment}-ssh-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# Ray primary interface
resource "aws_network_interface" "ray_server" {
  subnet_id = aws_subnet.pub[0].id
  security_groups = [
    aws_security_group.out_all.id,
    aws_security_group.in_ssh.id,
    aws_security_group.ray_cluster.id,
    aws_security_group.in_ray.id,
  ]
  tags = {
    Name = "${var.environment}-ray-server-eni"
  }
}

# Ray server
resource "aws_instance" "ray_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.server_instance_type

  key_name = aws_key_pair.user.key_name

  primary_network_interface {
    network_interface_id = aws_network_interface.ray_server.id
  }

  user_data_base64 = base64encode(templatefile("${path.module}/user_data_server.sh.tftpl", {
    ray_cluster_port = var.ray_cluster_port
    ray_api_port     = var.ray_api_port
    ray_client_port  = var.ray_client_port
  }))

  tags = {
    Name = "${var.environment}-ray-server"
  }
}

# IAM Role for EC2 instances
resource "aws_iam_role" "ec2_fleet" {
  name = "${var.environment}-ec2-fleet-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for EC2 instances
resource "aws_iam_role_policy" "ec2_fleet" {
  name = "${var.environment}-ec2-fleet-policy"
  role = aws_iam_role.ec2_fleet.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:CompleteLifecycleAction"
        ]
        Resource : provider::aws::arn_build(
          data.aws_partition.current.partition,
          "autoscaling",
          var.aws_region,
          data.aws_caller_identity.current.account_id,
          "autoScalingGroupName/${local.asg_name}"
        )
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "fleet_profile" {
  name = "${var.environment}-fleet-profile"
  role = aws_iam_role.ec2_fleet.name
}

# EC2 Launch Template
resource "aws_launch_template" "ray_worker" {
  name_prefix = "${var.environment}-ray-worker-"
  image_id    = data.aws_ami.ubuntu.id

  key_name = aws_key_pair.user.key_name

  instance_requirements {
    memory_mib { min = 1 }
    vcpu_count { min = var.worker_fleet_min_cpu }
    max_spot_price_as_percentage_of_optimal_on_demand_price = var.spot_price_ratio
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.fleet_profile.name
  }

  network_interfaces {
    security_groups = [
      aws_security_group.out_all.id,
      aws_security_group.in_ssh.id,
      aws_security_group.ray_cluster.id,
    ]
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/user_data_worker.sh.tftpl", {
    ray_api_url         = aws_instance.ray_server.private_ip,
    ray_cluster_port    = var.ray_cluster_port
    ray_api_port        = var.ray_api_port
    asg_name            = local.asg_name
    lifecycle_hook_name = local.lifecycle_hook_name
    aws_region          = var.aws_region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.environment}-ray-worker"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# EC2 Auto Scaling Group
resource "aws_autoscaling_group" "ray_fleet" {
  name                = local.asg_name
  vpc_zone_identifier = aws_subnet.pub[*].id
  health_check_type   = "EC2"

  desired_capacity_type = "vcpu"
  min_size              = 1
  max_size              = var.target_capacity
  desired_capacity      = var.target_capacity

  mixed_instances_policy {
    instances_distribution {
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "lowest-price"
    }
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.ray_worker.id
        version            = "$Latest"
      }
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.environment}-spot-fleet"
    propagate_at_launch = true
  }
}

# Lifecycle hook to drain Ray workers before termination
resource "aws_autoscaling_lifecycle_hook" "ray_drain" {
  name                   = local.lifecycle_hook_name
  autoscaling_group_name = aws_autoscaling_group.ray_fleet.name
  default_result         = "CONTINUE"
  heartbeat_timeout      = 60
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["*ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
