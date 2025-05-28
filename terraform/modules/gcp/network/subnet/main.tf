# Subnets
resource "google_compute_subnetwork" "subnet" {
  count                    = length(var.subnets)
  name                     = "${var.name}-${count.index}"
  ip_cidr_range            = element(var.subnets[*], count.index)
  region                   = var.location
  private_ip_google_access = var.private_ip_google_access
  network                  = var.vpc_id
}
