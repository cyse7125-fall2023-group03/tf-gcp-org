provider "google" {
  region  = var.region
  credentials = file("/Users/pawan/Documents/AdvCloud/IAMKeys/centering-timer-401021-5925c66ce00b.json")
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
