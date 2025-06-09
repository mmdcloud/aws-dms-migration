# AWS DMS Resources
resource "aws_dms_replication_instance" "dms" {
  allocated_storage            = var.allocated_storage
  apply_immediately            = var.apply_immediately
  engine_version               = var.engine_version
  replication_instance_class   = var.replication_instance_class
  replication_instance_id      = var.replication_instance_id
  vpc_security_group_ids       = var.vpc_security_group_ids
  replication_subnet_group_id = aws_dms_replication_subnet_group.dms.replication_subnet_group_id
}

resource "aws_dms_endpoint" "source" {
  endpoint_id   = var.source_endpoint_id
  endpoint_type = var.source_endpoint_type
  engine_name   = var.source_engine_name
  username      = var.source_username
  password      = var.source_password 
  server_name   = var.source_server_name
  port          = var.source_port
  ssl_mode      = var.source_ssl_mode
}

resource "aws_dms_endpoint" "target" {
  endpoint_id   = var.destination_endpoint_id
  endpoint_type = var.destination_endpoint_type
  engine_name   = var.destination_engine_name
  username      = var.destination_username
  password      = var.destination_password 
  server_name   = var.destination_server_name
  port          = var.destination_port
  ssl_mode      = var.destination_ssl_mode
}

resource "aws_dms_replication_subnet_group" "dms" {
  replication_subnet_group_id          = var.replication_subnet_group_id
  replication_subnet_group_description = var.replication_subnet_group_description
  subnet_ids                          = var.subnet_group_ids
}

resource "aws_dms_replication_task" "task" {
  count = length(var.tasks)
  migration_type           = var.tasks[count.index].migration_type  
  replication_task_id      = var.tasks[count.index].replication_task_id
  replication_instance_arn = aws_dms_replication_instance.dms.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target.endpoint_arn
  table_mappings           = var.tasks[count.index].table_mappings
}