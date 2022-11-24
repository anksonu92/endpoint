terraform {
  required_version = "~> 1.1"
  required_providers {
    azuread = {
      source  = "registry.terraform.io/hashicorp/azuread"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "registry.terraform.io/hashicorp/azurerm"
      version = "~> 3.9"
    }
    random = {
      source  = "registry.terraform.io/hashicorp/random"
      version = "~> 3.0"
    }
    time = {
      source  = "registry.terraform.io/hashicorp/time"
      version = "~> 0.7"
    }
  }
}

provider "azuread" {}

provider "azurerm" {
  skip_provider_registration = false
  storage_use_azuread        = true # prereq to using 'rbac' access model!
  features {}
}

data "azuread_domains" "lens" {
  only_default = true
}

locals {
  ad_users = {
    lens-sqladmin = "mdwadmin"
    lens-analyst  = "testuser"
  }
}

resource "random_integer" "suffix" {
  min = 1
  max = 9999
  keepers = {
    resource_group_name = azurerm_resource_group.lens.name
  }
}

resource "random_password" "ad_users" {
  for_each = local.ad_users

  length  = 24
  special = true
}

resource "azuread_user" "lens" {
  # To create, terraform SPN must be assigned to role `User Administrator` in Azure AD
  for_each = local.ad_users

  user_principal_name = format("%s@%s", each.value, data.azuread_domains.lens.domains[0].domain_name)
  display_name        = each.value
  password            = random_password.ad_users[each.key].result
}

resource "azurerm_key_vault_secret" "ad_users" {
  for_each = local.ad_users

  key_vault_id = module.lens_base.key_vault.id
  name         = each.value
  value        = random_password.ad_users[each.key].result

  depends_on = [module.lens_base.key_vault]
}

resource "azurerm_resource_group" "lens" {
  location = "eastus2"
  name     = "lens-base-test-rbac-users"
}

module "lens_base" {
  source = "git::https://github.com/anksonu92/base.git"

  resource_group_name = azurerm_resource_group.lens.name
  location            = azurerm_resource_group.lens.location

  key_vault = {
    name            = "lens-tf-test-kv1"
    access_model    = "rbac"
    access_policies = {}
    rbac_roles = { for k, v in local.ad_users : k => {
      object_id            = azuread_user.lens[k].object_id
      role_definition_name = "Key Vault Reader"
    } }
  }

  datalake = {
    name                   = format("%s%s", "lens", random_integer.suffix.result)
    tier                   = "Standard"
    replication_type       = "LRS"
    data_retention_in_days = 7
    containers             = ["dropzone", "raw", "stage", "mdw"]
    access_model           = "rbac"
    rbac_roles = { for k, v in local.ad_users : k => {
      object_id            = azuread_user.lens[k].object_id
      role_definition_name = "Storage Blob Data Contributor"
    } }
  }

  depends_on = [
    azurerm_resource_group.lens,
    azuread_user.lens
  ]
}

output "key_vault" {
  value = module.lens_base.key_vault
}

output "datalake" {
  value = module.lens_base.datalake
}

module "lens_vnet" {

  source = "git::https://github.com/anksonu92/vnet1.git"

  //depends_on = [azurerm_resource_group.lens]
  resource_group_name = azurerm_resource_group.lens.name
  location            = azurerm_resource_group.lens.location


}

output "vnet" {
  value = module.lens_vnet.vnet

}

module "prvt_endpoint" {
  source              = "../../"
  resource_group_name = azurerm_resource_group.lens.name
  location            = azurerm_resource_group.lens.location
  depends_on          = [module.lens_vnet, module.lens_base]

  subnet_id                        = module.lens_vnet.vnet.subnet1_id
  private_link_enabled_resource_id = module.lens_base.datalake.id
  subresource_names                = ["blob"]
  private_dns_zone_name            = module.lens_vnet.vnet.dns_name
}