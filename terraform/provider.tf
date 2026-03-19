terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.8.1"
    }
  }
  # backend "s3" {
  #   bucket         = "dms-migration-project-bucket"
  #   key            = "dms-migration-project-bucket/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "dms-migration-terraform-state-lock"
  # }
}

# Configure the AWS Provider
provider "aws" {
  region = var.destination_location
}

provider "google" {
  region  = var.source_location
  project = var.gcp_project
}

provider "vault" {}