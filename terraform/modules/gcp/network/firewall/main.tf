resource "google_compute_firewall" "carshub_firewall" {
  count         = length(var.firewall_data)
  name          = element(var.firewall_data[*].firewall_name, count.index)
  direction     = element(var.firewall_data[*].firewall_direction, count.index)
  network       = var.vpc_id
  source_ranges = element(var.firewall_data[*].source_ranges, count.index)
  dynamic "allow" {
    # for_each = var.firewall_data[*].allow_list
    for_each = flatten([for data in var.firewall_data : data.allow_list])
    content {
      ports    = allow.value["ports"]
      protocol = allow.value["protocol"]
    }
  }
  target_tags = element(var.firewall_data[*].target_tags, count.index)
}