# ------------------------------------------------------------------------
# GCP Secret(Vault) Configuration
# ------------------------------------------------------------------------
data "vault_generic_secret" "cloudsql" {
  path = "secret/sql"
}

# ------------------------------------------------------------------------
# GCP VPC Configuration
# ------------------------------------------------------------------------
module "source_vpc" {
  source                          = "./modules/gcp/vpc"
  vpc_name                        = "source-vpc"
  delete_default_routes_on_create = false
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  subnets = [
    {
      ip_cidr_range            = "10.1.0.0/16"
      name                     = "source-subnet"
      private_ip_google_access = true
      purpose                  = "PRIVATE"
      region                   = var.source_location
      role                     = "ACTIVE"
    }
  ]
  firewall_data = [
    {
      name = "gcp-dms-firewall-ingress"
      source_ranges = [
        "10.0.0.0/16", # AWS VPC (entire range)
        "10.2.0.0/20", # Cloud SQL peered range
        "10.0.1.0/24", # Add specific private subnet ranges
        "10.0.2.0/24",
        "10.0.3.0/24"
      ]
      direction = "INGRESS"
      allow_list = [
        {
          protocol = "tcp"
          ports    = ["3306"]
        }
      ]
    },
    {
      name               = "gcp-dms-firewall-egress"
      destination_ranges = ["10.0.0.0/16", "10.2.0.0/20"]
      direction          = "EGRESS"
      allow_list = [
        {
          protocol = "tcp"
          ports    = ["3306"]
        }
      ]
    },
    # {
    #   name          = "allow-ssh"
    #   source_ranges = ["0.0.0.0/0"]
    #   direction     = "INGRESS"
    #   allow_list = [
    #     {
    #       protocol = "tcp"
    #       ports    = ["22"]
    #     }
    #   ]
    # }
  ]
}

# ------------------------------------------------------------------------
# GCP Secret Manager Configuration
# ------------------------------------------------------------------------
module "source_cloudsql_password_secret" {
  secret_id   = "source_db_password_secret"
  source      = "./modules/gcp/secret-manager"
  secret_data = tostring(data.vault_generic_secret.cloudsql.data["password"])
}

# ------------------------------------------------------------------------
# GCP Private Peering Configuration 
# ------------------------------------------------------------------------
resource "google_compute_global_address" "source_sql_private_ip_address" {
  name          = "source-sql-private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  address       = "10.2.0.0"
  network       = module.source_vpc.vpc_id
}

resource "google_service_networking_connection" "source_db_private_vpc_connection" {
  network                 = module.source_vpc.vpc_id
  service                 = "servicenetworking.googleapis.com"
  update_on_creation_fail = true
  deletion_policy         = "ABANDON"
  reserved_peering_ranges = [google_compute_global_address.source_sql_private_ip_address.name]
}

resource "google_compute_network_peering_routes_config" "peering_routes" {
  peering = google_service_networking_connection.source_db_private_vpc_connection.peering
  network = module.source_vpc.vpc_name # Make sure this is the VPC NAME not ID

  import_custom_routes = true
  export_custom_routes = true

  depends_on = [google_service_networking_connection.source_db_private_vpc_connection]
}

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
  deletion_protection_enabled = false # Make it true for production readiness
  vpc_self_link               = module.source_vpc.self_link
  password                    = module.source_cloudsql_password_secret.secret_data
  backup_configuration = {
    enabled                        = true
    location                       = "us-central1"
    binary_log_enabled             = true
    start_time                     = "03:00"
    point_in_time_recovery_enabled = false # Make it true for production readiness
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
# AWS Secret(Vault) Configuration
# ------------------------------------------------------------------------
data "vault_generic_secret" "rds" {
  path = "secret/rds"
}

# ------------------------------------------------------------------------
# AWS VPC Configuration
# ------------------------------------------------------------------------
module "destination_vpc" {
  source                  = "./modules/aws/vpc"
  vpc_name                = "destination-vpc"
  vpc_cidr                = "10.0.0.0/16"
  azs                     = var.destination_azs
  public_subnets          = var.destination_public_subnets
  private_subnets         = var.destination_private_subnets
  database_subnets        = var.destination_database_subnets
  enable_dns_hostnames    = true
  enable_dns_support      = true
  create_igw              = true
  map_public_ip_on_launch = true
  enable_nat_gateway      = true
  single_nat_gateway      = false
  one_nat_gateway_per_az  = true
  tags = {
    Project = "dms-migration"
  }
}

module "dms_sg" {
  source = "./modules/aws/security-groups"
  name   = "dms-sg"
  vpc_id = module.destination_vpc.vpc_id
  ingress_rules = [
    {
      description     = "Allow DMS traffic to RDS"
      from_port       = 3306
      to_port         = 3306
      protocol        = "tcp"
      security_groups = []
      cidr_blocks = [
        "10.0.0.0/16", # AWS VPC
        "10.1.0.0/16", # GCP VPC subnet
        "10.2.0.0/20"  # Cloud SQL peered range
      ]
    }
  ]
  egress_rules = [
    {
      description = "Allow all outbound traffic"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
  tags = {
    Name = "dms-sg"
  }
}

# RDS Security Group
module "destination_rds_sg" {
  source = "./modules/aws/security-groups"
  name   = "destination-rds-sg"
  vpc_id = module.destination_vpc.vpc_id
  ingress_rules = [
    {
      description     = "MySQL from DMS"
      from_port       = 3306
      to_port         = 3306
      protocol        = "tcp"
      security_groups = [module.dms_sg.id]
      cidr_blocks     = []
    },
    {
      description     = "MySQL from VPC"
      from_port       = 3306
      to_port         = 3306
      protocol        = "tcp"
      security_groups = []
      cidr_blocks     = ["10.0.0.0/16"]
    }
  ]
  egress_rules = [
    {
      description = "Allow all outbound traffic"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
  tags = {
    Name = "destination-rds-sg"
  }
}

# ------------------------------------------------------------------------
# AWS Secret Manager Configuration
# ------------------------------------------------------------------------
module "destination_db_credentials" {
  source                  = "./modules/aws/secrets-manager"
  name                    = "destination_rds_secrets"
  description             = "destination_rds_secrets"
  recovery_window_in_days = 35
  secret_string = jsonencode({
    username = tostring(data.vault_generic_secret.rds.data["username"])
    password = tostring(data.vault_generic_secret.rds.data["password"])
  })
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
  skip_final_snapshot    = true # Make it false for production readiness
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
      endpoint = var.notification_email
    }
  ]
}

# ------------------------------------------------------------------------
# VPN Configuration
# ------------------------------------------------------------------------
# Create a HA VPN gateway in GCP (create this first)
resource "google_compute_ha_vpn_gateway" "gcp_vpn_gateway" {
  name    = "gcp-vpn-gateway"
  network = module.source_vpc.vpc_id
  region  = var.source_location
}

# Create a cloud router for BGP with explicit route advertisement
resource "google_compute_router" "gcp_router" {
  name    = "gcp-vpn-router"
  network = module.source_vpc.vpc_id
  region  = var.source_location
  bgp {
    advertise_mode = "CUSTOM"
    # Advertise all subnets including the Cloud SQL subnet
    advertised_groups = ["ALL_SUBNETS"]
    asn               = 65000
    # Explicitly advertise the Cloud SQL subnet range
    # advertised_ip_ranges {
    #   range = "10.1.0.0/16"
    # }

    advertised_ip_ranges {
      range       = "10.2.0.0/20"
      description = "Cloud SQL service networking range"
    }

    # advertised_ip_ranges {
    #   range       = "${google_compute_global_address.source_sql_private_ip_address.address}/${google_compute_global_address.source_sql_private_ip_address.prefix_length}"
    #   description = "Cloud SQL peered range"
    # }
  }
}

# Create a VPN gateway in AWS
resource "aws_vpn_gateway" "aws_vpn_gw" {
  vpc_id          = module.destination_vpc.vpc_id
  amazon_side_asn = 65001
  tags = {
    Name = "aws-vpn-gateway"
  }
}

# Attach VPN gateway to VPC
resource "aws_vpn_gateway_attachment" "vpn_attachment" {
  vpn_gateway_id = aws_vpn_gateway.aws_vpn_gw.id
  vpc_id         = module.destination_vpc.vpc_id
}

# Create customer gateways representing the GCP side
resource "aws_customer_gateway" "gcp_cgw_1" {
  bgp_asn    = 65000
  ip_address = google_compute_ha_vpn_gateway.gcp_vpn_gateway.vpn_interfaces[0].ip_address
  type       = "ipsec.1"

  tags = {
    Name = "aws-customer-gw-1"
  }

  depends_on = [google_compute_ha_vpn_gateway.gcp_vpn_gateway]
}

resource "aws_customer_gateway" "gcp_cgw_2" {
  bgp_asn    = 65000
  ip_address = google_compute_ha_vpn_gateway.gcp_vpn_gateway.vpn_interfaces[1].ip_address
  type       = "ipsec.1"

  tags = {
    Name = "aws-customer-gw-2"
  }

  depends_on = [google_compute_ha_vpn_gateway.gcp_vpn_gateway]
}

# Create VPN connections to GCP
resource "aws_vpn_connection" "vpn_connection_1" {
  vpn_gateway_id      = aws_vpn_gateway.aws_vpn_gw.id
  customer_gateway_id = aws_customer_gateway.gcp_cgw_1.id
  type                = "ipsec.1"
  static_routes_only  = false

  tags = {
    Name = "vpn-connection-1"
  }

  depends_on = [aws_vpn_gateway_attachment.vpn_attachment]
}

resource "aws_vpn_connection" "vpn_connection_2" {
  vpn_gateway_id      = aws_vpn_gateway.aws_vpn_gw.id
  customer_gateway_id = aws_customer_gateway.gcp_cgw_2.id
  type                = "ipsec.1"
  static_routes_only  = false

  tags = {
    Name = "vpn-connection-2"
  }

  depends_on = [aws_vpn_gateway_attachment.vpn_attachment]
}

# Create external VPN gateway representing the AWS side
resource "google_compute_external_vpn_gateway" "aws_vpn_gateway_1" {
  name            = "aws-vpn-gateway"
  redundancy_type = "FOUR_IPS_REDUNDANCY"
  description     = "AWS VPN Gateway"

  interface {
    id         = 0
    ip_address = aws_vpn_connection.vpn_connection_1.tunnel1_address
  }
  interface {
    id         = 1
    ip_address = aws_vpn_connection.vpn_connection_1.tunnel2_address
  }
  interface {
    id         = 2
    ip_address = aws_vpn_connection.vpn_connection_2.tunnel1_address
  }
  interface {
    id         = 3
    ip_address = aws_vpn_connection.vpn_connection_2.tunnel2_address
  }
}

# Create VPN tunnels on GCP side
resource "google_compute_vpn_tunnel" "gcp_tunnel1" {
  name                            = "gcp-tunnel1"
  region                          = var.source_location
  vpn_gateway                     = google_compute_ha_vpn_gateway.gcp_vpn_gateway.id
  peer_external_gateway           = google_compute_external_vpn_gateway.aws_vpn_gateway_1.id
  peer_external_gateway_interface = 0
  shared_secret                   = aws_vpn_connection.vpn_connection_1.tunnel1_preshared_key
  router                          = google_compute_router.gcp_router.id
  vpn_gateway_interface           = 0
  ike_version                     = 2
}

resource "google_compute_vpn_tunnel" "gcp_tunnel2" {
  name                            = "gcp-tunnel2"
  region                          = var.source_location
  vpn_gateway                     = google_compute_ha_vpn_gateway.gcp_vpn_gateway.id
  peer_external_gateway           = google_compute_external_vpn_gateway.aws_vpn_gateway_1.id
  peer_external_gateway_interface = 1
  shared_secret                   = aws_vpn_connection.vpn_connection_1.tunnel2_preshared_key
  router                          = google_compute_router.gcp_router.id
  vpn_gateway_interface           = 0
  ike_version                     = 2
}

resource "google_compute_vpn_tunnel" "gcp_tunnel3" {
  name                            = "gcp-tunnel3"
  region                          = var.source_location
  vpn_gateway                     = google_compute_ha_vpn_gateway.gcp_vpn_gateway.id
  peer_external_gateway           = google_compute_external_vpn_gateway.aws_vpn_gateway_1.id
  peer_external_gateway_interface = 2
  shared_secret                   = aws_vpn_connection.vpn_connection_2.tunnel1_preshared_key
  router                          = google_compute_router.gcp_router.id
  vpn_gateway_interface           = 1
  ike_version                     = 2
}

resource "google_compute_vpn_tunnel" "gcp_tunnel4" {
  name                            = "gcp-tunnel4"
  region                          = var.source_location
  vpn_gateway                     = google_compute_ha_vpn_gateway.gcp_vpn_gateway.id
  peer_external_gateway           = google_compute_external_vpn_gateway.aws_vpn_gateway_1.id
  peer_external_gateway_interface = 3
  shared_secret                   = aws_vpn_connection.vpn_connection_2.tunnel2_preshared_key
  router                          = google_compute_router.gcp_router.id
  vpn_gateway_interface           = 1
  ike_version                     = 2
}

# Create router interfaces for BGP
resource "google_compute_router_interface" "gcp_interface1" {
  name   = "gcp-interface1"
  router = google_compute_router.gcp_router.name
  region = var.source_location
  # FIXED: GCP side uses VGW inside address (AWS's side)
  ip_range   = "${aws_vpn_connection.vpn_connection_1.tunnel1_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.gcp_tunnel1.name
}

resource "google_compute_router_interface" "gcp_interface2" {
  name       = "gcp-interface2"
  router     = google_compute_router.gcp_router.name
  region     = var.source_location
  ip_range   = "${aws_vpn_connection.vpn_connection_1.tunnel2_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.gcp_tunnel2.name
}

resource "google_compute_router_interface" "gcp_interface3" {
  name       = "gcp-interface3"
  router     = google_compute_router.gcp_router.name
  region     = var.source_location
  ip_range   = "${aws_vpn_connection.vpn_connection_2.tunnel1_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.gcp_tunnel3.name
}

resource "google_compute_router_interface" "gcp_interface4" {
  name       = "gcp-interface4"
  router     = google_compute_router.gcp_router.name
  region     = var.source_location
  ip_range   = "${aws_vpn_connection.vpn_connection_2.tunnel2_cgw_inside_address}/30"
  vpn_tunnel = google_compute_vpn_tunnel.gcp_tunnel4.name
}

# Create BGP sessions
resource "google_compute_router_peer" "gcp_bgp_peer1" {
  name   = "gcp-bgp-peer1"
  router = google_compute_router.gcp_router.name
  region = var.source_location
  # FIXED: Peer IP is the CGW inside address (GCP's own IP on AWS side)
  peer_ip_address           = aws_vpn_connection.vpn_connection_1.tunnel1_vgw_inside_address
  peer_asn                  = 65001
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.gcp_interface1.name
}

resource "google_compute_router_peer" "gcp_bgp_peer2" {
  name                      = "gcp-bgp-peer2"
  router                    = google_compute_router.gcp_router.name
  region                    = var.source_location
  peer_ip_address           = aws_vpn_connection.vpn_connection_1.tunnel2_vgw_inside_address
  peer_asn                  = 65001
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.gcp_interface2.name
}

resource "google_compute_router_peer" "gcp_bgp_peer3" {
  name                      = "gcp-bgp-peer3"
  router                    = google_compute_router.gcp_router.name
  region                    = var.source_location
  peer_ip_address           = aws_vpn_connection.vpn_connection_2.tunnel1_vgw_inside_address
  peer_asn                  = 65001
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.gcp_interface3.name
}

resource "google_compute_router_peer" "gcp_bgp_peer4" {
  name                      = "gcp-bgp-peer4"
  router                    = google_compute_router.gcp_router.name
  region                    = var.source_location
  peer_ip_address           = aws_vpn_connection.vpn_connection_2.tunnel2_vgw_inside_address
  peer_asn                  = 65001
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.gcp_interface4.name
}

# Enable route propagation on AWS private route tables
resource "aws_vpn_gateway_route_propagation" "private_routes" {
  count          = length(module.destination_vpc.private_route_table_ids)
  vpn_gateway_id = aws_vpn_gateway.aws_vpn_gw.id
  route_table_id = module.destination_vpc.private_route_table_ids[count.index]

  depends_on = [
    aws_vpn_gateway_attachment.vpn_attachment,
    aws_vpn_connection.vpn_connection_1,
    aws_vpn_connection.vpn_connection_2
  ]
}

# Add explicit static routes as backup (in case BGP takes time)
resource "aws_route" "to_gcp_subnet" {
  count                  = length(module.destination_vpc.private_route_table_ids)
  route_table_id         = module.destination_vpc.private_route_table_ids[count.index]
  destination_cidr_block = "10.1.0.0/16"
  gateway_id             = aws_vpn_gateway.aws_vpn_gw.id

  depends_on = [
    aws_vpn_gateway_attachment.vpn_attachment,
    google_compute_vpn_tunnel.gcp_tunnel1,
    google_compute_vpn_tunnel.gcp_tunnel2,
    google_compute_vpn_tunnel.gcp_tunnel3,
    google_compute_vpn_tunnel.gcp_tunnel4
  ]
}

# Add route for Cloud SQL peered range
resource "aws_route" "to_gcp_cloudsql_peered" {
  count                  = length(module.destination_vpc.private_route_table_ids)
  route_table_id         = module.destination_vpc.private_route_table_ids[count.index]
  destination_cidr_block = "10.2.0.0/20"
  gateway_id             = aws_vpn_gateway.aws_vpn_gw.id

  depends_on = [
    aws_vpn_gateway_attachment.vpn_attachment,
    google_compute_vpn_tunnel.gcp_tunnel1,
    google_compute_vpn_tunnel.gcp_tunnel2,
    google_compute_vpn_tunnel.gcp_tunnel3,
    google_compute_vpn_tunnel.gcp_tunnel4
  ]
}

# Wait for VPN tunnels and BGP to establish (increased from 60s to 300s)
resource "time_sleep" "wait_for_vpn" {
  depends_on = [
    aws_vpn_gateway_route_propagation.private_routes,
    aws_route.to_gcp_subnet,
    aws_route.to_gcp_cloudsql_peered,
    google_compute_router_peer.gcp_bgp_peer1,
    google_compute_router_peer.gcp_bgp_peer2,
    google_compute_router_peer.gcp_bgp_peer3,
    google_compute_router_peer.gcp_bgp_peer4
  ]

  create_duration = "300s"
}

# ------------------------------------------------------------------------
# DMS IAM Configuration
# ------------------------------------------------------------------------
data "aws_iam_policy_document" "dms_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["dms.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "dms_vpc_role" {
  name               = "dms-vpc-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
}

resource "aws_iam_role_policy_attachment" "dms_vpc_role_attachment" {
  role       = aws_iam_role.dms_vpc_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

resource "aws_iam_role" "dms_cloudwatch_logs_role" {
  name               = "dms-cloudwatch-logs-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
}

resource "aws_iam_role_policy_attachment" "dms_cloudwatch_logs_role_attachment" {
  role       = aws_iam_role.dms_cloudwatch_logs_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
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

  source_endpoint_id   = "cloudsql-source"
  source_endpoint_type = "source"
  source_engine_name   = "mysql"
  source_username      = tostring(data.vault_generic_secret.cloudsql.data["username"])
  source_password      = tostring(data.vault_generic_secret.cloudsql.data["password"])
  source_server_name   = module.source_db.private_ip_address
  source_port          = 3306
  source_ssl_mode      = "none" # require

  destination_endpoint_id   = "rds"
  destination_endpoint_type = "target"
  destination_engine_name   = "mysql"
  destination_username      = tostring(data.vault_generic_secret.rds.data["username"])
  destination_password      = tostring(data.vault_generic_secret.rds.data["password"])
  destination_server_name   = split(":", module.destination_db.endpoint)[0]
  destination_port          = 3306
  destination_ssl_mode      = "none" # require

  tasks = [
    {
      migration_type      = "full-load-and-cdc"
      replication_task_id = "cloudsql-to-rds-task"
      replication_task_settings = jsonencode({
        TargetMetadata = {
          TargetSchema       = ""
          SupportLobs        = true
          FullLobMode        = false
          LobChunkSize       = 64
          LimitedSizeLobMode = true
          LobMaxSize         = 32
        }
        FullLoadSettings = {
          TargetTablePrepMode = "TRUNCATE"
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
              "schema-name" : var.source_db,
              "table-name" : "%"
            },
            "rule-action" : "rename",
            "value" : "${var.source_db}",
            "old-value" : null
          }
        ]
      })
    }
  ]

  depends_on = [
    aws_iam_role_policy_attachment.dms_vpc_role_attachment,
    aws_iam_role_policy_attachment.dms_cloudwatch_logs_role_attachment,
    module.source_db,
    module.destination_db,
    time_sleep.wait_for_vpn
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

# -----------------------------------------------------------------------------------------
# VPN Health Check and Validation
# -----------------------------------------------------------------------------------------
resource "null_resource" "validate_vpn_connectivity" {
  depends_on = [
    google_compute_router_peer.gcp_bgp_peer1,
    google_compute_router_peer.gcp_bgp_peer2,
    google_compute_router_peer.gcp_bgp_peer3,
    google_compute_router_peer.gcp_bgp_peer4,
    aws_vpn_gateway_route_propagation.private_routes
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for VPN tunnels to establish..."
      sleep 60
      
      # Check AWS VPN connection status
      echo "Checking AWS VPN Connection 1 status..."
      aws ec2 describe-vpn-connections \
        --vpn-connection-ids ${aws_vpn_connection.vpn_connection_1.id} \
        --query 'VpnConnections[0].VgwTelemetry[*].[OutsideIpAddress,Status]' \
        --output table
      
      echo "Checking AWS VPN Connection 2 status..."
      aws ec2 describe-vpn-connections \
        --vpn-connection-ids ${aws_vpn_connection.vpn_connection_2.id} \
        --query 'VpnConnections[0].VgwTelemetry[*].[OutsideIpAddress,Status]' \
        --output table
      
      # Wait for BGP to converge
      echo "Waiting 3 minutes for BGP convergence..."
      sleep 180
      
      # Check BGP session status on GCP
      echo "Checking GCP BGP session status..."
      gcloud compute routers get-status ${google_compute_router.gcp_router.name} \
        --region=${var.source_location} \
        --format="table(result.bgpPeerStatus[].name,result.bgpPeerStatus[].state)"
      
      echo "VPN validation complete. Check logs above for any DOWN tunnels."
    EOT
  }
}

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