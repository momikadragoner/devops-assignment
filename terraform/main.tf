###############################################################################
# main.tf — Gitea on Azure App Service + Azure Database for PostgreSQL
#
# Simplified architecture aligned with the course labs:
#   - Lab 04-optional : ACR + App Service with container images
#   - Lab 06          : Azure App Service (PaaS) deployment
#   - Lab 11          : OpenTofu IaC on Azure
#
# Provision everything with a single command:
#   tofu apply
###############################################################################

terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

###############################################################################
# Random suffix — ensures globally unique resource names
###############################################################################
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  suffix = random_string.suffix.result
  tags = {
    Project     = "gitea-devops"
    Environment = var.environment
    ManagedBy   = "opentofu"
  }
}

###############################################################################
# Resource Group
###############################################################################
resource "azurerm_resource_group" "main" {
  name     = "rg-gitea-${var.environment}-${local.suffix}"
  location = var.location
  tags     = local.tags
}

###############################################################################
# Azure Container Registry (ACR)
# admin_enabled = true so App Service can authenticate with username/password.
###############################################################################
resource "azurerm_container_registry" "main" {
  name                = "acrgitea${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
  tags                = local.tags
}

###############################################################################
# Azure Database for PostgreSQL — Flexible Server (DBaaS)
# Uses public access with Azure-services firewall rule (simplest setup).
###############################################################################
resource "azurerm_postgresql_flexible_server" "main" {
  name                         = "psql-gitea-${local.suffix}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "15"
  administrator_login          = var.db_admin_user
  administrator_password       = var.db_admin_password
  zone                         = "1"
  storage_mb                   = 32768
  sku_name                     = "B_Standard_B1ms"
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  tags                         = local.tags
}

# Allow all Azure-internal services to reach the DB (required by App Service)
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  name             = "allow-azure-services"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_postgresql_flexible_server_database" "gitea" {
  name      = "gitea"
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}

###############################################################################
# App Service Plan — Linux, B2 tier (required for always-on containers)
###############################################################################
resource "azurerm_service_plan" "main" {
  name                = "plan-gitea-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "B2"
  tags                = local.tags
}

###############################################################################
# App Service — Web App for Containers
#
# On first apply we point to the public Docker Hub image of Gitea.
# The CI/CD pipeline will later push a custom image to ACR and update
# the container settings — no chicken-and-egg bootstrap problem.
###############################################################################
resource "azurerm_linux_web_app" "main" {
  name                = "app-gitea-${local.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true
  tags                = local.tags

  site_config {
    always_on = true
    application_stack {
      # Public Docker Hub image — works immediately without seeding ACR first.
      # The CI pipeline will overwrite this with the ACR image on first deploy.
      docker_image_name   = "gitea/gitea:${var.gitea_image_tag}"
      docker_registry_url = "https://index.docker.io"
    }
  }

  # Gitea is configured entirely via GITEA__section__key environment variables.
  app_settings = {
    "GITEA__database__DB_TYPE"  = "postgres"
    "GITEA__database__HOST"     = "${azurerm_postgresql_flexible_server.main.fqdn}:5432"
    "GITEA__database__NAME"     = azurerm_postgresql_flexible_server_database.gitea.name
    "GITEA__database__USER"     = var.db_admin_user
    "GITEA__database__PASSWD"   = var.db_admin_password
    "GITEA__database__SSL_MODE" = "require"
    "GITEA__server__HTTP_PORT"  = "3000"
    "GITEA__server__ROOT_URL"   = "https://app-gitea-${local.suffix}.azurewebsites.net/"
    "GITEA__server__APP_NAME"   = "ELTE DevOps Gitea"
    # Tell App Service which port the container listens on
    "WEBSITES_PORT" = "3000"
  }

  depends_on = [
    azurerm_postgresql_flexible_server_database.gitea,
    azurerm_postgresql_flexible_server_firewall_rule.allow_azure,
  ]
}
