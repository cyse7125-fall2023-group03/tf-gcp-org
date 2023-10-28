provider "google" {
  region  = var.region
  credentials = var.service_account_credentials
  zone = var.zone
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">=4.0, <5.0"
    }
  }
}
