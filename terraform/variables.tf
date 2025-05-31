variable "source_location" {
  type    = string
  default = "us-central1"
}

variable "destination_location" {
  type    = string
  default = "us-east-1"
}

variable "source_public_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "source_private_subnets" {
  type    = list(string)
  default = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}