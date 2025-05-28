variable "name" {}
variable "location" {}
variable "private_ip_google_access" {}
variable "subnets" {
  type = list(string)
}
variable "vpc_id" {}