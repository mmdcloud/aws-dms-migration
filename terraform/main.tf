locals {
  common_tags = {
    Project   = "dms-migration"
    ManagedBy = "terraform"
  }
}

resource "random_id" "id" {
  byte_length = 8
}

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
        "10.0.0.0/16",
        "10.2.0.0/20",
        "10.0.1.0/24",
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
      name = "gcp-dms-firewall-ssh"
      source_ranges = [
        "35.235.240.0/20" # GCP IAP TCP forwarding range
      ]
      direction = "INGRESS"
      allow_list = [
        {
          protocol = "tcp"
          ports    = ["22"]
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
    }
  ]
}

# # ------------------------------------------------------------------------
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
        "10.0.0.0/16",
        "10.1.0.0/16",
        "10.2.0.0/20"
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

module "destination_test_instance_sg" {
  source = "./modules/aws/security-groups"
  name   = "destination-test-instance-sg"
  vpc_id = module.destination_vpc.vpc_id
  ingress_rules = [
    {
      # SSH restricted to VPC CIDR only.
      # Use AWS Systems Manager Session Manager for public access instead:
      # aws ssm start-session --target <instance-id>
      # This requires the SSM agent and an instance profile with AmazonSSMManagedInstanceCore.
      description     = "Allow SSH from within VPC only"
      from_port       = 22
      to_port         = 22
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
    Name = "destination-test-instance-sg"
  }
}

# ------------------------------------------------------------------------
# AWS Secret Manager Configuration
# ------------------------------------------------------------------------
module "destination_db_credentials" {
  source                  = "./modules/aws/secrets-manager"
  name                    = "destination-rds-secrets-${random_id.id.hex}"
  description             = "destination_rds_secrets"
  recovery_window_in_days = 30
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
  skip_final_snapshot    = true # Make it false in production 
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

    advertised_ip_ranges {
      range       = "10.2.0.0/20"
      description = "Cloud SQL service networking range"
    }
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
  name                      = "gcp-bgp-peer1"
  router                    = google_compute_router.gcp_router.name
  region                    = var.source_location
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

# Make sure awscli, boto3 and gcloud are installed on your local system 

# Wait for VPN tunnels and BGP to establish (increased from 60s to 300s)
# Wait for all 4 BGP sessions to reach ESTABLISHED before allowing DMS to proceed.
# Replaces a blind time_sleep: polls every 30s for up to 15 minutes, then fails
# loudly with the actual BGP state so the error is diagnosable.
resource "null_resource" "wait_for_vpn_bgp" {
  depends_on = [
    aws_vpn_gateway_route_propagation.private_routes,
    aws_route.to_gcp_subnet,
    aws_route.to_gcp_cloudsql_peered,
    google_compute_router_peer.gcp_bgp_peer1,
    google_compute_router_peer.gcp_bgp_peer2,
    google_compute_router_peer.gcp_bgp_peer3,
    google_compute_router_peer.gcp_bgp_peer4
  ]

  triggers = {
    vpn_connection_1_id = aws_vpn_connection.vpn_connection_1.id
    vpn_connection_2_id = aws_vpn_connection.vpn_connection_2.id
    router_name         = google_compute_router.gcp_router.name
    region              = var.source_location
    # Route table IDs as a CSV so a change re-triggers the check
    private_route_tables = join(",", module.destination_vpc.private_route_table_ids)
    # Cloud SQL peering range — re-trigger if it ever changes
    cloudsql_range = google_compute_global_address.source_sql_private_ip_address.address
  }

  provisioner "local-exec" {
    command = <<-EOT
      #!/usr/bin/env bash
      set -euo pipefail

      # ── tunables ──────────────────────────────────────────────────────────
      IPSEC_MAX_RETRIES=20     # 20 × 15s = 5 min for IPSec to come up
      IPSEC_SLEEP_SEC=15
      IPSEC_REQUIRED_UP=2      # At least 2/4 endpoints must be UP (HA minimum)

      BGP_MAX_RETRIES=30       # 30 × 30s = 15 min for BGP to converge
      BGP_SLEEP_SEC=30
      BGP_REQUIRED_ESTABLISHED=4

      CONN1="${self.triggers.vpn_connection_1_id}"
      CONN2="${self.triggers.vpn_connection_2_id}"
      ROUTER="${self.triggers.router_name}"
      REGION="${self.triggers.region}"
      CLOUDSQL_RANGE="${self.triggers.cloudsql_range}/20"
      ROUTE_TABLES="${self.triggers.private_route_tables}"

      SEP="════════════════════════════════════════════════════════════════"

      # ── helpers ───────────────────────────────────────────────────────────
      ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

      dump_diagnostics() {
        echo ""
        echo "$SEP"
        echo "  DIAGNOSTIC DUMP — $(ts)"
        echo "$SEP"

        echo ""
        echo "── AWS: VPN tunnel telemetry ────────────────────────────────"
        aws ec2 describe-vpn-connections \
          --vpn-connection-ids "$CONN1" "$CONN2" \
          --query 'VpnConnections[*].{ID:VpnConnectionId,Tunnels:VgwTelemetry[*].{IP:OutsideIpAddress,Status:Status,LastChanged:LastStatusChange,Reason:StatusMessage}}' \
          --output json 2>/dev/null || echo "  (aws CLI query failed)"

        echo ""
        echo "── AWS: BGP routes in private route tables ──────────────────"
        IFS=',' read -ra RT_IDS <<< "$ROUTE_TABLES"
        for rt in "$${RT_IDS[@]}"; do
          echo "  Route table: $rt"
          aws ec2 describe-route-tables \
            --route-table-ids "$rt" \
            --query "RouteTables[0].Routes[?GatewayId!=null].[DestinationCidrBlock,GatewayId,State,Origin]" \
            --output table 2>/dev/null || echo "  (query failed for $rt)"
        done

        echo ""
        echo "── GCP: BGP peer status ─────────────────────────────────────"
        gcloud compute routers get-status "$ROUTER" \
          --region="$REGION" \
          --format="table(
            result.bgpPeerStatus[].name,
            result.bgpPeerStatus[].state,
            result.bgpPeerStatus[].status,
            result.bgpPeerStatus[].uptime,
            result.bgpPeerStatus[].numLearnedRoutes
          )" 2>/dev/null || echo "  (gcloud query failed)"

        echo ""
        echo "── GCP: Advertised routes from router ───────────────────────"
        gcloud compute routers get-status "$ROUTER" \
          --region="$REGION" \
          --format="json" 2>/dev/null \
          | python3 -c "
import sys, json
data = json.load(sys.stdin)
peers = data.get('result', {}).get('bgpPeerStatus', [])
for p in peers:
    routes = p.get('advertisedRoutes', [])
    print(f\"  Peer: {p.get('name')}  advertised={len(routes)} routes\")
    for r in routes:
        print(f\"    {r.get('destRange')}\")
" 2>/dev/null || echo "  (route parse failed)"

        echo "$SEP"
        echo ""
      }

      # ═════════════════════════════════════════════════════════════════════
      # PHASE 1 — AWS IPSec tunnel endpoints
      # Must have at least $IPSEC_REQUIRED_UP endpoints UP before BGP check.
      # BGP runs on top of IPSec; checking BGP while IPSec is DOWN wastes
      # the entire 15-minute window.
      # ═════════════════════════════════════════════════════════════════════
      echo ""
      echo "$SEP"
      echo "  PHASE 1 — AWS IPSec layer  (need $${IPSEC_REQUIRED_UP}/4 UP)"
      echo "  Max wait: $(( IPSEC_MAX_RETRIES * IPSEC_SLEEP_SEC ))s"
      echo "$SEP"

      for i in $(seq 1 $IPSEC_MAX_RETRIES); do
        TUNNEL_JSON=$(aws ec2 describe-vpn-connections \
          --vpn-connection-ids "$CONN1" "$CONN2" \
          --query 'VpnConnections[*].VgwTelemetry[*].{status:Status,ip:OutsideIpAddress,reason:StatusMessage}' \
          --output json 2>/dev/null || echo '[]')

        TUNNELS_UP=$(echo "$TUNNEL_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
# flatten nested lists
flat = [t for conn in data for t in conn]
up   = [t for t in flat if t.get('status') == 'UP']
print(len(up))
" 2>/dev/null || echo "0")

        echo "  [$(ts)] Attempt $i/$${IPSEC_MAX_RETRIES}: $${TUNNELS_UP}/4 tunnel endpoints UP"

        if [ "$${TUNNELS_UP}" -ge "$${IPSEC_REQUIRED_UP}" ]; then
          echo "  ✓ IPSec layer ready ($${TUNNELS_UP}/4 UP). Proceeding to BGP check."
          break
        fi

        if [ "$i" -eq "$${IPSEC_MAX_RETRIES}" ]; then
          echo ""
          echo "ERROR: IPSec did not reach $${IPSEC_REQUIRED_UP} UP endpoints after $(( IPSEC_MAX_RETRIES * IPSEC_SLEEP_SEC ))s."
          echo "Possible causes: pre-shared key mismatch, firewall blocking UDP 500/4500, or IKE version mismatch."
          dump_diagnostics
          exit 1
        fi

        sleep "$${IPSEC_SLEEP_SEC}"
      done

      # ═════════════════════════════════════════════════════════════════════
      # PHASE 2 — GCP BGP session convergence
      # All 4 peers must reach state=ESTABLISHED and status=UP.
      # ESTABLISHED alone is insufficient — status catches IKE/hold-timer issues
      # that leave BGP partially negotiated.
      # ═════════════════════════════════════════════════════════════════════
      echo ""
      echo "$SEP"
      echo "  PHASE 2 — GCP BGP layer  (need $${BGP_REQUIRED_ESTABLISHED}/4 ESTABLISHED)"
      echo "  Max wait: $(( BGP_MAX_RETRIES * BGP_SLEEP_SEC ))s"
      echo "$SEP"

      for i in $(seq 1 $BGP_MAX_RETRIES); do
        STATUS_JSON=$(gcloud compute routers get-status "$ROUTER" \
          --region="$REGION" \
          --format=json 2>/dev/null || echo '{}')

        ESTABLISHED=$(echo "$STATUS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
peers = data.get('result', {}).get('bgpPeerStatus', [])
ok = [p for p in peers if p.get('status') == 'UP' and p.get('state') == 'ESTABLISHED']
# Print count and summary for logging
for p in peers:
    state  = p.get('state', 'UNKNOWN')
    status = p.get('status', 'UNKNOWN')
    uptime = p.get('uptime', '-')
    routes = p.get('numLearnedRoutes', 0)
    print(f\"PEER {p.get('name')}: state={state} status={status} uptime={uptime} learned_routes={routes}\", file=__import__('sys').stderr)
print(len(ok))
" 2>/tmp/bgp_peer_detail || echo "0")

        # Surface per-peer detail to the apply log
        cat /tmp/bgp_peer_detail 2>/dev/null | sed 's/^/  /' || true

        echo "  [$(ts)] Attempt $i/$${BGP_MAX_RETRIES}: $${ESTABLISHED}/$${BGP_REQUIRED_ESTABLISHED} BGP sessions ESTABLISHED"

        if [ "$${ESTABLISHED}" -ge "$${BGP_REQUIRED_ESTABLISHED}" ]; then
          echo "  ✓ BGP fully converged ($${ESTABLISHED}/$${BGP_REQUIRED_ESTABLISHED}). Proceeding to route check."
          break
        fi

        if [ "$i" -eq "$${BGP_MAX_RETRIES}" ]; then
          echo ""
          echo "ERROR: BGP did not fully converge after $(( BGP_MAX_RETRIES * BGP_SLEEP_SEC ))s."
          echo "Possible causes: ASN mismatch (GCP=65000, AWS=65001), BGP timer mismatch, or missing route advertisement."
          dump_diagnostics
          exit 1
        fi

        sleep "$${BGP_SLEEP_SEC}"
      done

      # ═════════════════════════════════════════════════════════════════════
      # PHASE 3 — Route reachability validation
      # BGP ESTABLISHED does not guarantee routes are propagated to AWS route
      # tables. This phase catches the common split-brain case where BGP is up
      # but the Cloud SQL peering range never appears in AWS routing.
      # ═════════════════════════════════════════════════════════════════════
      echo ""
      echo "$SEP"
      echo "  PHASE 3 — Route reachability ($${CLOUDSQL_RANGE} visible in AWS route tables?)"
      echo "$SEP"

      ROUTE_FOUND=false
      IFS=',' read -ra RT_IDS <<< "$ROUTE_TABLES"

      for rt in "$${RT_IDS[@]}"; do
        HIT=$(aws ec2 describe-route-tables \
          --route-table-ids "$rt" \
          --query "RouteTables[0].Routes[?DestinationCidrBlock=='$${CLOUDSQL_RANGE}'].State" \
          --output text 2>/dev/null || echo "")

        if [ -n "$HIT" ]; then
          echo "  ✓ $${CLOUDSQL_RANGE} found in route table $rt (state: $HIT)"
          ROUTE_FOUND=true
        else
          echo "  ✗ $${CLOUDSQL_RANGE} NOT found in route table $rt"
        fi
      done

      if [ "$ROUTE_FOUND" = "false" ]; then
        echo ""
        echo "ERROR: Cloud SQL peering range $${CLOUDSQL_RANGE} not present in any private route table."
        echo "BGP is ESTABLISHED but routes have not propagated. Check:"
        echo "  1. GCP router is advertising the 10.2.0.0/20 range (see advertised_ip_ranges in google_compute_router)"
        echo "  2. aws_vpn_gateway_route_propagation is applied to all private route tables"
        echo "  3. BGP hold-timer has not expired between phases 2 and 3"
        dump_diagnostics
        exit 1
      fi

      echo ""
      echo "── GCP: Verifying advertised prefix count ────────────────────"
      ADVERTISED=$(gcloud compute routers get-status "$ROUTER" \
        --region="$REGION" \
        --format=json 2>/dev/null \
        | python3 -c "
import sys, json
data = json.load(sys.stdin)
peers = data.get('result', {}).get('bgpPeerStatus', [])
total = sum(len(p.get('advertisedRoutes', [])) for p in peers)
print(total)
" 2>/dev/null || echo "0")

      if [ "$${ADVERTISED}" -eq 0 ]; then
        echo "  WARNING: GCP router is advertising 0 routes. DMS may connect but Cloud SQL traffic may not route correctly."
        echo "  Check google_compute_router.bgp.advertised_ip_ranges and advertised_groups."
      else
        echo "  ✓ GCP router advertising $${ADVERTISED} route(s) across all peers."
      fi

      # ═════════════════════════════════════════════════════════════════════
      # ALL PHASES PASSED
      # ═════════════════════════════════════════════════════════════════════
      echo ""
      echo "$SEP"
      echo "  ✓ ALL PHASES PASSED — VPN fully ready for DMS at $(ts)"
      echo "  IPSec: UP | BGP: ESTABLISHED ($${BGP_REQUIRED_ESTABLISHED}/$${BGP_REQUIRED_ESTABLISHED}) | Routes: propagated"
      echo "$SEP"
      echo ""
    EOT
  }
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

# -----------------------------------------------------------------------------------------
# Test Instances
# -----------------------------------------------------------------------------------------
# GCP Instance
resource "google_compute_address" "gcp_vm_ip" {
  name = "gcp-vm-public-ip"
}

module "source_test_instance" {
  source                    = "./modules/gcp/compute"
  name                      = "source-test-instance"
  machine_type              = "e2-micro"
  zone                      = "${var.source_location}-a"
  metadata_startup_script   = file("${path.module}/scripts/user_data.sh")
  deletion_protection       = false
  allow_stopping_for_update = true
  image                     = "ubuntu-os-cloud/ubuntu-2004-focal-v20220712"
  network_interfaces = [
    {
      network    = module.source_vpc.vpc_id
      subnetwork = module.source_vpc.subnets[0].id
      access_configs = [
        {
          nat_ip = google_compute_address.gcp_vm_ip.address
        }
      ]
    }
  ]
  tags = ["gcp-instance"]
}

resource "aws_iam_role" "ec2_role" {
  name = "ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_instance_profile" "destination_test_iam_instance_profile" {
  name = "destination-test-instance-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# AWS Instance
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

module "destination_test_instance" {
  source                      = "./modules/aws/ec2"
  name                        = "destination-test-instance"
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  subnet_id                   = module.destination_vpc.public_subnets[0]
  security_groups             = [module.destination_test_instance_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.destination_test_iam_instance_profile.name
  user_data                   = filebase64("${path.module}/scripts/user_data.sh")
}