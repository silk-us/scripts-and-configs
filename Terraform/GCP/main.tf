terraform {
  required_providers {
    silk = {
      source  = "localdomain/provider/silk"
      version = "1.0.9"
    }
  }
}

provider "google" {
    project = "gcp-project"
    region  = "us-east4"
    zone    = "us-east4-a"
}

provider "silk" {
  server = "10.10.10.10"
  username = "admin"
  password = "password"
}

variable "region" {
    type = string
    default = "us-east4"
}

variable "zone" {
    type = string
    default = "us-east4-a"
}

variable "vm-name" {
    type = string
    default = "terraformVM"
}

data "template_file" "default" {
  template = file("./bootstrap/bootstrap.sh")
}

resource "google_compute_instance" "default" {
    name = "${var.vm-name}"
    machine_type = "e2-highcpu-16"
    zone         = var.zone
    allow_stopping_for_update = true
    metadata_startup_script = data.template_file.default.rendered

    boot_disk {
        initialize_params {
            image = "ubuntu-2004-focal-v20210720"
            type = "pd-ssd"
            size = 100 
        }
    }

    network_interface {
        network = "flex-cluster-${var.clusterid}-network-external-mgmt"
        subnetwork = google_compute_subnetwork.hosts-mgmt.name
        access_config {}
    }
    
    network_interface {
        network = "flex-cluster-${var.clusterid}-network-external-data1"
        subnetwork = google_compute_subnetwork.hosts-data.name
    }
}

resource "silk_volume" "Silk-Volume" {
    name = "${var.vm-name}-vd1"
    size_in_gb = 200
    volume_group_name = silk_volume_group.Silk-Volume-Group.name
    description = "Build with TF"
    host_mapping = [silk_host.Silk-Host.name]
    allow_destroy = true
}


resource "silk_volume_group" "Silk-Volume-Group" {
    name = "${var.vm-name}-vg"
    quota_in_gb = 0
    enable_deduplication = false
    description = "Created via TF"
}

resource "silk_host" "Silk-Host" {
    name = "${var.vm-name}"
    host_type = "Linux"
    iqn = "iqn.2005-03.org.open-iscsi:${var.vm-name}"
}
