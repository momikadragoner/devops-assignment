# Cloud Infrastructure Documentation

## 1. Application — Gitea

**[Gitea](https://gitea.io)** is a self-hosted, open-source Git service similar to GitHub.

| Layer | Technology |
|---|---|
| Web Frontend | Gitea web UI (Go + HTML/JS), port 3000 |
| Backend API | Gitea REST API (same binary) |
| Database | PostgreSQL 15 |

Gitea was chosen because:
- It has a clear frontend/database split required by the task.
- The official Docker image supports full configuration via environment variables, making it ideal for PaaS containerised deployment.
- It is small enough to run on B2 App Service tier without cost issues.

---

## 2. Cloud Architecture

```
┌──────────────────────────── Azure Subscription ────────────────────────────────┐
│                                                                                 │
│  Resource Group: rg-gitea-prod-<suffix>                                        │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  Azure Container Registry (acrgitea<suffix>)                            │   │
│  │  Stores custom Gitea Docker images built by the CI/CD pipeline          │   │
│  └───────────────────────────────┬─────────────────────────────────────────┘   │
│                                  │ pull image                                  │
│  ┌───────────────────────────────▼─────────────────────────────────────────┐   │
│  │  App Service Plan (plan-gitea-<suffix>, Linux B2)                       │   │
│  │                                                                          │   │
│  │  App Service / Web App for Containers (app-gitea-<suffix>)              │   │
│  │  - Container: custom Gitea image from ACR                               │   │
│  │  - Port: 3000 (mapped via WEBSITES_PORT)                                │   │
│  │  - Config: GITEA__* environment variables                               │   │
│  │  - Public URL: https://app-gitea-<suffix>.azurewebsites.net             │   │
│  └───────────────────────────────┬─────────────────────────────────────────┘   │
│                                  │ SSL/TLS connection (port 5432)              │
│  ┌───────────────────────────────▼─────────────────────────────────────────┐   │
│  │  Azure Database for PostgreSQL Flexible Server (psql-gitea-<suffix>)    │   │
│  │  - SKU: B_Standard_B1ms (burstable, 32 GB storage)                     │   │
│  │  - Firewall: allow Azure services only (0.0.0.0 → 0.0.0.0)             │   │
│  │  - Database: gitea                                                       │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. IaC Files

| File | Purpose |
|---|---|
| `terraform/main.tf` | All Azure resources: RG, ACR, PostgreSQL, App Service Plan, Web App |
| `terraform/variables.tf` | Input variable declarations with defaults |
| `terraform/outputs.tf` | Post-apply references (ACR URL, App Service name, public URL) |
| `terraform/terraform.tfvars.example` | Example variable values (copy to `terraform.tfvars`) |

---

## 4. Step-by-Step Deployment Guide

### Prerequisites

Install these tools before starting:

```powershell
# Azure CLI
winget install Microsoft.AzureCLI

# OpenTofu (the IaC tool taught in Lab 11)
winget install OpenTofu.OpenTofu

# Docker Desktop (for local testing)
winget install Docker.DockerDesktop
```

---

### Step 1 — Authenticate to Azure

```bash
# Log in to your Azure account (opens browser)
az login

# Verify the correct subscription is selected
az account show --query "{name:name, id:id}" -o table

# If needed, switch to your student subscription
az account set --subscription "Azure for Students"
```

---

### Step 2 — Clone / prepare the repository

```bash
# The assignment files are already in your local repository.
# Navigate to the assignment directory.
cd assignment
```

---

### Step 3 — Set the database password

The password is **never** committed to Git. Export it as an environment variable before running OpenTofu.

```bash
# Linux / macOS
export TF_VAR_db_admin_password="MySecure#Pass1"

# Windows PowerShell
$env:TF_VAR_db_admin_password="MySecure#Pass1"
```

> **Password rules** (Azure PostgreSQL requirement): at least 8 characters, must include uppercase, lowercase, and a digit or special character.

---

### Step 4 — Initialise OpenTofu providers

```bash
cd terraform

# Download the azurerm and random providers
tofu init
```

Expected output:
```
OpenTofu has been successfully initialized!
```

---

### Step 5 — Preview the changes

```bash
tofu plan
```

You should see **6 resources to add**:
- `random_string.suffix`
- `azurerm_resource_group.main`
- `azurerm_container_registry.main`
- `azurerm_postgresql_flexible_server.main`
- `azurerm_postgresql_flexible_server_firewall_rule.allow_azure`
- `azurerm_postgresql_flexible_server_database.gitea`
- `azurerm_service_plan.main`
- `azurerm_linux_web_app.main`

---

### Step 6 — Provision all infrastructure (single command)

```bash
tofu apply -auto-approve
```

This single command provisions the **entire** cloud environment.  
Typical duration: **5–8 minutes**.

At the end, OpenTofu prints the outputs:

```
Outputs:

acr_login_server    = "acrgiteaABCDEF.azurecr.io"
app_service_name    = "app-gitea-ABCDEF"
app_service_url     = "https://app-gitea-ABCDEF.azurewebsites.net"
resource_group_name = "rg-gitea-prod-ABCDEF"
next_steps          = "✅ Infrastructure provisioned! ..."
```

**Save these values** — you will need them for GitHub secrets.

---

### Step 7 — Get the ACR admin password

```bash
# Get the ACR admin username
tofu output -raw acr_admin_username

# Get the ACR admin password from Azure Portal:
# Portal > Container Registries > acrgiteaXXXXXX > Access keys > password
```

Or via CLI:
```bash
az acr credential show --name $(tofu output -raw acr_login_server | cut -d. -f1) \
  --query "passwords[0].value" -o tsv
```

---

### Step 8 — Verify the App Service is running

```bash
# Check the App Service state
az webapp show \
  --name $(tofu output -raw app_service_name) \
  --resource-group $(tofu output -raw resource_group_name) \
  --query "state" -o tsv
# Expected: Running

# Open in browser
start $(tofu output -raw app_service_url)
```

At this point Gitea should be accessible using the public Docker Hub image. The CI/CD pipeline (see next section) will replace it with your custom ACR image.

---

### Step 9 — Tear down (after demo)

```bash
tofu destroy -auto-approve
```

This deletes **all** provisioned resources to avoid ongoing costs.

---

## 5. Deployment Platform Justification

### Azure App Service (PaaS) — chosen

| Criterion | Rationale |
|---|---|
| **Simplicity** | No cluster management — Azure handles OS patching, scaling, and health restarts. |
| **Container support** | "Web App for Containers" runs any Docker image from ACR with zero extra config. |
| **Cost** | B2 App Service Plan (~$30/month) vs AKS which requires at minimum ~$150+/month for a 2-node cluster. |
| **Course alignment** | Directly taught in Labs 06 and 11 (Azure App Service + OpenTofu). |
| **Integrated deployment** | `az webapp config container set` updates the running image in seconds, no orchestrator needed. |

#### Alternatives considered

| Option | Reason not chosen |
|---|---|
| **VM** | Manual OS patching, no built-in health restart, complex app setup. |
| **AKS (Kubernetes)** | Overkill for a single-app deployment; requires Helm, networking config, and more complex CI/CD. |

### Database — Azure Database for PostgreSQL Flexible Server (DBaaS)

| Criterion | Rationale |
|---|---|
| **Managed** | Automatic backups, patching, high-availability option. |
| **Cost** | B_Standard_B1ms burstable SKU is ~$15/month — affordable for a student project. |
| **SSL** | Enforced by default; Gitea connects with `SSL_MODE=require`. |
| **Simplicity** | Firewall rule `0.0.0.0 → 0.0.0.0` allows all Azure services including App Service to connect. |

---

## 6. Security Notes

- DB password is **never** stored in code — passed as `TF_VAR_db_admin_password` and stored as a GitHub secret.
- ACR admin credentials are stored as GitHub secrets, never in YAML files.
- App Service enforces HTTPS (`https_only = true`).
- PostgreSQL only accepts connections from Azure's IP ranges (firewall rule).
