terraform {
  required_providers {
    silk = {
      source  = "localdomain/provider/silk"
      version = "1.0.9"
    }
  }
}

provider "silk" {
  server = "10.10.10.10"
  username = "admin"
  password = "password"
}

provider "azurerm" {
  features {}
}

variable "subscriptionId" {
    type = string
    default = "1234ebd5-123e-12dd-123d-53dd12345678"
}

variable "vmName" {
    type = string
    default = "terraformVM"
}

variable "rgName" {
    type = string
    default = "SG-RG02"
}

variable "vnetName" {
    type = string
    default = "shared-vnet"
}

variable "mgmtSubnet" {
    type = string
    default = "hosts_mgmt"
}

variable "dataSubnet" {
    type = string
    default = "hosts_data"
}

variable "location" {
    type = string
    default = "eastus"
}

resource "silk_volume_group" "Silk-Volume-Group" {
    name = "${var.vmName}-vg"
    quota_in_gb = 0
    enable_deduplication = false
    description = "Created via TF"
}

resource "silk_volume" "Silk-Volume" {
    name = "${var.vmName}-125"
    size_in_gb = 125
    volume_group_name = silk_volume_group.Silk-Volume-Group.name
    description = "Build with TF"
    host_mapping = [silk_host.Silk-Host.name]
    allow_destroy = true
}

resource "silk_volume" "Silk-Volume2" {
    name = "${var.vmName}-128"
    size_in_gb = 128
    volume_group_name = silk_volume_group.Silk-Volume-Group.name
    description = "Build with TF"
    host_mapping = [silk_host.Silk-Host.name]
    allow_destroy = true
}

resource "silk_volume" "Silk-Volume3" {
    name = "${var.vmName}-5tb"
    size_in_gb = 5120
    volume_group_name = silk_volume_group.Silk-Volume-Group.name
    description = "Build with TF"
    host_mapping = [silk_host.Silk-Host.name]
    allow_destroy = true
}

resource "silk_host" "Silk-Host" {
    name = var.vmName
    host_type = "Linux"
    iqn = "iqn.2005-03.org.open-iscsi:${var.vmName}"
}

resource "azurerm_public_ip" "main" {
    name                = "${var.vmName}-pip"
    resource_group_name = var.rgName
    location            = var.location
    allocation_method   = "Static"
}

resource "azurerm_network_interface" "mgmt" {
  name                = "${var.vmName}-mgmt"
  resource_group_name = var.rgName
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = "/subscriptions/${subscriptionId}/resourceGroups/${var.rgName}/providers/Microsoft.Network/virtualNetworks/${var.vnetName}/subnets/${var.mgmtSubnet}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.main.id
  }
}

resource "azurerm_network_interface" "data" {
  name                = "${var.vmName}-data1"
  resource_group_name = var.rgName
  location            = var.location
  enable_accelerated_networking = true

  ip_configuration {
    name                          = "internal"
    subnet_id                     = "/subscriptions/${subscriptionId}/resourceGroups/${var.rgName}/providers/Microsoft.Network/virtualNetworks/${var.vnetName}/subnets/${var.dataSubnet}"
    private_ip_address_allocation = "Dynamic"
  }
}

data "template_file" "bootstrap_file" {
  template = file("./bootstrap/bootstrap.sh")
}

resource "azurerm_linux_virtual_machine" "main" {
  name                            = var.vmName
  resource_group_name             = var.rgName
  location                        = var.location
  size                            = "Standard_M192is_v2"
  admin_username                  = "adminKey"
  disable_password_authentication = true
  custom_data = base64encode(data.template_file.bootstrap_file.rendered)

  network_interface_ids = [
    azurerm_network_interface.mgmt.id,
    azurerm_network_interface.data.id,
  ]

  admin_ssh_key {
    username = "adminKey"
    public_key = file("~/.ssh/adminKey.pub")
  }

  source_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "82gen2"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }
}

