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