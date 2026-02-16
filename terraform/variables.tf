variable "source_location" {
  type = string
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.source_location))
    error_message = "Must be a valid GCP region (e.g., us-central1)"
  }
}

variable "destination_location" {
  type = string
}

variable "source_db" {
  type = string
}

variable "destination_db" {
  type = string
}

variable "destination_public_subnets" {
  type        = list(string)
  description = "Public Subnet CIDR values"
}

variable "destination_private_subnets" {
  type        = list(string)
  description = "Private Subnet CIDR values"
}

variable "destination_database_subnets" {
  type        = list(string)
  description = "Private Subnet CIDR values"
}

variable "destination_azs" {
  type        = list(string)
  description = "Availability Zones"
}

variable "notification_email" {
  type        = list(string)
  description = "Notification Email"
}

variable "dms_engine_version" {
  type        = list(string)
  description = "DMS Engine Version"
}
