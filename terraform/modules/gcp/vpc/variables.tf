variable "vpc_name" {}
variable "delete_default_routes_on_create" {}
variable "auto_create_subnetworks" {}
variable "routing_mode" {}
variable "firewall_data" {
  type = list(object({
    name          = string
    source_ranges = set(string)
    allow_list = set(object({
      protocol = string
      ports    = list(string)
    }))
  }))
}
variable "subnets" {
  type = list(object({
    name                     = string
    ip_cidr_range            = string
    region                   = string
    private_ip_google_access = bool
    purpose                  = string
    role                     = string
  }))
}