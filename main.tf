resource "random_pet" "rg" {
  keepers = {
    random_name = var.org_id
  }
}
resource "google_project" "project_1" {
  name       = "project-1"
  project_id = random_pet.rg.id
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

resource "google_compute_subnetwork" "bastion-subnet" {
  name                     = "public-subnet"
  ip_cidr_range            = "10.0.2.0/24"
  region                   = var.region
  network                  = google_compute_network.gcp-vpc.self_link
  private_ip_google_access = false
  project = google_project.project_1.project_id

}

resource "google_compute_subnetwork" "private-subnet" {
  name                     = "private-subnet"
  ip_cidr_range            = "10.0.0.0/24"
  region                   = var.region
  network                  = google_compute_network.gcp-vpc.self_link
  private_ip_google_access = true
  project = google_project.project_1.project_id

  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "pod-range"
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

resource "google_compute_router_nat" "nat" {
  name   = "nat"
  router = google_compute_router.router.name
  project = google_project.project_1.project_id
  region = var.region

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  nat_ip_allocate_option             = "MANUAL_ONLY"

  subnetwork {
    name                    = google_compute_subnetwork.private-subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  nat_ips = [google_compute_address.nat.self_link]
}

resource "google_compute_address" "nat" {
  name         = "nat"
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
  project = google_project.project_1.project_id
  depends_on = [google_project_service.proj_services]
}

resource "google_container_cluster" "my_vpc_native_cluster" {
  name               = "my-vpc-native-cluster"
  location           = var.region
  # Make it regional
  node_locations = ["us-east1-b", "us-east1-c", "us-east1-d"]
  network = google_compute_network.gcp-vpc.self_link
  subnetwork = google_compute_subnetwork.private-subnet.self_link
  remove_default_node_pool = true
  initial_node_count       = 1
  project = google_project.project_1.project_id
  # Private cluster 
  private_cluster_config {
    enable_private_endpoint = true
    enable_private_nodes    = true
    master_ipv4_cidr_block  = "10.0.1.0/28"
  }
  
  # Use GKE Standard
  release_channel {
    channel = "REGULAR"
  }

   addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
  }
  
  workload_identity_config {
    workload_pool = "${random_pet.rg.id}.svc.id.goog"
  }
  # IP allocation  
  ip_allocation_policy {
    services_secondary_range_name = google_compute_subnetwork.private-subnet.secondary_ip_range[0].range_name
    cluster_secondary_range_name  = google_compute_subnetwork.private-subnet.secondary_ip_range[1].range_name
  }

   binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }
  master_authorized_networks_config {
  cidr_blocks {
    cidr_block = "${google_compute_instance.bastion.network_interface.0.network_ip}/32"
    display_name = "bastion"
    } 
  }
  

}

resource "google_service_account" "kubernetes" {
  account_id = "kubernetes"
  project = google_project.project_1.project_id
  depends_on = [google_project_service.proj_services]
}


resource "google_container_node_pool" "my_node_pool" {
  name       = "my-node-pool"
  cluster    = google_container_cluster.my_vpc_native_cluster.id
  
  management {
    auto_repair  = true
    auto_upgrade = true
  }
   autoscaling {
    min_node_count = 1
    max_node_count = 10
  }
  node_config {
    machine_type = "e2-small"
    disk_size_gb = 20 
    image_type = "COS_CONTAINERD" # Container-optimized OS 
    service_account = google_service_account.kubernetes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  depends_on = [google_project_service.proj_services]
}


resource "google_compute_instance" "bastion" {
  name         = "bastion"
  machine_type = "f1-micro"
  zone         = var.zone
  project = google_project.project_1.project_id
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.bastion-subnet.self_link

    access_config {
      // Assign public IP
    }
  }

  metadata_startup_script = <<EOF
  sudo apt upgrade
  sudo apt update
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

  sudo apt-get update
  sudo apt-get install apt-transport-https ca-certificates gnupg curl sudo
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.asc] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo tee /usr/share/keyrings/cloud.google.asc
  sudo apt-get update && sudo apt-get install google-cloud-cli
  sudo apt-get install google-cloud-sdk-gke-gcloud-auth-plugin

  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_helm.sh

  gcloud container clusters get-credentials my-vpc-native-cluster --region us-east1 --internal-ip
  EOF
}

resource "google_compute_project_metadata" "my_ssh_key" {
  project = google_project.project_1.project_id
  metadata = {
    ssh-keys = <<EOF
    ${var.ssh_user}:${var.my_ssh_key}
    EOF
  }
}

