resource "aws_db_instance" "db" {
  allocated_storage   = var.allocated_storage
  db_name             = var.db_name
  engine              = var.engine
  engine_version      = var.engine_version
  publicly_accessible = var.publicly_accessible
  multi_az            = var.multi_az
  instance_class      = var.instance_class
  username             = var.username
  password             = var.password
  parameter_group_name = var.parameter_group_name
  backup_retention_period = 7
  backup_window        = "03:00-05:00"
  skip_final_snapshot  = var.skip_final_snapshot
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = var.vpc_security_group_ids
  tags = {
    Name = var.db_name
  }
}

# Subnet group for RDS
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = var.subnet_group_name
  subnet_ids = var.subnet_group_ids
  
  tags = {
    Name = var.subnet_group_name
  }
}