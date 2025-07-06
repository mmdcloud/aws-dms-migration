# Registering vault provider
data "vault_generic_secret" "rds" {
  path = "secret/rds"
}

# Registering vault provider
data "vault_generic_secret" "cloudsql" {
  path = "secret/sql"
}

# ------------------------ GCP Configuration ------------------------

# VPC Creation
module "source_vpc" {
  source                  = "./modules/gcp/network/vpc"
  auto_create_subnetworks = false
  vpc_name                = "source-vpc"
  routing_mode            = "REGIONAL"
}

# Subnets Creation
module "source_vpc_public_subnets" {
  source                   = "./modules/gcp/network/subnet"
  name                     = "source-public-subnet"
  subnets                  = var.source_public_subnets
  vpc_id                   = module.source_vpc.vpc_id
  private_ip_google_access = false
  location                 = var.source_location
}

module "source_vpc_private_subnets" {
  source                   = "./modules/gcp/network/subnet"
  name                     = "source-private-subnet"
  subnets                  = var.source_private_subnets
  vpc_id                   = module.source_vpc.vpc_id
  private_ip_google_access = true
  location                 = var.source_location
}

# Secret Manager
module "source_cloudsql_password_secret" {
  source      = "./modules/gcp/secret-manager"
  secret_data = tostring(data.vault_generic_secret.cloudsql.data["password"])
  secret_id   = "source_db_password_secret"
}

# Cloud SQL
module "source_db" {
  source                      = "./modules/gcp/cloud-sql"
  name                        = "source-db"
  db_name                     = "source-db"
  db_user                     = "mohit"
  db_version                  = "MYSQL_8_0"
  location                    = var.source_location
  tier                        = "db-f1-micro"
  ipv4_enabled                = true
  availability_type           = "ZONAL"
  disk_size                   = 10
  deletion_protection_enabled = false
  backup_configuration        = []
  vpc_self_link               = module.source_vpc.self_link
  vpc_id                      = module.source_vpc.vpc_id
  password                    = module.source_cloudsql_password_secret.secret_data
  depends_on                  = [module.source_cloudsql_password_secret]
  database_flags              = []
}

# ------------------------ AWS Configuration ------------------------

# VPC Configuration
module "destination_vpc" {
  source                = "./modules/aws/vpc/vpc"
  vpc_name              = "destination-vpc"
  vpc_cidr_block        = "10.0.0.0/16"
  enable_dns_hostnames  = true
  enable_dns_support    = true
  internet_gateway_name = "destination_vpc_igw"
}

# RDS Security Group
module "destination_rds_sg" {
  source = "./modules/aws/vpc/security_groups"
  vpc_id = module.destination_vpc.vpc_id
  name   = "destination_rds_sg"
  ingress = [
    {
      from_port       = 3306
      to_port         = 3306
      protocol        = "tcp"
      self            = "false"
      cidr_blocks     = ["0.0.0.0/0"]
      security_groups = []
      description     = "any"
    }
  ]
  egress = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

# Public Subnets
module "destination_public_subnets" {
  source = "./modules/aws/vpc/subnets"
  name   = "destination public subnet"
  subnets = [
    {
      subnet = "10.0.1.0/24"
      az     = "us-east-1a"
    },
    {
      subnet = "10.0.2.0/24"
      az     = "us-east-1b"
    },
    {
      subnet = "10.0.3.0/24"
      az     = "us-east-1c"
    }
  ]
  vpc_id                  = module.destination_vpc.vpc_id
  map_public_ip_on_launch = true
}

# Private Subnets
module "destination_private_subnets" {
  source = "./modules/aws/vpc/subnets"
  name   = "destination private subnet"
  subnets = [
    {
      subnet = "10.0.6.0/24"
      az     = "us-east-1d"
    },
    {
      subnet = "10.0.5.0/24"
      az     = "us-east-1e"
    },
    {
      subnet = "10.0.4.0/24"
      az     = "us-east-1f"
    }
  ]
  vpc_id                  = module.destination_vpc.vpc_id
  map_public_ip_on_launch = false
}

# Destination Public Route Table
module "destination_public_rt" {
  source  = "./modules/aws/vpc/route_tables"
  name    = "destination public route table"
  subnets = module.destination_public_subnets.subnets[*]
  routes = [
    {
      cidr_block     = "0.0.0.0/0"
      gateway_id     = module.destination_vpc.igw_id
      nat_gateway_id = ""
    }
  ]
  vpc_id = module.destination_vpc.vpc_id
}

# Destination Private Route Table
module "destination_private_rt" {
  source  = "./modules/aws/vpc/route_tables"
  name    = "destination public route table"
  subnets = module.destination_private_subnets.subnets[*]
  routes  = []
  vpc_id  = module.destination_vpc.vpc_id
}

# Secrets Manager
module "destination_db_credentials" {
  source                  = "./modules/aws/secrets-manager"
  name                    = "destination_rds_secrets"
  description             = "destination_rds_secrets"
  recovery_window_in_days = 0
  secret_string = jsonencode({
    username = tostring(data.vault_generic_secret.rds.data["username"])
    password = tostring(data.vault_generic_secret.rds.data["password"])
  })
}

# RDS Instance
module "destination_db" {
  source                  = "./modules/aws/rds"
  db_name                 = "destinationdb"
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  multi_az                = true
  parameter_group_name    = "default.mysql8.0"
  username                = tostring(data.vault_generic_secret.rds.data["username"])
  password                = tostring(data.vault_generic_secret.rds.data["password"])
  subnet_group_name       = "destination_rds_subnet_group"
  backup_retention_period = 7
  backup_window           = "03:00-05:00"
  subnet_group_ids = [
    module.destination_public_subnets.subnets[0].id,
    module.destination_public_subnets.subnets[1].id
  ]
  vpc_security_group_ids = [module.destination_rds_sg.id]
  publicly_accessible    = true
  skip_final_snapshot    = true
}

# --------------------------- DMS Configuration ---------------------------

# 1. Create DMS VPC Role
resource "aws_iam_role" "dms_vpc_role" {
  name               = "dms-vpc-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
}

data "aws_iam_policy_document" "dms_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["dms.amazonaws.com"]
      type        = "Service"
    }
  }
}

# 2. Attach the required AWS managed policy
resource "aws_iam_role_policy_attachment" "dms_vpc_role_attachment" {
  role       = aws_iam_role.dms_vpc_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

# 3. Create DMS CloudWatch Logs Role (if needed)
resource "aws_iam_role" "dms_cloudwatch_logs_role" {
  name               = "dms-cloudwatch-logs-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
}

resource "aws_iam_role_policy_attachment" "dms_cloudwatch_logs_role_attachment" {
  role       = aws_iam_role.dms_cloudwatch_logs_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
}

resource "aws_security_group" "dms_sg" {
  name        = "dms-security-group"
  description = "Allow DMS traffic"
  vpc_id      = module.destination_vpc.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"] # Adjust to your VPC CIDR
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# DMS Replication Instance
module "dms_replication_instance" {
  source                     = "./modules/aws/dms"
  allocated_storage          = 20
  apply_immediately          = false
  publicly_accessible        = true
  replication_instance_class = "dms.t3.micro"
  engine_version             = "3.6.1"
  replication_instance_id    = "dms-instance"
  vpc_security_group_ids     = [aws_security_group.dms_sg.id]

  replication_subnet_group_id          = "dms-subnet-group"
  replication_subnet_group_description = "Subnet group for DMS"
  subnet_group_ids = [
    module.destination_public_subnets.subnets[0].id,
    module.destination_public_subnets.subnets[1].id
  ]

  source_endpoint_id   = "cloudsql-source"
  source_endpoint_type = "source"
  source_engine_name   = "mysql"
  source_username      = tostring(data.vault_generic_secret.cloudsql.data["username"])
  source_password      = tostring(data.vault_generic_secret.cloudsql.data["password"])
  source_server_name   = module.source_db.public_ip_address
  source_port          = 3306
  source_ssl_mode      = "none"

  destination_endpoint_id   = "rds"
  destination_endpoint_type = "target"
  destination_engine_name   = "mysql"
  destination_username      = tostring(data.vault_generic_secret.rds.data["username"])
  destination_password      = tostring(data.vault_generic_secret.rds.data["password"])
  destination_server_name   = module.destination_db.endpoint
  destination_port          = 3306
  destination_ssl_mode      = "none"

  tasks = [
    {
      migration_type      = "full-load"
      replication_task_id = "cloudsql-to-rds-task"
      table_mappings = jsonencode(
        {
          "rules" : [
            {
              "rule-type" : "selection",
              "rule-id" : "1",
              "rule-name" : "1",
              "object-locator" : {
                "schema-name" : "%",
                "table-name" : "%"
              },
              "rule-action" : "include"
            },
            {
              "rule-type" : "transformation",
              "rule-id" : "2",
              "rule-name" : "2",
              "object-locator" : {
                "schema-name" : "%",
                "table-name" : "%"
              },
              "rule-action" : "convert-lowercase",
              "rule-target" : "schema"
            }
          ]
        }
      )
    }
  ]
  depends_on = [
    aws_iam_role_policy_attachment.dms_vpc_role_attachment,
    aws_iam_role_policy_attachment.dms_cloudwatch_logs_role_attachment,
    module.source_db,
    module.destination_db
  ]
}