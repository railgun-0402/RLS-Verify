# 検証用の最小構成: Cognito User Pool + RDS for PostgreSQL
# ・RDS は検証を簡単にするため publicly_accessible=true にし、SG で自分の IP だけ許可する
# ・本番ではプライベートサブネット + ECS/Lambda 等から接続する構成にすること
# ・終わったら terraform destroy（RDS は起動しているだけで課金される）

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "ap-northeast-1"
}

variable "my_ip_cidr" {
  description = "RDS への接続を許可する自分のグローバル IP（例: 203.0.113.10/32）"
  type        = string
}

variable "db_master_password" {
  type      = string
  sensitive = true
}

# ---------- Cognito ----------

resource "aws_cognito_user_pool" "this" {
  name = "rls-verify"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }
}

resource "aws_cognito_user_pool_client" "cli" {
  name         = "rls-verify-cli"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false
  # 検証で CLI からトークンを取るため USER_PASSWORD_AUTH を許可（本番は SRP / Hosted UI 推奨）
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]
}

# ---------- RDS for PostgreSQL ----------

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "db" {
  name   = "rls-verify-db"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "pg" {
  identifier     = "rls-verify"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_encrypted = true

  db_name  = "rlsdemo"
  username = "rls_admin"
  password = var.db_master_password

  publicly_accessible    = true
  vpc_security_group_ids = [aws_security_group.db.id]

  skip_final_snapshot = true
  apply_immediately   = true
}

# ---------- outputs ----------

output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "client_id" {
  value = aws_cognito_user_pool_client.cli.id
}

output "db_host" {
  value = aws_db_instance.pg.address
}
