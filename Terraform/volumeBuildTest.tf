terraform {
  required_providers {
    silk = {
      source  = "localdomain/provider/silk"
      version = "1.1.0"
    }
  }
}

provider "silk" {
  server = "10.10.10.10"
  username = "admin"
  password = "password"
}

variable "vmname" {
    type = string
    default = "apitest"
}

resource "silk_volume_group" "Silk-Volume-Group" {
    name = "${var.vmname}-vg"
    quota_in_gb = 0
    enable_deduplication = false
    description = "Created via TF"
}

resource "silk_volume" "Silk-Volume1" {
    name = "${var.vmname}-vol1"
    size_in_gb = 30
    volume_group_name = silk_volume_group.Silk-Volume-Group.name
    description = "Build with TF"
    host_mapping = [silk_host.Silk-Host.name]
    allow_destroy = true
}

resource "silk_volume" "Silk-Volume2" {
    name = "${var.vmname}-vol2"
    size_in_gb = 30
    volume_group_name = silk_volume_group.Silk-Volume-Group.name
    description = "Build with TF"
    host_mapping = [silk_host.Silk-Host.name]
    allow_destroy = true
}

resource "silk_volume" "Silk-Volume3" {
    name = "${var.vmname}-vol3"
    size_in_gb = 30
    volume_group_name = silk_volume_group.Silk-Volume-Group.name
    description = "Build with TF"
    host_mapping = [silk_host.Silk-Host.name]
    allow_destroy = true
}

resource "silk_volume" "Silk-Volume4" {
    name = "${var.vmname}-vol4"
    size_in_gb = 30
    volume_group_name = silk_volume_group.Silk-Volume-Group.name
    description = "Build with TF"
    host_mapping = [silk_host.Silk-Host.name]
    allow_destroy = true
}

resource "silk_volume" "Silk-Volume5" {
    name = "${var.vmname}-vol5"
    size_in_gb = 30
    volume_group_name = silk_volume_group.Silk-Volume-Group.name
    description = "Build with TF"
    host_mapping = [silk_host.Silk-Host.name]
    allow_destroy = true
}

resource "silk_volume" "Silk-Volume6" {
    name = "${var.vmname}-vol6"
    size_in_gb = 30
    volume_group_name = silk_volume_group.Silk-Volume-Group.name
    description = "Build with TF"
    host_mapping = [silk_host.Silk-Host.name]
    allow_destroy = true
}

resource "silk_volume" "Silk-Volume7" {
    name = "${var.vmname}-vol7"
    size_in_gb = 30
    volume_group_name = silk_volume_group.Silk-Volume-Group.name
    description = "Build with TF"
    host_mapping = [silk_host.Silk-Host.name]
    allow_destroy = true
}

resource "silk_volume" "Silk-Volume8" {
    name = "${var.vmname}-vol8"
    size_in_gb = 30
    volume_group_name = silk_volume_group.Silk-Volume-Group.name
    description = "Build with TF"
    host_mapping = [silk_host.Silk-Host.name]
    allow_destroy = true
}

resource "silk_volume" "Silk-Volume9" {
    name = "${var.vmname}-vol9"
    size_in_gb = 30
    volume_group_name = silk_volume_group.Silk-Volume-Group.name
    description = "Build with TF"
    host_mapping = [silk_host.Silk-Host.name]
    allow_destroy = true
}

resource "silk_volume" "Silk-Volume10" {
    name = "${var.vmname}-vol10"
    size_in_gb = 30
    volume_group_name = silk_volume_group.Silk-Volume-Group.name
    description = "Build with TF"
    host_mapping = [silk_host.Silk-Host.name]
    allow_destroy = true
}

resource "silk_host" "Silk-Host" {
    name = var.vmname
    host_type = "Linux"
    # iqn = "${var.iqnprefix}${var.vmname}"
}
