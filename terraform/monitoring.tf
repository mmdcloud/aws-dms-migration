# -----------------------------------------------------------------------------------------
# CloudWatch Alarms for Monitoring
# -----------------------------------------------------------------------------------------
module "dms_cpu" {
  source              = "./modules/aws/cloudwatch/cloudwatch-alarm"
  alarm_name          = "dms-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "DMS instance CPU utilization is too high"
  ok_actions          = [module.dms_event_notification.topic_arn]
  alarm_actions       = [module.dms_event_notification.topic_arn]

  dimensions = {
    ReplicationInstanceIdentifier = module.dms_replication_instance.replication_instance_id
  }
}

module "dms_freeable_memory" {
  source              = "./modules/aws/cloudwatch/cloudwatch-alarm"
  alarm_name          = "dms-low-memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = "524288000" # 500MB
  alarm_description   = "DMS instance freeable memory is low"
  ok_actions          = [module.dms_event_notification.topic_arn]
  alarm_actions       = [module.dms_event_notification.topic_arn]

  dimensions = {
    ReplicationInstanceIdentifier = module.dms_replication_instance.replication_instance_id
  }
}

module "dms_cdc_lag" {
  source              = "./modules/aws/cloudwatch/cloudwatch-alarm"
  alarm_name          = "dms-cdc-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CDCLatencySource"
  namespace           = "AWS/DMS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "60" # Alert if CDC lag exceeds 60 seconds
  alarm_description   = "DMS CDC source latency is high - replication falling behind"
  ok_actions          = [module.dms_event_notification.topic_arn]
  alarm_actions       = [module.dms_event_notification.topic_arn]
  dimensions = {
    ReplicationInstanceIdentifier = module.dms_replication_instance.replication_instance_id
  }
}

module "dms_cdc_target_lag" {
  source              = "./modules/aws/cloudwatch/cloudwatch-alarm"
  alarm_name          = "dms-cdc-target-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CDCLatencyTarget"
  namespace           = "AWS/DMS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "60"
  alarm_description   = "DMS CDC target latency is high - apply falling behind"
  ok_actions          = [module.dms_event_notification.topic_arn]
  alarm_actions       = [module.dms_event_notification.topic_arn]
  dimensions = {
    ReplicationInstanceIdentifier = module.dms_replication_instance.replication_instance_id
  }
}

# RDS alarms
module "rds_cpu" {
  source              = "./modules/aws/cloudwatch/cloudwatch-alarm"
  alarm_name          = "rds-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "RDS CPU utilization is too high"
  ok_actions          = [module.dms_event_notification.topic_arn]
  alarm_actions       = [module.dms_event_notification.topic_arn]
  dimensions = {
    DBInstanceIdentifier = module.destination_db.id
  }
}

module "rds_free_storage" {
  source              = "./modules/aws/cloudwatch/cloudwatch-alarm"
  alarm_name          = "rds-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "10737418240" # 10GB in bytes
  alarm_description   = "RDS free storage space is critically low"
  ok_actions          = [module.dms_event_notification.topic_arn]
  alarm_actions       = [module.dms_event_notification.topic_arn]
  dimensions = {
    DBInstanceIdentifier = module.destination_db.id
  }
}

module "rds_connections" {
  source              = "./modules/aws/cloudwatch/cloudwatch-alarm"
  alarm_name          = "rds-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "800" # db.r6g.large max_connections ~1000; alert at 80%
  alarm_description   = "RDS connection count is approaching the instance limit"
  ok_actions          = [module.dms_event_notification.topic_arn]
  alarm_actions       = [module.dms_event_notification.topic_arn]
  dimensions = {
    DBInstanceIdentifier = module.destination_db.id
  }
}

# RDS - Freeable memory (low memory causes swap, which kills query performance)
module "rds_freeable_memory" {
  source              = "./modules/aws/cloudwatch/cloudwatch-alarm"
  alarm_name          = "rds-low-memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1073741824" # 1GB - r6g.large has 16GB RAM; alert well before swap kicks in
  alarm_description   = "RDS freeable memory is low - risk of swap usage and degraded performance"
  ok_actions          = [module.dms_event_notification.topic_arn]
  alarm_actions       = [module.dms_event_notification.topic_arn]
  dimensions = {
    DBInstanceIdentifier = module.destination_db.id
  }
}

# RDS - Read latency spike (catches index issues introduced by DMS full-load writes)
module "rds_read_latency" {
  source              = "./modules/aws/cloudwatch/cloudwatch-alarm"
  alarm_name          = "rds-high-read-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "ReadLatency"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "0.02" # 20ms - elevated read latency during migration signals table lock contention
  alarm_description   = "RDS read latency is elevated - possible lock contention during migration"
  ok_actions          = [module.dms_event_notification.topic_arn]
  alarm_actions       = [module.dms_event_notification.topic_arn]
  dimensions = {
    DBInstanceIdentifier = module.destination_db.id
  }
}

# RDS - Write latency spike (DMS apply phase can overwhelm target during burst CDC)
module "rds_write_latency" {
  source              = "./modules/aws/cloudwatch/cloudwatch-alarm"
  alarm_name          = "rds-high-write-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "WriteLatency"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "0.05" # 50ms - DMS batch apply can cause write spikes; catch before it cascades
  alarm_description   = "RDS write latency is elevated - DMS apply may be overwhelming target"
  ok_actions          = [module.dms_event_notification.topic_arn]
  alarm_actions       = [module.dms_event_notification.topic_arn]
  dimensions = {
    DBInstanceIdentifier = module.destination_db.id
  }
}