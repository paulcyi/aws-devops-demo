# AWS DevOps Demo Pipeline

End-to-end DevOps pipeline deploying a dynamic Flask app with DynamoDB on ECS Fargate using Terraform and GitHub Actions.

## What I Did
Built an automated CI/CD pipeline to:
- **Containerize**: Dockerized a Flask app with a DynamoDB hit counter.
- **Deploy**: Runs on AWS ECS Fargate with an Application Load Balancer (ALB).
- **Persist**: Stores page hits in a DynamoDB table.
- **Automate**: GitHub Actions builds, pushes to ECR, and deploys via Terraform on every `main` push.

Live at: [http://devops-demo-alb-426352306.us-east-1.elb.amazonaws.com/](http://devops-demo-alb-426352306.us-east-1.elb.amazonaws.com/)

## What I Learned
- **Terraform**: Mastered Infrastructure as Code—VPC, ECS, ALB, DynamoDB, and IAM perms galore.
- **IAM Debugging**: Conquered a maze of AWS permissions (`PassRole`, `TagResource`, `Describe*`)—patience pays off!
- **CI/CD**: Tuned GitHub Actions for seamless Docker + Terraform workflows.
- **Resilience**: Turned "AccessDenied" errors into wins—each fix made it stronger.

## Tech Stack
![Python](https://img.shields.io/badge/python-3.9-blue)
![Flask](https://img.shields.io/badge/flask-2.1+-green)
![Docker](https://img.shields.io/badge/docker-latest-blue)
![Terraform](https://img.shields.io/badge/terraform-1.5.7-purple)
![AWS](https://img.shields.io/badge/AWS-ECS%20%7C%20DynamoDB%20%7C%20ECR-orange)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-CI/CD-black)
![Workflow Runs](https://img.shields.io/github/workflow/status/paulcyi/aws-devops-demo/CI%20Build,%20Test,%20Push%20to%20ECR,%20and%20Deploy%20Terraform?label=Workflow%20Runs)

## Setup
1. Clone: `git clone https://github.com/paulcyi/aws-devops-demo`
2. Configure AWS creds in GitHub Secrets (`AWS_REGION`).
3. Push to `main`—watch the magic!

## Demo
[Add screenshot or "Coming soon!" once counter’s live]