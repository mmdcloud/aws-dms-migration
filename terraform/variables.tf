variable "source_location" {
  type    = string
  default = "us-central1"
}

variable "destination_location" {
  type    = string
  default = "us-east-1"
}

variable "source_db" {
  type    = string
  default = "source-db"
}

variable "destination_db" {
  type    = string
  default = "destinationdb"
}

variable "destination_public_subnets" {
  type        = list(string)
  description = "Public Subnet CIDR values"
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "destination_private_subnets" {
  type        = list(string)
  description = "Private Subnet CIDR values"
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "destination_azs" {
  type        = list(string)
  description = "Availability Zones"
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}