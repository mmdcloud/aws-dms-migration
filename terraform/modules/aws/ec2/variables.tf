variable "name"{}
variable "ami"{}
variable "instance_type"{}
variable "associate_public_ip_address"{}
variable "key_name"{
    type = string
    default = ""
}
variable "subnet_id"{}
variable "security_groups"{}
variable "user_data"{}
variable "iam_instance_profile"{
    type = string
    default = ""
}