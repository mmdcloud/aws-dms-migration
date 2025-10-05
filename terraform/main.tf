# ------------------------------------------------------------------------
# GCP Configuration
# ------------------------------------------------------------------------

data "vault_generic_secret" "cloudsql" {
  path = "secret/sql"
}

# VPC Creation
module "source_vpc" {
  source                          = "./modules/gcp/vpc"
  vpc_name                        = "source-vpc"
  delete_default_routes_on_create = false
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  subnets = [
    {
      ip_cidr_range            = "10.1.0.0/16"
      name                     = "source-public-subnet"
      private_ip_google_access = false
      purpose                  = "PRIVATE"
      region                   = var.source_location
      role                     = "ACTIVE"
    }
  ]
  firewall_data = [
    {
      name          = "vpc-firewall-ssh"
      source_ranges = ["0.0.0.0/0"]
      allow_list = [
        {
          protocol = "tcp"
          ports    = ["22"]
        }
      ]
    }
  ]
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
  name                        = var.source_db
  db_name                     = var.source_db
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

# ------------------------------------------------------------------------
# AWS Configuration
# ------------------------------------------------------------------------

data "vault_generic_secret" "rds" {
  path = "secret/rds"
}

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
      cidr_blocks     = ["10.0.0.0/16"]
      security_groups = []
      description     = "MySQL from VPC"
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
      subnet = "10.0.4.0/24"
      az     = "us-east-1a"
    },
    {
      subnet = "10.0.5.0/24"
      az     = "us-east-1b"
    },
    {
      subnet = "10.0.6.0/24"
      az     = "us-east-1c"
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
  name    = "destination private route table"
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
  db_name                 = var.destination_db
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

# SNS Configuration
module "sns" {
  source     = "./modules/sns"
  topic_name = "dms-job-status-change-topic"
  subscriptions = [
    {
      protocol = "email"
      endpoint = "madmaxcloudonline@gmail.com"
    }
  ]
}

# ------------------------------------------------------------------------
# DMS Configuration
# ------------------------------------------------------------------------

# DMS VPC Role
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

resource "aws_iam_role_policy_attachment" "dms_vpc_role_attachment" {
  role       = aws_iam_role.dms_vpc_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

# DMS CloudWatch Logs Role (if needed)
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
    cidr_blocks = ["10.0.0.0/16"]
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
              "rule-name" : "include-source-db",
              "object-locator" : {
                "schema-name" : "${var.source_db}",
                "table-name" : "%"
              },
              "rule-action" : "include"
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

resource "aws_dms_event_subscription" "subscription" {
  enabled          = true
  event_categories = ["creation", "deletion", "failure", "state-change"]
  name             = "dms-event-subscription"
  sns_topic_arn    = module.sns.topic_arn
  source_ids       = [module.dms_replication_instance.replication_instance_id]
  source_type      = "replication-instance"
  depends_on       = [module.dms_replication_instance]
}

# ------------------------------------------------------------------------
# VPN Configuration
# ------------------------------------------------------------------------

# Create a customer gateway representing the GCP side
resource "aws_customer_gateway" "gcp_cgw_1" {
  bgp_asn    = 65534
  ip_address = google_compute_ha_vpn_gateway.gcp_vpn_gateway.vpn_interfaces[0].ip_address
  type       = "ipsec.1"

  tags = {
    Name = "aws-customer-gw-1"
  }

  # This depends on the GCP VPN gateway being created first
  depends_on = [google_compute_ha_vpn_gateway.gcp_vpn_gateway]
}

resource "aws_customer_gateway" "gcp_cgw_2" {
  bgp_asn    = 65534
  ip_address = google_compute_ha_vpn_gateway.gcp_vpn_gateway.vpn_interfaces[1].ip_address
  type       = "ipsec.1"

  tags = {
    Name = "aws-customer-gw-2"
  }

  # This depends on the GCP VPN gateway being created first
  depends_on = [google_compute_ha_vpn_gateway.gcp_vpn_gateway]
}

# Create a VPN gateway in AWS
resource "aws_vpn_gateway" "aws_vpn_gw" {
  vpc_id          = module.destination_vpc.vpc_id
  amazon_side_asn = 65001
  tags = {
    Name = "aws-vpn-gateway"
  }
}

# Create a VPN connection to GCP
resource "aws_vpn_connection" "vpn_connection_1" {
  vpn_gateway_id      = aws_vpn_gateway.aws_vpn_gw.id
  customer_gateway_id = aws_customer_gateway.gcp_cgw_1.id
  type                = "ipsec.1"
  tags = {
    Name = "vpn-connection-1"
  }
}

resource "aws_vpn_connection" "vpn_connection_2" {
  vpn_gateway_id      = aws_vpn_gateway.aws_vpn_gw.id
  customer_gateway_id = aws_customer_gateway.gcp_cgw_2.id
  type                = "ipsec.1"
  tags = {
    Name = "vpn-connection-2"
  }
}

resource "aws_vpn_gateway_attachment" "vpn_attachment" {
  vpn_gateway_id = aws_vpn_gateway.aws_vpn_gw.id
  vpc_id         = module.destination_vpc.vpc_id
}

# Create a HA VPN gateway in GCP
resource "google_compute_ha_vpn_gateway" "gcp_vpn_gateway" {
  name    = "gcp-vpn-gateway"
  network = module.source_vpc.vpc_id
  region  = "us-central1"
}

# Create a cloud router for BGP (optional)
resource "google_compute_router" "gcp_router" {
  name    = "gcp-vpn-router"
  network = module.source_vpc.vpc_id
  region  = "us-central1"
  bgp {
    advertise_mode    = "CUSTOM"
    advertised_groups = ["ALL_SUBNETS"]
    asn               = 65534
  }
}

# Create external VPN gateway representing the AWS side
resource "google_compute_external_vpn_gateway" "aws_vpn_gateway_1" {
  name            = "aws-vpn-gateway-1"
  redundancy_type = "TWO_IPS_REDUNDANCY"
  description     = "AWS VPN Gateway 1"
  interface {
    id         = 0
    ip_address = aws_vpn_connection.vpn_connection_1.tunnel1_address
  }
  interface {
    id         = 1
    ip_address = aws_vpn_connection.vpn_connection_1.tunnel2_address
  }
}

resource "google_compute_external_vpn_gateway" "aws_vpn_gateway_2" {
  name            = "aws-vpn-gateway-2"
  redundancy_type = "TWO_IPS_REDUNDANCY"
  description     = "AWS VPN Gateway 2"
  interface {
    id         = 0
    ip_address = aws_vpn_connection.vpn_connection_2.tunnel1_address
  }
  interface {
    id         = 1
    ip_address = aws_vpn_connection.vpn_connection_2.tunnel2_address
  }
}

# Create VPN tunnels on GCP side
resource "google_compute_vpn_tunnel" "gcp_tunnel1" {
  name                            = "gcp-tunnel1"
  region                          = "us-central1"
  vpn_gateway                     = google_compute_ha_vpn_gateway.gcp_vpn_gateway.id
  peer_external_gateway           = google_compute_external_vpn_gateway.aws_vpn_gateway_1.id
  peer_external_gateway_interface = 0
  ike_version                     = 2
  shared_secret                   = aws_vpn_connection.vpn_connection_1.tunnel1_preshared_key
  router                          = google_compute_router.gcp_router.id
  vpn_gateway_interface           = 0
}

resource "google_compute_vpn_tunnel" "gcp_tunnel2" {
  name                            = "gcp-tunnel2"
  region                          = "us-central1"
  vpn_gateway                     = google_compute_ha_vpn_gateway.gcp_vpn_gateway.id
  peer_external_gateway           = google_compute_external_vpn_gateway.aws_vpn_gateway_1.id
  peer_external_gateway_interface = 1
  ike_version                     = 2
  shared_secret                   = aws_vpn_connection.vpn_connection_1.tunnel2_preshared_key
  router                          = google_compute_router.gcp_router.id
  vpn_gateway_interface           = 0
}

resource "google_compute_vpn_tunnel" "gcp_tunnel3" {
  name                            = "gcp-tunnel3"
  region                          = "us-central1"
  vpn_gateway                     = google_compute_ha_vpn_gateway.gcp_vpn_gateway.id
  peer_external_gateway           = google_compute_external_vpn_gateway.aws_vpn_gateway_2.id
  peer_external_gateway_interface = 0
  ike_version                     = 2
  shared_secret                   = aws_vpn_connection.vpn_connection_2.tunnel1_preshared_key
  router                          = google_compute_router.gcp_router.id
  vpn_gateway_interface           = 1
}

resource "google_compute_vpn_tunnel" "gcp_tunnel4" {
  name                            = "gcp-tunnel4"
  region                          = "us-central1"
  vpn_gateway                     = google_compute_ha_vpn_gateway.gcp_vpn_gateway.id
  peer_external_gateway           = google_compute_external_vpn_gateway.aws_vpn_gateway_2.id
  peer_external_gateway_interface = 1
  ike_version                     = 2
  shared_secret                   = aws_vpn_connection.vpn_connection_2.tunnel2_preshared_key
  router                          = google_compute_router.gcp_router.id
  vpn_gateway_interface           = 1
}

# Create BGP sessions (optional)
resource "google_compute_router_peer" "gcp_bgp_peer1" {
  name                      = "gcp-bgp-peer1"
  router                    = google_compute_router.gcp_router.name
  region                    = "us-central1"
  peer_ip_address           = aws_vpn_connection.vpn_connection_1.tunnel1_vgw_inside_address
  peer_asn                  = 65001
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.gcp_interface1.name
}

resource "google_compute_router_peer" "gcp_bgp_peer2" {
  name                      = "gcp-bgp-peer2"
  router                    = google_compute_router.gcp_router.name
  region                    = "us-central1"
  peer_ip_address           = aws_vpn_connection.vpn_connection_1.tunnel2_vgw_inside_address
  peer_asn                  = 65001
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.gcp_interface2.name
}

resource "google_compute_router_peer" "gcp_bgp_peer3" {
  name                      = "gcp-bgp-peer3"
  router                    = google_compute_router.gcp_router.name
  region                    = "us-central1"
  peer_ip_address           = aws_vpn_connection.vpn_connection_2.tunnel1_vgw_inside_address
  peer_asn                  = 65001
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.gcp_interface3.name
}

resource "google_compute_router_peer" "gcp_bgp_peer4" {
  name                      = "gcp-bgp-peer4"
  router                    = google_compute_router.gcp_router.name
  region                    = "us-central1"
  peer_ip_address           = aws_vpn_connection.vpn_connection_2.tunnel2_vgw_inside_address
  peer_asn                  = 65001
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.gcp_interface4.name
}

resource "google_compute_router_interface" "gcp_interface1" {
  name       = "gcp-interface1"
  router     = google_compute_router.gcp_router.name
  region     = "us-central1"
  ip_range   = "${aws_vpn_connection.vpn_connection_1.tunnel1_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.gcp_tunnel1.name
}

resource "google_compute_router_interface" "gcp_interface2" {
  name       = "gcp-interface2"
  router     = google_compute_router.gcp_router.name
  region     = "us-central1"
  ip_range   = "${aws_vpn_connection.vpn_connection_1.tunnel2_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.gcp_tunnel2.name
}

resource "google_compute_router_interface" "gcp_interface3" {
  name       = "gcp-interface3"
  router     = google_compute_router.gcp_router.name
  region     = "us-central1"
  ip_range   = "${aws_vpn_connection.vpn_connection_2.tunnel1_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.gcp_tunnel3.name
}

resource "google_compute_router_interface" "gcp_interface4" {
  name       = "gcp-interface4"
  router     = google_compute_router.gcp_router.name
  region     = "us-central1"
  ip_range   = "${aws_vpn_connection.vpn_connection_2.tunnel2_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.gcp_tunnel4.name
}