# Terraform Configuration for AWS DevOps Demo
# Defines the provider, backend, and resource dependencies for a production-ready ECS deployment
terraform {
  # Configure required providers with version constraints
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use latest 5.x series for stability and features
    }
  }
  # Specify compatible Terraform version
  required_version = "~> 1.5.7"

  # S3 backend for remote state management
  backend "s3" {
    bucket  = "aws-devops-demo-terraform-state"
    key     = "aws-devops-demo/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

# AWS Provider Configuration
# Sets the default region for all AWS resources
provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------
# Networking Resources
# Defines the VPC, subnets, and routing for the application

# VPC for the DevOps Demo
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "devops-demo-vpc"
    Environment = var.environment
  }
}

# Public Subnets for Load Balancer and ECS
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone       = element(["us-east-1a", "us-east-1b"], count.index)
  tags = {
    Name        = "devops-demo-subnet-public-${count.index}"
    Environment = var.environment
  }
}

# Internet Gateway for Public Access
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "devops-demo-igw"
    Environment = var.environment
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name        = "devops-demo-public-rt"
    Environment = var.environment
  }
}

# Associate Route Table with Public Subnets
resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public[*].id)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# ---------------------------------------------
# Storage Resources
# Manages ECR and DynamoDB for the application

# ECR Repository for Docker Images
resource "aws_ecr_repository" "devops_demo_repo" {
  name                 = "aws-devops-demo"
  image_tag_mutability = "MUTABLE"
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = {
    Name        = "devops-demo-ecr"
    Environment = var.environment
  }
}

# DynamoDB Table for Hit Counter
resource "aws_dynamodb_table" "demo_hits" {
  name         = "DemoHits"
  billing_mode = "PAY_PER_REQUEST" # Cost-effective for demo
  hash_key     = "id"
  attribute {
    name = "id"
    type = "S"
  }
  tags = {
    Name        = "devops-demo-hits"
    Environment = var.environment
  }
}

# ---------------------------------------------
# Security Resources
# Defines security groups and IAM roles for access control

# Security Group for Application Load Balancer
resource "aws_security_group" "alb_sg" {
  name_prefix = "alb-sg-"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow public HTTP access
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "devops-demo-alb-sg"
    Environment = var.environment
  }
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_sg" {
  name_prefix = "ecs-sg-"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port       = 5001
    to_port         = 5001
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # Restrict to ALB traffic
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "devops-demo-ecs-sg"
    Environment = var.environment
  }
}

# IAM OpenID Connect Provider for GitHub Actions
data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions_role" {
  name = "GitHubActionsECRRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:paulcyi/aws-devops-demo:*"
        }
      }
    }]
  })
  tags = {
    Name        = "github-actions-ecr-role"
    Environment = var.environment
  }
}

# IAM Policy for ECR Push
resource "aws_iam_policy" "ecr_push_policy" {
  name        = "GitHubActionsECRPush"
  description = "Allows GitHub Actions to push images to ECR"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ecr:GetAuthorizationToken"]
      Resource = "*"
      }, {
      Effect = "Allow"
      Action = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories"
      ]
      Resource = aws_ecr_repository.devops_demo_repo.arn
    }]
  })
}

# IAM Policy for Terraform Management
resource "aws_iam_policy" "github_terraform_policy" {
  name = "GitHubActionsTerraform"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecs:UpdateService",
        "ecs:DescribeServices",
        "ecs:DescribeClusters"
      ]
      Resource = [
        aws_ecs_cluster.devops_demo_cluster.arn,
        aws_ecs_service.devops_demo_service.id,
        aws_ecs_task_definition.devops_demo_task.arn
      ]
      }, {
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "arn:aws:s3:::aws-devops-demo-terraform-state/*"
      }, {
      Effect = "Allow"
      Action = [
        "ec2:Describe*",
        "elasticloadbalancing:Describe*",
        "ecr:ListTagsForResource",
        "iam:GetOpenIDConnectProvider",
        "iam:GetRole",
        "iam:ListRolePolicies",
        "iam:GetPolicy",
        "iam:ListAttachedRolePolicies",
        "iam:GetPolicyVersion",
        "iam:ListEntitiesForPolicy",
        "iam:ListPolicyVersions",
        "iam:DeletePolicyVersion",
        "iam:CreatePolicyVersion",
        "logs:DescribeLogGroups",
        "logs:ListTagsLogGroup",
        "logs:ListTagsForResource",
        "ecs:DescribeTaskDefinition",
        "ecs:DeregisterTaskDefinition",
        "ecs:RegisterTaskDefinition",
        "ecs:TagResource",
        "iam:PassRole",
        "dynamodb:DescribeTable",
        "dynamodb:DescribeContinuousBackups",
        "dynamodb:DescribeTimeToLive",
        "dynamodb:ListTagsOfResource",
        "iam:GetRolePolicy"
      ]
      Resource = "*"
    }]
  })
}

# Attach Policies to GitHub Actions Role
resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.ecr_push_policy.arn
}

resource "aws_iam_role_policy_attachment" "github_actions_tf" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.github_terraform_policy.arn
}

# ---------------------------------------------
# Compute Resources
# Manages ECS cluster, tasks, and services

# ECS Cluster
resource "aws_ecs_cluster" "devops_demo_cluster" {
  name = "devops-demo-cluster"
  tags = {
    Name        = "devops-demo-cluster"
    Environment = var.environment
  }
}

# ECS Task Role
resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-devops-demo-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
  tags = {
    Name        = "devops-demo-task-role"
    Environment = var.environment
  }
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
  tags = {
    Name        = "devops-demo-execution-role"
    Environment = var.environment
  }
}

# IAM Policy for DynamoDB Access
resource "aws_iam_policy" "ecs_dynamodb_access" {
  name = "ECSDynamoDBAccess"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:UpdateItem",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DescribeTable",
        "dynamodb:ListTables"
      ]
      Resource = aws_dynamodb_table.demo_hits.arn
    }]
  })
}

# Attach ECS Execution Role Policy
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Attach DynamoDB Access Policy to Task Role
resource "aws_iam_role_policy_attachment" "task_role_dynamodb_access" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_dynamodb_access.arn
}

# ECS Task Definition
resource "aws_ecs_task_definition" "devops_demo_task" {
  family                   = var.ecs_task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.instance_cpu
  memory                   = var.instance_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([
    {
      name         = "devops-demo-container"
      image        = "724772086697.dkr.ecr.us-east-1.amazonaws.com/aws-devops-demo:${var.image_tag}"
      cpu          = var.instance_cpu
      memory       = var.instance_memory
      essential    = true
      portMappings = [{ containerPort = 5001 }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_log_group.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
      environment = [
        { name = "AWS_REGION", value = var.aws_region },
        { name = "BUILD_TRIGGER", value = var.image_tag }
      ]
    }
  ])
  tags = {
    Name        = "devops-demo-task"
    Environment = var.environment
  }
}

# ECS Service
resource "aws_ecs_service" "devops_demo_service" {
  name                 = "devops-demo-service"
  cluster              = aws_ecs_cluster.devops_demo_cluster.id
  task_definition      = aws_ecs_task_definition.devops_demo_task.arn
  launch_type          = "FARGATE"
  desired_count        = 1
  force_new_deployment = true
  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_target_group.arn
    container_name   = "devops-demo-container"
    container_port   = 5001
  }
  depends_on = [aws_lb_listener.http]
  tags = {
    Name        = "devops-demo-service"
    Environment = var.environment
  }
}

# ---------------------------------------------
# Load Balancing Resources
# Configures the ALB to route traffic to ECS

# Application Load Balancer
resource "aws_lb" "ecs_alb" {
  name               = "devops-demo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
  tags = {
    Name        = "devops-demo-alb"
    Environment = var.environment
  }
}

# Target Group for ECS
resource "aws_lb_target_group" "ecs_target_group" {
  name        = "devops-demo-tg"
  port        = 5001
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  tags = {
    Name        = "devops-demo-tg"
    Environment = var.environment
  }
}

# HTTP Listener for ALB
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_target_group.arn
  }
}

# ---------------------------------------------
# Monitoring and Scaling Resources
# Configures logging, alerts, and auto scaling for the application

# CloudWatch Log Group for ECS Logs
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/devops-demo-task"
  retention_in_days = 7
  tags = {
    Name        = "devops-demo-logs"
    Environment = var.environment
  }
}

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = "devops-demo-alerts"
  tags = {
    Name        = "devops-demo-alerts"
    Environment = var.environment
  }
}

# SNS Email Subscription for Alerts
resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "yipaulx@gmail.com"  # Subscriber's email for notifications
}

# CloudWatch Alarm for High Latency
resource "aws_cloudwatch_metric_alarm" "high_latency_alarm" {
  alarm_name          = "high-latency-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "0.5"
  alarm_description   = "This metric monitors ALB latency exceeding 0.5 seconds"
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    LoadBalancer = aws_lb.ecs_alb.arn_suffix
    TargetGroup  = aws_lb_target_group.ecs_target_group.arn_suffix
  }
  tags = {
    Name        = "high-latency-alarm"
    Environment = var.environment
  }
}

# Auto Scaling Target for ECS Service
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 4
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.devops_demo_cluster.name}/${aws_ecs_service.devops_demo_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  tags = {
    Name        = "ecs-scaling-target"
    Environment = var.environment
  }
}

# Auto Scaling Policy for ECS
resource "aws_appautoscaling_policy" "ecs_policy" {
  name               = "ecs-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label        = "${aws_lb.ecs_alb.arn_suffix}/${aws_lb_target_group.ecs_target_group.arn_suffix}"
    }
    target_value = 100.0
  }
}

# ---------------------------------------------
# Networking Endpoint
# Enhances DynamoDB connectivity

# DynamoDB VPC Endpoint
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  route_table_ids   = [aws_route_table.public_rt.id]
  vpc_endpoint_type = "Gateway"
  tags = {
    Name        = "devops-demo-dynamodb-endpoint"
    Environment = var.environment
  }
}
