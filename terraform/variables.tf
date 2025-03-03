# Variables Configuration for AWS DevOps Demo
# Defines input parameters for Terraform deployment with defaults and validation
# Ensures modularity, documentation, and best practices for production use

variable "aws_region" {
  description = "The AWS region where all resources will be deployed (e.g., us-east-1)"
  type        = string
  default     = "us-east-1"
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "The aws_region value must be a valid AWS region (e.g., us-east-1)."
  }
}

variable "ecs_task_family" {
  description = "The family name for the ECS task definition (e.g., devops-demo-task)"
  type        = string
  default     = "devops-demo-task"
  validation {
    condition     = length(var.ecs_task_family) > 0 && length(var.ecs_task_family) <= 255 && can(regex("^[a-zA-Z0-9-]*$", var.ecs_task_family))
    error_message = "The ecs_task_family must be a non-empty string up to 255 characters, using only alphanumeric and hyphen characters."
  }
}

variable "image_tag" {
  description = "The tag for the Docker image in ECR (e.g., latest or a Git SHA)"
  type        = string
  default     = "v1.0"
  validation {
    condition     = length(var.image_tag) > 0 && length(var.image_tag) <= 128
    error_message = "The image_tag must be a non-empty string up to 128 characters."
  }
}

variable "environment" {
  description = "The deployment environment (e.g., production, staging)"
  type        = string
  default     = "production"
  validation {
    condition     = contains(["production", "staging", "development"], lower(var.environment))
    error_message = "The environment must be one of: production, staging, development."
  }
}

variable "instance_cpu" {
  description = "CPU units allocated to the ECS task (e.g., 256 for 0.25 vCPU)"
  type        = number
  default     = 256
  validation {
    condition     = var.instance_cpu >= 256 && var.instance_cpu <= 4096
    error_message = "The instance_cpu must be between 256 and 4096 units."
  }
}

variable "instance_memory" {
  description = "Memory (MB) allocated to the ECS task (e.g., 512)"
  type        = number
  default     = 512
  validation {
    condition     = var.instance_memory >= 512 && var.instance_memory <= 8192
    error_message = "The instance_memory must be between 512 and 8192 MB."
  }
}