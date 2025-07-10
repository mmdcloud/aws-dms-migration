output "replication_instance_id" {
  value = aws_dms_replication_instance.dms.id  
}

output "task_ids" {
  value = aws_dms_replication_task.task[*].id
}