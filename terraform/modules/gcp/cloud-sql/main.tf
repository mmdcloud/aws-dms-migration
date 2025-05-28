resource "google_compute_global_address" "carshub_sql_private_ip_address" {
  name          = "carshub-sql-private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.vpc_id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = var.vpc_id
  service                 = "servicenetworking.googleapis.com"
  update_on_creation_fail = true
  deletion_policy         = "ABANDON"
  reserved_peering_ranges = [google_compute_global_address.carshub_sql_private_ip_address.name]
}

resource "google_sql_database_instance" "db_instance" {
  name             = var.name
  region           = var.location
  database_version = var.db_version
  root_password    = var.password
  settings {
    tier                        = var.tier
    availability_type           = var.availability_type
    disk_size                   = var.disk_size
    disk_type                   = var.disk_type
    disk_autoresize             = var.disk_autoresize
    disk_autoresize_limit       = var.disk_autoresize_limit
    deletion_protection_enabled = var.deletion_protection_enabled
    dynamic "database_flags" {
      for_each = var.database_flags
      content {
        name  = database_flags.value["name"]
        value = database_flags.value["value"]
      }
    }
    dynamic "backup_configuration" {
      for_each = var.backup_configuration
      content {
        enabled                        = backup_configuration.value["enabled"]
        location                       = backup_configuration.value["location"]
        binary_log_enabled             = backup_configuration.value["binary_log_enabled"]
        start_time                     = backup_configuration.value["start_time"]
        point_in_time_recovery_enabled = backup_configuration.value["point_in_time_recovery_enabled"]
        dynamic "backup_retention_settings" {
          for_each = backup_configuration.value["backup_retention_settings"]
          content {
            retained_backups = backup_retention_settings.value["retained_backups"]
            retention_unit   = backup_retention_settings.value["retention_unit"]
          }
        }
      }
    }
    ip_configuration {
      ipv4_enabled                                  = var.ipv4_enabled
      private_network                               = var.vpc_self_link
      enable_private_path_for_google_cloud_services = true
      # authorized_networks {
      #   name  = "all"
      #   value = "0.0.0.0/0"
      # }
    }
  }
  deletion_protection = false
  depends_on          = [google_service_networking_connection.private_vpc_connection]
}


resource "google_sql_database" "db" {
  name     = var.db_name
  instance = google_sql_database_instance.db_instance.name
}

resource "google_sql_user" "db_user" {
  name        = var.db_user
  instance    = google_sql_database_instance.db_instance.name
  password = var.password
  host        = "%"
}
