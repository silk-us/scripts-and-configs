terraform {
  required_providers {
    silk = {
      source  = "localdomain/provider/silk"
      version = "1.2.2"
    }
  }
}

provider "silk" {
  server = "10.10.10.10"
  username = "admin"
  password = "Password01"
}

provider "azurerm" {
  features {}
}


variable "vmname" {
    type = string
    default = "tfvm01"
}

variable "rgname" {
    type = string
    default = "host-rg"
}

variable "vnetname" {
    type = string
    default = "production-vnet-01"
}

variable "mgmtsnname" {
    type = string
    default = "hosts_mgmt"
}

variable "datasnname" {
    type = string
    default = "hosts_data"
}

variable "location" {
    type = string
    default = "centralus"
}

resource "silk_volume_group" "vg1" {
    name = "${var.vmname}-vg"
    quota_in_gb = 0
    enable_deduplication = false
    description = "Created via TF"
}

resource "silk_volume" "disk1" {
    name = "${var.vmname}-vol1"
    size_in_gb = 2048
    volume_group_name = silk_volume_group.vg1.name
    description = "Created via TF"
    host_mapping = [silk_host.host.name]
    allow_destroy = true
}

resource "silk_volume" "disk2" {
    name = "${var.vmname}-vol2"
    size_in_gb = 4096
    volume_group_name = silk_volume_group.vg1.name
    description = "Created via TF"
    host_mapping = [silk_host.host.name]
    allow_destroy = true
}

resource "silk_host" "host" {
    name = var.vmname
    host_type = "Linux"
    iqn = "iqn.2005-03.org.open-iscsi:${var.vmname}"
}

resource "azurerm_public_ip" "main" {
    name                = "${var.vmname}-pip"
    resource_group_name = var.rgname
    location            = var.location
    allocation_method   = "Static"
    zones               = [1]
    sku                 = "Standard"
}

resource "azurerm_network_interface" "mgmt" {
  name                = "${var.vmname}-mgmt"
  resource_group_name = var.rgname
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = "/subscriptions/8d6bebd5-173e-42dd-afed-53dd32674bd5/resourceGroups/${var.rgname}/providers/Microsoft.Network/virtualNetworks/${var.vnetname}/subnets/${var.mgmtsnname}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.main.id
  }
}

resource "azurerm_network_interface" "data" {
  name                = "${var.vmname}-data1"
  resource_group_name = var.rgname
  location            = var.location
  enable_accelerated_networking = true

  ip_configuration {
    name                          = "internal"
    subnet_id                     = "/subscriptions/8d6bebd5-173e-42dd-afed-53dd32674bd5/resourceGroups/${var.rgname}/providers/Microsoft.Network/virtualNetworks/${var.vnetname}/subnets/${var.datasnname}"
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "main" {
  name                            = var.vmname
  resource_group_name             = var.rgname
  location                        = var.location
  size                            = "Standard_D2s_v3"
  admin_username                  = "kmdemo-azure"
  disable_password_authentication = true
  zone = "1"
  custom_data = filebase64("./bootstrap/bootstrap.sh")

  network_interface_ids = [
    azurerm_network_interface.mgmt.id,
    azurerm_network_interface.data.id,
  ]

  admin_ssh_key {
    username = "kmdemo-azure"
    public_key = file("~/.ssh/kmdemo-azure.pub")
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }
}

