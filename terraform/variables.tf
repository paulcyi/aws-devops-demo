variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "ecs_task_family" {
  type    = string
  default = "devops-demo-task"
}

variable "image_tag" {
  type    = string
  default = "latest"
}
