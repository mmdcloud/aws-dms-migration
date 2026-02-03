variable "source_location" {
  type = string
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