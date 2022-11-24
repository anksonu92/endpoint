variable "resource_group_name" {
  description = "The name of the resource group where modules resources will be deployed. The resource group location will be used for all resources in this module as well."
  type        = string
}

variable "location" {
  description = "The Azure region where the resources will be deployed."
  type        = string
}

variable "subnet_id" {
  description = "The subent id details"
  type        = string
}

variable "private_link_enabled_resource_id" {
  description = "The subent id details"
  type        = string
}


variable "subresource_names" {
  description = "The subent id details"
  type        = list(string) 
}



variable "private_dns_zone_name" {
  description = "The subent id details"
  type        = string
}