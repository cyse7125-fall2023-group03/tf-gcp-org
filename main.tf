resource "google_project" "project_1" {
  name       = "project-1"
  project_id = var.project_id
  org_id     = var.org_id

  billing_account = var.billing_account
  depends_on = [google_project_service.billing]
}


resource "google_project_service" "billing" {
  service = "cloudbilling.googleapis.com"
  project = var.default_project_id
  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
}

resource "google_project_service" "proj_services" {
  service  = each.value
  for_each = toset(var.api_service_list)
  project = google_project.project_1.project_id
  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
}


resource "time_sleep" "wait_compute" {
  depends_on = [google_project_service.proj_services]
  
  create_duration = var.sleep_time
  destroy_duration = var.sleep_time
}

resource "time_sleep" "wait_billing" {
  depends_on = [google_project_service.billing]
  
  create_duration = var.sleep_time
  destroy_duration = var.sleep_time
}
resource "google_compute_network" "gcp-vpc" {
  name                    = "gcp-vpc"
  project = google_project.project_1.project_id
  auto_create_subnetworks = false
  depends_on = [google_project_service.proj_services]
}

resource "google_compute_subnetwork" "public-subnet" {
  name                     = "public-subnet"
  ip_cidr_range            = "10.0.0.0/24"
  region                   = var.region
  network                  = google_compute_network.gcp-vpc.self_link
  private_ip_google_access = false
  project = google_project.project_1.project_id

  secondary_ip_range {
    range_name    = "first-range"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "second-range"
    ip_cidr_range = "10.2.0.0/20"
  }

}

resource "google_compute_firewall" "allow-ssh" {
  name          = "allow-ssh"
  network       = google_compute_network.gcp-vpc.name
  project = google_project.project_1.project_id
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_router" "router" {
  name    = "router"
  region  = var.region
  network = google_compute_network.gcp-vpc.self_link
  project = google_project.project_1.project_id
}

resource "google_compute_instance" "gcp_instance" {
  name         = "gcp-instance"
  machine_type = "e2-micro"
  zone         = var.zone
  tags         = ["ssh"]
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }
  project = google_project.project_1.project_id


  network_interface {
    subnetwork_project = google_project.project_1.project_id
    network    = google_compute_network.gcp-vpc.name
    subnetwork = google_compute_subnetwork.public-subnet.name
  }

  depends_on = [
    google_compute_network.gcp-vpc,
  ]
}