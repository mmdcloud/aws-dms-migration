
resource "google_compute_instance" "instance" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  dynamic "network_interface" {
    for_each = var.network_interfaces
    content {
      network    = network_interface.value["network"]
      subnetwork = network_interface.value["subnetwork"]
      dynamic "access_config" {
        for_each = network_interface.value["access_configs"]
        content {
          nat_ip = access_config.value["nat_ip"]
        }
      }
    }
  }
  metadata_startup_script = var.metadata_startup_script

  boot_disk {
    initialize_params {
      image = var.image
    }
  }

  deletion_protection       = var.deletion_protection
  allow_stopping_for_update = var.allow_stopping_for_update
  tags = var.tags
}
