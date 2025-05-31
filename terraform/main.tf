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
  subnets                  = var.public_subnets
  vpc_id                   = module.source_vpc.vpc_id
  private_ip_google_access = false
  location                 = var.location
}

module "source_vpc_private_subnets" {
  source                   = "./modules/gcp/network/subnet"
  name                     = "source-private-subnet"
  subnets                  = var.private_subnets
  vpc_id                   = module.source_vpc.vpc_id
  private_ip_google_access = true
  location                 = var.location
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
  location                    = var.location
  tier                        = "db-f1-micro"
  ipv4_enabled                = false
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
  db_name                 = "destination-db"
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
  publicly_accessible    = false
  skip_final_snapshot    = true
}
