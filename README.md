# Gitea on Azure App Service - DevOps Assignment

## Application

**[Gitea](https://gitea.io)** self-hosted, open-source Git service (like GitHub) with a full web frontend and a PostgreSQL backend database.


---

## Repository Structure

```
assignment/
├── .github/
│   └── workflows/
│       └── deploy.yml              # GitHub Actions CI/CD pipeline (Lab 12)
├── custom/
│   └── templates/
│       └── home.tmpl               # Custom Gitea home page (baked into Docker image)
├── docs/
│   ├── infrastructure.md           # IaC documentation + step-by-step deployment guide
│   └── cicd-pipeline.md            # CI/CD documentation + live demo script
├── terraform/
│   ├── main.tf                     # All Azure resources (RG, ACR, PostgreSQL, App Service)
│   ├── variables.tf                # Input variables
│   ├── outputs.tf                  # Post-apply references and next-steps helper
│   ├── terraform.tfvars.example    # Example values (copy to terraform.tfvars)
│   └── .gitignore                  # Excludes state files and tfvars from Git
├── Dockerfile                      # Custom Gitea image (bakes in org defaults)
└── README.md
```

---

## Architecture at a Glance

```
GitHub → GitHub Actions CI/CD
             │  build & push
             ▼
Azure Container Registry (ACR)
             │  pull image
             ▼
Azure App Service (Web App for Containers)   ←→   Azure PostgreSQL Flexible Server
  https://app-gitea-<suffix>.azurewebsites.net         (DBaaS, SSL enforced)
```

All resources are provisioned by a **single OpenTofu command** — aligned with Lab 11.

---

## Quick Start

### 1 — Provision all cloud infrastructure

```bash
cd terraform

# Set DB password (never commit this)
export TF_VAR_db_admin_password="MySecure#Pass1"

tofu init           # download providers
tofu plan           # preview changes
tofu apply          # provision everything (~5 min)
```

### 2 — Connect GitHub Actions

Add these secrets in GitHub → Settings → Secrets → Actions:

| Secret | Source |
|---|---|
| `AZURE_CREDENTIALS` | `az ad sp create-for-rbac --sdk-auth` |
| `ACR_LOGIN_SERVER` | `tofu output acr_login_server` |
| `ACR_ADMIN_USER` | `tofu output -raw acr_admin_username` |
| `ACR_ADMIN_PASSWORD` | Azure Portal → ACR → Access keys |
| `APP_SERVICE_NAME` | `tofu output app_service_name` |
| `RESOURCE_GROUP` | `tofu output resource_group_name` |

### 3 — Trigger the CI/CD pipeline

```bash
git add .
git commit -m "initial deployment"
git push origin main
# GitHub Actions: Lint → Build → Deploy  (automatic, ~4 min)
```

### 4 — Access Gitea

```bash
# URL is printed by tofu apply and by the CI/CD pipeline
https://app-gitea-<suffix>.azurewebsites.net
```

---

## Documentation

| Document | Contents |
|---|---|
| [docs/infrastructure.md](docs/infrastructure.md) | Architecture diagram, IaC files, full 9-step deployment guide, platform justification |
| [docs/cicd-pipeline.md](docs/cicd-pipeline.md) | Pipeline stages, 7-step setup guide, live demo script, Q&A for the exam |

---

## Tear Down

```bash
tofu destroy -auto-approve
```
