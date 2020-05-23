variable "project_id" {
  default = ""
}

variable "my_ip" {
  default = ""
}

provider "google" {
  project = var.project_id
  region  = "us-central1"
}

resource "google_compute_network" "vpc_network" {
  name                    = "demo-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "subnet01"
  ip_cidr_range = "10.0.0.0/24"
  network       = google_compute_network.vpc_network.self_link
}

resource "google_compute_instance" "vm_instance" {
  count        = 3
  name         = "web0${count.index}"
  machine_type = "g1-small"
  tags         = ["allow-ssh-http"]
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-9"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.subnet.self_link
    access_config {}
  }
  metadata_startup_script = data.template_file.startup_script.rendered
  service_account {
    email  = google_service_account.instance_sa.email
    scopes = ["cloud-platform"]
  }
  allow_stopping_for_update = true
}

data "template_file" "startup_script" {
  template = file("${path.module}/startup-script.tpl")
  vars = {
    db_bucket = google_storage_bucket.db_bucket.name
    db_name   = "employees"
    db_user   = "root"
    db_pass   = "pass_${random_id.pass.hex}"
  }
}

resource "google_service_account" "instance_sa" {
  account_id = "web-sa"
}

resource "google_project_iam_member" "creator" {
  member = "serviceAccount:${google_service_account.instance_sa.email}"
  role   = "roles/storage.objectAdmin"
}

resource "google_project_iam_member" "sql_viewer" {
  member = "serviceAccount:${google_service_account.instance_sa.email}"
  role   = "roles/cloudsql.viewer"
}

resource "google_compute_firewall" "http_allow" {
  name          = "allow-http"
  network       = google_compute_network.vpc_network.self_link
  source_ranges = [google_compute_forwarding_rule.fr.ip_address, var.my_ip ]
  target_tags   = ["allow-ssh-http"]
  allow {
    protocol = "tcp"
    ports    = ["22","80"]
  }
}

resource "random_id" "pass" {
  byte_length = 6
}

resource "google_sql_database_instance" "lamp_instance" {
  region           = "us-central1"
  database_version = "MYSQL_5_7"
  settings {
    tier = "db-g1-small"
    ip_configuration {
      dynamic "authorized_networks" {
        for_each = google_compute_instance.vm_instance
        iterator = apps
        content {
          name  = apps.value.name
          value = apps.value.network_interface.0.access_config.0.nat_ip
        }
      }
    }
  }
}

# Create Cloud SQL user
resource "google_sql_user" "users" {
  name     = "root"
  instance = google_sql_database_instance.lamp_instance.name
  host     = "%"
  password = "pass_${random_id.pass.hex}"
}

# Create Cloud SQL database
resource "google_sql_database" "employees_db" {
  name     = "employees"
  instance = google_sql_database_instance.lamp_instance.name
}

//# Create GCS DB Dump bucket
resource "google_storage_bucket_object" "db_dump" {
  bucket = google_storage_bucket.db_bucket.name
  name   = "employees.sql"
  source = "${path.module}/employees.sql"
}

resource "google_storage_bucket" "db_bucket" {
  name          = "db-bucket-mw-demo-556771"
  storage_class = "NEARLINE"
}

resource "google_compute_forwarding_rule" "fr" {
  load_balancing_scheme = "EXTERNAL"
  name                  = "web-forwarding-rule"
  target                = google_compute_target_pool.tp.self_link
  port_range            = 80
  network_tier = "STANDARD"
}

resource "google_compute_target_pool" "tp" {
  name          = "web-nodes-pool"
  instances     = google_compute_instance.vm_instance[*].self_link
  health_checks = [google_compute_http_health_check.web_hc.name]
}

resource "google_compute_http_health_check" "web_hc" {
  name                = "web-check"
  request_path        = "/"
  check_interval_sec  = 10
  timeout_sec         = 3
  unhealthy_threshold = 3
  healthy_threshold   = 2
  port                = 80
}

output "url" {
  value = "http://${google_compute_forwarding_rule.fr.ip_address}/index.php"
}