provider "google" {
  region  = var.region
  credentials = var.credentials
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
