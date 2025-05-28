variable "firewall_data" {
  type = list(object({
    firewall_name      = string
    firewall_direction = string
    target_tags        = list(string)
    source_ranges      = list(string)
    allow_list = list(object({
      protocol = string
      ports    = list(string)
    }))
  }))
}
variable "vpc_id" {
  
}