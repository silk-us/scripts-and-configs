terraform {
  required_providers {
    silk = {
      source  = "localdomain/provider/silk"
      version = "1.2.5"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.99.0"
    }
  }
}

