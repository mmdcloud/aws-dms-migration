# Secret Manager resource for storing RDS credentials
resource "aws_secretsmanager_secret" "rds_creds" {
  name                    = var.name
  recovery_window_in_days = var.recovery_window_in_days
  description             = var.description
  tags = {
    Name = var.name
  }
}

resource "aws_secretsmanager_secret_version" "rds_creds_version" {
  secret_id     = aws_secretsmanager_secret.rds_creds.id
  secret_string = var.secret_string
}
