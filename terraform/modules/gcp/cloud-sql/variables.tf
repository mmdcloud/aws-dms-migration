variable "name" {}
variable "location" {}
variable "db_name" {}
variable "db_version" {}
variable "tier" {}
variable "db_user" {}
variable "password" {}
variable "vpc_id" {}
variable "vpc_self_link" {}
variable "ipv4_enabled" {}
variable "deletion_protection_enabled" {}
variable "availability_type" {}
variable "disk_size" {}
variable "disk_type" {
  type = string
  default = "PD_SSD"
}
variable "disk_autoresize" {
  type = bool
  default = false
}
variable "disk_autoresize_limit" {
  type = number
  default = 0
}
variable "database_flags" {
  type = list(object({
    name  = string
    value = string
  }))
  default = []  
} 
variable "backup_configuration" {
  type = list(object({
    enabled                        = bool
    start_time                     = string
    location                       = string
    binary_log_enabled = bool
    point_in_time_recovery_enabled = bool
    backup_retention_settings = list(object({
      retained_backups = number
      retention_unit   = string
    }))
  }))
}
