# ------------------------------------------------------------------------
# DMS Certificate Configuration
# ------------------------------------------------------------------------
resource "aws_dms_certificate" "source_cloudsql_ca" {
  certificate_id  = "cloudsql-source-ca"
  certificate_pem = file("${path.module}/certs/cloudsql-server-ca.pem")

  tags = local.common_tags
}

resource "aws_dms_certificate" "destination_rds_ca" {
  certificate_id  = "rds-destination-ca"
  certificate_pem = file("${path.module}/certs/rds-ca-bundle.pem")

  tags = local.common_tags
}

# ------------------------------------------------------------------------
# DMS Configuration
# ------------------------------------------------------------------------
module "dms_replication_instance" {
  source                               = "./modules/aws/dms"
  allocated_storage                    = 20
  apply_immediately                    = false
  publicly_accessible                  = false
  replication_instance_class           = "dms.t3.medium" # Use dms.c5.xlarge for production readiness
  engine_version                       = var.dms_engine_version
  replication_instance_id              = "dms-instance"
  vpc_security_group_ids               = [module.dms_sg.id]
  replication_subnet_group_id          = "dms-subnet-group"
  replication_subnet_group_description = "Subnet group for DMS"
  subnet_group_ids = [
    module.destination_vpc.private_subnets[0],
    module.destination_vpc.private_subnets[1],
    module.destination_vpc.private_subnets[2]
  ]

  source_endpoint_id     = "cloudsql-source"
  source_endpoint_type   = "source"
  source_engine_name     = "mysql"
  source_username        = tostring(data.vault_generic_secret.cloudsql.data["username"])
  source_password        = tostring(data.vault_generic_secret.cloudsql.data["password"])
  source_server_name     = module.source_db.private_ip_address
  source_port            = 3306
  source_ssl_mode        = "verify-ca"
  source_certificate_arn = aws_dms_certificate.source_cloudsql_ca.certificate_arn

  destination_endpoint_id     = "rds"
  destination_endpoint_type   = "target"
  destination_engine_name     = "mysql"
  destination_username        = tostring(data.vault_generic_secret.rds.data["username"])
  destination_password        = tostring(data.vault_generic_secret.rds.data["password"])
  destination_server_name     = split(":", module.destination_db.endpoint)[0]
  destination_port            = 3306
  destination_ssl_mode        = "verify-full"
  destination_certificate_arn = aws_dms_certificate.destination_rds_ca.certificate_arn

  tasks = [
    {
      migration_type      = "full-load-and-cdc"
      replication_task_id = "cloudsql-to-rds-task"
      replication_task_settings = jsonencode({
        TargetMetadata = {
          TargetSchema           = ""
          SupportLobs            = true
          FullLobMode            = false
          LobChunkSize           = 64
          LimitedSizeLobMode     = true
          LobMaxSize             = 32
          FailOnNoTablesCaptured = false
        }
        FullLoadSettings = {
          TargetTablePrepMode = "DO_NOTHING"
          MaxFullLoadSubTasks = 8
        }
        Logging = {
          EnableLogging = true
          LogComponents = [
            {
              Id       = "SOURCE_UNLOAD"
              Severity = "LOGGER_SEVERITY_DEFAULT"
            },
            {
              Id       = "TARGET_LOAD"
              Severity = "LOGGER_SEVERITY_DEFAULT"
            },
            {
              Id       = "SOURCE_CAPTURE"
              Severity = "LOGGER_SEVERITY_DEFAULT"
            },
            {
              Id       = "TARGET_APPLY"
              Severity = "LOGGER_SEVERITY_DEFAULT"
            }
          ]
        }
      })
      table_mappings = jsonencode({
        "rules" : [
          {
            "rule-type" : "selection",
            "rule-id" : "1",
            "rule-name" : "include-all-tables",
            "object-locator" : {
              "schema-name" : var.source_db,
              "table-name" : "%"
            },
            "rule-action" : "include"
          },
          {
            "rule-type" : "transformation",
            "rule-id" : "2",
            "rule-name" : "add-prefix-to-tables",
            "rule-target" : "table",
            "object-locator" : {
              "schema-name" : "madmax",
              "table-name" : "%"
            },
            "rule-action" : "add-prefix",
            "value" : "madmax_"
          }
        ]
      })
    }
  ]

  depends_on = [
    aws_iam_role_policy_attachment.dms_vpc_role_attachment,
    aws_iam_role_policy_attachment.dms_cloudwatch_logs_role_attachment,
    aws_dms_certificate.source_cloudsql_ca,
    aws_dms_certificate.destination_rds_ca,
    module.source_db,
    module.destination_db,
    null_resource.wait_for_vpn_bgp
  ]
}

# ------------------------------------------------------------------------
# SNS Configuration
# ------------------------------------------------------------------------
module "dms_event_notification" {
  source     = "./modules/aws/sns"
  topic_name = "dms-job-status-change-topic"
  subscriptions = [
    {
      protocol = "email"
      endpoint = "${var.notification_email}"
    }
  ]
}

resource "aws_dms_event_subscription" "subscription" {
  enabled          = true
  event_categories = ["creation", "deletion", "failure", "configuration change"]
  name             = "dms-event-subscription"
  sns_topic_arn    = module.dms_event_notification.topic_arn
  source_ids       = [module.dms_replication_instance.replication_instance_id]
  source_type      = "replication-instance"
  depends_on       = [module.dms_replication_instance]
}