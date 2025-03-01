# 🚀 Terraform Configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  required_version = "~> 1.5.7"

  backend "s3" {
    bucket = "aws-devops-demo-terraform-state"
    key    = "aws-devops-demo/terraform.tfstate"
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
  tags = {
    Name = "devops-demo-vpc"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone       = element(["us-east-1a", "us-east-1b"], count.index)
  tags = {
    Name = "devops-demo-subnet-public-${count.index}"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "devops-demo-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "devops-demo-public-rt"
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
  tags = {
    Name = "devops-demo-ecr"
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
  tags = {
    Name = "devops-demo-alb-sg"
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
  tags = {
    Name = "devops-demo-ecs-sg"
  }
}

# ✅ Application Load Balancer: Handles external traffic and routes to ECS
resource "aws_lb" "ecs_alb" {
  name               = "devops-demo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
  tags = {
    Name = "devops-demo-alb"
  }
}

# UPDATED: Modified the health check to use the /health endpoint
resource "aws_lb_target_group" "ecs_target_group" {
  name        = "devops-demo-tg"
  port        = 5001
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  
  health_check {
    path                = "/health"  # Changed from "/" to "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  
  tags = {
    Name = "devops-demo-tg"
  }
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

# ✅ IAM for GitHub Actions (OIDC)
data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_actions_role" {
  name = "GitHubActionsECRRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
      }
    ]
  })
}

resource "aws_iam_policy" "ecr_push_policy" {
  name        = "GitHubActionsECRPush"
  description = "Policy to allow GitHub Actions to push to ECR"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
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
      }
    ]
  })
}

resource "aws_iam_policy" "github_terraform_policy" {
  name = "GitHubActionsTerraform"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::aws-devops-demo-terraform-state/*"
      },
      {
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
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.ecr_push_policy.arn
}

resource "aws_iam_role_policy_attachment" "github_actions_tf" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.github_terraform_policy.arn
}

# ✅ ECS Cluster & Task Definition
resource "aws_ecs_cluster" "devops_demo_cluster" {
  name = "devops-demo-cluster"
  tags = {
    Name = "devops-demo-cluster"
  }
}

# NEW: Create a separate task role for runtime permissions
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
    Name = "devops-demo-task-role"
  }
}

# Task Execution Role (for pulling images and pushing logs)
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
    Name = "devops-demo-execution-role"
  }
}

# UPDATED: Improved policy for DynamoDB access
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

# Standard execution role policy attachment
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "task_role_dynamodb_access" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_dynamodb_access.arn
}

# UPDATED: Task definition now includes task_role_arn
resource "aws_ecs_task_definition" "devops_demo_task" {
  family                   = var.ecs_task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn  # Added task role
  
  container_definitions = jsonencode([
    {
      name      = "devops-demo-container"
      image     = "${aws_ecr_repository.devops_demo_repo.repository_url}:${var.image_tag}"
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
          awslogs-group         = aws_cloudwatch_log_group.ecs_log_group.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
      environment = [  # Added environment variables
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "BUILD_TRIGGER"
          value = "v2"
        }
      ]
    }
  ])
  tags = {
    Name = "devops-demo-task"
  }
}

# ✅ ECS Service
resource "aws_ecs_service" "devops_demo_service" {
  name            = "devops-demo-service"
  cluster         = aws_ecs_cluster.devops_demo_cluster.id
  task_definition = aws_ecs_task_definition.devops_demo_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1
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
    Name = "devops-demo-service"
  }
}

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/devops-demo-task"
  retention_in_days = 7
  tags = {
    Name = "devops-demo-logs"
  }
}

# DynamoDB Table for Hit Counter
resource "aws_dynamodb_table" "demo_hits" {
  name           = "DemoHits"
  billing_mode   = "PAY_PER_REQUEST"  # Cost-effective for demo
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"  # String type for the key
  }

  tags = {
    Name = "devops-demo-hits"
  }
}

# NEW: DynamoDB endpoint for better connectivity from private subnets
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  route_table_ids   = [aws_route_table.public_rt.id]
  vpc_endpoint_type = "Gateway"
  tags = {
    Name = "devops-demo-dynamodb-endpoint"
  }
}
