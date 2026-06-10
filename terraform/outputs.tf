###############################################################################
# outputs.tf — Key values to copy after `tofu apply`
###############################################################################

output "resource_group_name" {
  description = "Name of the resource group (needed for GitHub secrets)."
  value       = azurerm_resource_group.main.name
}

output "acr_login_server" {
  description = "ACR login server URL (needed for GitHub secrets and docker push)."
  value       = azurerm_container_registry.main.login_server
}

output "acr_admin_username" {
  description = "ACR admin username (needed for GitHub secrets)."
  value       = azurerm_container_registry.main.admin_username
  sensitive   = true
}

output "app_service_name" {
  description = "App Service name (needed for GitHub secrets and az webapp commands)."
  value       = azurerm_linux_web_app.main.name
}

output "app_service_url" {
  description = "Public URL of the Gitea instance."
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "postgres_fqdn" {
  description = "FQDN of the PostgreSQL Flexible Server."
  value       = azurerm_postgresql_flexible_server.main.fqdn
  sensitive   = true
}

output "next_steps" {
  description = "What to do after apply."
  value       = <<-EOT
    ✅ Infrastructure provisioned!

    1. Copy the outputs above into your GitHub repository secrets:
         ACR_LOGIN_SERVER  → ${azurerm_container_registry.main.login_server}
         ACR_ADMIN_USER    → (run: tofu output -raw acr_admin_username)
         ACR_ADMIN_PASSWORD → (Azure Portal > ACR > Access keys)
         APP_SERVICE_NAME  → ${azurerm_linux_web_app.main.name}
         RESOURCE_GROUP    → ${azurerm_resource_group.main.name}

    2. Push a commit to the main branch to trigger the CI/CD pipeline.

    3. Once the pipeline finishes, visit:
         ${azurerm_linux_web_app.main.default_hostname}
  EOT
}
