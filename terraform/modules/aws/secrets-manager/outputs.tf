output "name" {
  value = aws_secretsmanager_secret.rds_creds.name
}

output "arn" {
  value = aws_secretsmanager_secret.rds_creds.arn
}
