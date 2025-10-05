resource "google_compute_network" "vpc" {
  name                            = var.vpc_name
  delete_default_routes_on_create = var.delete_default_routes_on_create
  auto_create_subnetworks         = var.auto_create_subnetworks
  routing_mode                    = var.routing_mode
}

resource "google_compute_subnetwork" "subnets" {
  count                    = length(var.subnets)
  name                     = var.subnets[count.index].name
  ip_cidr_range            = var.subnets[count.index].ip_cidr_range
  region                   = var.subnets[count.index].region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = var.subnets[count.index].private_ip_google_access
  purpose                  = var.subnets[count.index].purpose
  role                     = var.subnets[count.index].role
}

resource "google_compute_firewall" "firewall" {
  count   = length(var.firewall_data)
  name    = var.firewall_data[count.index].name
  network = google_compute_network.vpc.id
  dynamic "allow" {
    for_each = var.firewall_data[count.index].allow_list
    content {
      protocol = allow.value["protocol"]
      ports    = allow.value["ports"]
    }
  }

  source_ranges = var.firewall_data[count.index].source_ranges
}
