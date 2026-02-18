# infra/main.tf - Terraform IaC dla GCP (VPC, GKE) w AutoHealKube
# Użyj: terraform init; terraform apply -var="project_id=your-project"
# Wersja: Terraform 1.7.0+ (2026), GKE 1.35+
# Reusable: Vars z values.yaml (parsuj via Makefile później).

provider "google" {
  project = var.project_id
  region  = var.region
}

# VPC
resource "google_compute_network" "vpc" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.project_name}-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# GKE Cluster (private dla security)
resource "google_container_cluster" "gke" {
  name     = "${var.project_name}-cluster"
  location = "${var.region}-a"
  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  initial_node_count = 1
  min_master_version = var.gke_version  # np. 1.35.1-gke.1
  node_version       = var.gke_version
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  node_config {
    machine_type = "e2-medium"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# IAM (dla GKE access, np. Cloud Shell)
resource "google_project_iam_member" "gke_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "user:your-email@example.com"  # Zmień na swoje (lub service account)
}

# Vars
variable "project_id" {}
variable "region" { default = "us-central1" }
variable "project_name" { default = "autohealkube" }
variable "gke_version" { default = "1.35.1-gke.1" }

# Outputs
output "gke_endpoint" {
  value = google_container_cluster.gke.endpoint
}
output "gke_ca_certificate" {
  value     = google_container_cluster.gke.master_auth.0.cluster_ca_certificate
  sensitive = true
}