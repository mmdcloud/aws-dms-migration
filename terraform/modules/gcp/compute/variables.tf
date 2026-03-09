
variable "name" {}
variable "machine_type" {}
variable "zone" {}
variable  "deletion_protection" {}
variable  "allow_stopping_for_update" {}
variable "metadata_startup_script" {}
variable "image" {}
variable "network_interfaces" {
  type = list(object({
    network = string
    subnetwork = string
    access_configs = list(object({
      nat_ip = string
    }))
  }))
}
variable "tags" {}