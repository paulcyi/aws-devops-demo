# 🚀 Terraform Configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.0"

  backend "s3" {
    bucket = "aws-devops-demo-terraform-state"
    key = "aws-devops-demo/terraform.tfstate"
    region = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

# ✅ Networking: Creates a VPC and public subnets
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone       = element(["us-east-1a", "us-east-1b"], count.index)
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public[*].id)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# ECR Repository for storing Docker images
resource "aws_ecr_repository" "devops_demo_repo" {
  name                 = "aws-devops-demo"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# ✅ Security: Defines security groups for ALB and ECS
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
}

resource "aws_security_group" "ecs_sg" {
  name_prefix = "ecs-sg-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5001
    to_port         = 5001
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # Only allow traffic from ALB
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ✅ Application Load Balancer: Handles external traffic and routes to ECS
resource "aws_lb" "ecs_alb" {
  name               = "devops-demo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "ecs_target_group" {
  name        = "devops-demo-tg"
  port        = 5001
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_target_group.arn
  }
}

# ✅ IAM Role for GitHub Actions
data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_oidc_deploy" {
  name = "GitHubOIDC-Deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        },
        Action    = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub": "repo:paulcyi/aws-devops-demo:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "github_oidc_deploy_policy" {
  name = "GitHubOIDCDeployPolicy"
  path = "/"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          # ECR Permissions
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:ListTagsForResource",  # ✅ Fix ECR error

          # ECS, Logging, and S3 Permissions
          "ecs:*",
          "logs:*",
          "s3:*", 

          # IAM Permissions for Terraform
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:PassRole",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetRolePolicy",
          "iam:ListEntitiesForPolicy",
          "iam:SetDefaultPolicyVersion",
          "iam:TagPolicy",
          "iam:UntagPolicy",

          # EC2 Permissions (Fix Unauthorized VPC Error)
          "ec2:DescribeVpcs",  
          "ec2:DescribeVpcClassicLink",  

          # IAM Permissions for OIDC Role
          "iam:GetOpenIDConnectProvider",
          "iam:GetRole"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_oidc_deploy_attach" {
  role       = aws_iam_role.github_oidc_deploy.name
  policy_arn = aws_iam_policy.github_oidc_deploy_policy.arn
}

# ✅ ECS Cluster & Task Definition: Defines the containerized app and execution role
resource "aws_ecs_cluster" "devops_demo_cluster" {
  name = "devops-demo-cluster"
}

variable "ecs_task_family" {
  default = "devops-demo-task"
}

resource "aws_ecs_task_definition" "devops_demo_task" {
  family                   = var.ecs_task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([
    {
      name      = "devops-demo-container"
      image     = "${aws_ecr_repository.devops_demo_repo.repository_url}:latest"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 5001
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group = "/ecs/devops-demo-task"
          awslogs-region = "us-east-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

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
}

resource "aws_iam_policy_attachment" "ecs_task_execution_role_attach" {
  name       = "ecs-task-execution-role-attach"
  roles      = [aws_iam_role.ecs_task_execution_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ✅ ECS Service: Deploys the app and registers with the ALB
resource "aws_ecs_service" "devops_demo_service" {
  name            = "devops-demo-service"
  cluster         = aws_ecs_cluster.devops_demo_cluster.id
  task_definition = aws_ecs_task_definition.devops_demo_task.arn
  launch_type     = "FARGATE"

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

  desired_count = 1

  depends_on = [aws_lb_listener.http]
}

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name = "/ecs/devops-demo-task"
  retention_in_days = 7
}
