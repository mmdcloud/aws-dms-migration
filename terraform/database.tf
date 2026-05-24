# ------------------------------------------------------------------------
# GCP Cloud SQL Configuration
# ------------------------------------------------------------------------
module "source_db" {
  source                      = "./modules/gcp/cloud-sql"
  name                        = var.source_db
  db_name                     = var.source_db
  db_user                     = tostring(data.vault_generic_secret.cloudsql.data["username"])
  db_version                  = "MYSQL_8_0"
  location                    = var.source_location
  tier                        = "db-f1-micro" # Use db-n1-standard-2 for production readiness
  ipv4_enabled                = false
  availability_type           = "REGIONAL"
  disk_size                   = 10
  deletion_protection_enabled = false # Make it true in production
  vpc_self_link               = module.source_vpc.self_link
  password                    = module.source_cloudsql_password_secret.secret_data
  backup_configuration = {
    enabled                        = true
    location                       = "us-central1"
    binary_log_enabled             = true
    start_time                     = "03:00"
    point_in_time_recovery_enabled = false
    backup_retention_settings = {
      retained_backups = 7
      retention_unit   = "COUNT"
    }
  }
  database_flags = [
    {
      name  = "binlog_row_image"
      value = "full"
    },
    {
      name  = "max_connections"
      value = "500"
    }
  ]
  depends_on = [
    module.source_cloudsql_password_secret,
    google_service_networking_connection.source_db_private_vpc_connection
  ]
}

# ------------------------------------------------------------------------
# RDS Configuration
# ------------------------------------------------------------------------
module "destination_db" {
  source                  = "./modules/aws/rds"
  db_name                 = var.destination_db
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro" # Use db.r6g.large for production readiness
  multi_az                = true
  parameter_group_name    = "default.mysql8.0"
  username                = tostring(data.vault_generic_secret.rds.data["username"])
  password                = tostring(data.vault_generic_secret.rds.data["password"])
  subnet_group_name       = "destination_rds_subnet_group"
  backup_retention_period = 7
  backup_window           = "03:00-05:00"
  subnet_group_ids = [
    module.destination_vpc.database_subnets[0],
    module.destination_vpc.database_subnets[1],
    module.destination_vpc.database_subnets[2]
  ]
  vpc_security_group_ids = [module.destination_rds_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true # Make it false in production 
}