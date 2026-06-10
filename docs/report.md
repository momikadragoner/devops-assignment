# DevOps Assignment — Cloud Infrastructure & CI/CD Report

**Student:** *(fill in your name)*  
**Date:** June 2026  
**GitHub Repository:** https://github.com/momikadragoner/devops-assignment  
**Live Application:** https://app-gitea-i138vq.azurewebsites.net

---

## 1. Application Selection

### What is Gitea?

[Gitea](https://gitea.io) is a self-hosted, open-source Git service that provides the same core functionality as GitHub: code repositories, pull requests, issue tracking, user management, and a full web UI. It is written in Go and distributed as a single binary or Docker image.

Gitea was chosen because:
- It is **not** in the example list (eShopOnWeb, Pet Store, Online Boutique, Sock Shop).
- It has a clear **web frontend** (Go + HTML/JS served on port 3000) and a **backend database** (PostgreSQL), satisfying the architectural requirement.
- It is 100% open-source and publicly available, requiring no licence.
- Its Docker image supports complete configuration via environment variables, making it ideal for cloud-native PaaS deployment.

### Architecture Analysis

After cloning and analysing the repository, Gitea's architecture is:

| Layer | Technology | Role |
|---|---|---|
| Web Frontend | Go (HTML/CSS/JS templates, rendered server-side) | User interface — browse repos, manage users, view PRs |
| Backend API | Go (same binary as the frontend) | REST API, Git operations (HTTP/SSH), authentication |
| Database | PostgreSQL (primary), also supports MySQL/SQLite | Stores users, repositories metadata, issues, settings |
| File Storage | Local filesystem (or object storage) | Stores actual Git objects (blobs, trees, commits) |

For this deployment, the **filesystem storage** is provided by the App Service's ephemeral container storage, which is acceptable for a demo environment. In production, Azure Blob Storage or a persistent volume would be used.

### Deployment Needs

| Need | Requirement |
|---|---|
| HTTP port | Container must expose port 3000 |
| Database | PostgreSQL 15+ with SSL |
| Environment config | All settings injected via `GITEA__section__key` env vars |
| Persistence | App data at `/data` (ephemeral in this demo) |

---

## 2. Cloud Infrastructure (IaC)

### Platform: Microsoft Azure

The Azure for Students subscription was used, which restricts deployable regions to a subset of Azure locations. The region `switzerlandnorth` was selected as it is confirmed to work with the student subscription.

### IaC Tool: OpenTofu

[OpenTofu](https://opentofu.org) is the open-source fork of Terraform with identical HCL syntax, taught in Lab 11 of this course. All infrastructure is defined in HCL files under `terraform/` and provisioned with a single command:

```bash
tofu apply
```

### Provisioned Resources

The following Azure resources are provisioned by `terraform/main.tf`:

| Resource | Azure Type | Purpose |
|---|---|---|
| Resource Group `rg-gitea-prod-i138vq` | `azurerm_resource_group` | Logical container for all resources |
| Container Registry `acrgiteai138vq` | `azurerm_container_registry` | Stores the custom Gitea Docker images built by CI/CD |
| PostgreSQL Server `psql-gitea-i138vq` | `azurerm_postgresql_flexible_server` | Managed database (DBaaS) — stores all Gitea data |
| PostgreSQL Database `gitea` | `azurerm_postgresql_flexible_server_database` | The specific database Gitea connects to |
| App Service Plan `plan-gitea-i138vq` | `azurerm_service_plan` | Linux B2 compute tier for the web app |
| App Service `app-gitea-i138vq` | `azurerm_linux_web_app` | Runs the Gitea Docker container; public-facing URL |

A `random_string` resource generates a 6-character suffix for all names, guaranteeing global uniqueness without manual configuration.

### Architecture Diagram

```
Developer's Laptop
       │  git push
       ▼
GitHub Repository (momikadragoner/devops-assignment)
       │  webhook trigger
       ▼
GitHub Actions Runner (ubuntu-latest)
       │  docker build + push
       ▼
Azure Container Registry (acrgiteai138vq.azurecr.io)
       │  pull image on deploy
       ▼
Azure App Service — Web App for Containers (app-gitea-i138vq)
  URL: https://app-gitea-i138vq.azurewebsites.net
       │  SSL/TLS on port 5432
       ▼
Azure Database for PostgreSQL — Flexible Server (psql-gitea-i138vq)
  FQDN: psql-gitea-i138vq.postgres.database.azure.com
```

### Key IaC Design Decisions

**Random suffix for uniqueness**

```hcl
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}
```

ACR names and App Service names must be globally unique in Azure. Rather than requiring the user to pick a name manually, a random suffix is generated and applied to all resources consistently.

**Gitea configured entirely via environment variables**

```hcl
app_settings = {
  "GITEA__database__DB_TYPE"  = "postgres"
  "GITEA__database__HOST"     = "${azurerm_postgresql_flexible_server.main.fqdn}:5432"
  ...
}
```

Gitea reads the `GITEA__section__key` environment variable pattern to configure every aspect of its behaviour. This avoids baking secrets into the Docker image and allows the same image to run in different environments with different settings.

**Sensitive values never committed to Git**

The database password is passed via an environment variable (`TF_VAR_db_admin_password`), not written into any file. OpenTofu marks it as `sensitive = true` so it is never printed in plan/apply output.

---

## 3. Deployment Platform Justification

### Chosen: Azure App Service (PaaS)

| Criterion | Rationale |
|---|---|
| **No server management** | Azure handles OS patching, host reboots, and health restarts automatically. |
| **Native container support** | "Web App for Containers" runs any Docker image from ACR with zero Kubernetes knowledge required. |
| **Deployment simplicity** | Updating the running app is a single `az webapp config container set` call — no cluster, no Helm, no manifests. |
| **Cost** | Linux B2 App Service Plan ≈ €25/month vs AKS minimum ≈ €100+/month for a demo. |
| **Course alignment** | Directly taught in Lab 06 (App Service) and Lab 11 (OpenTofu for App Service). |

### Alternatives Considered

| Option | Why not chosen |
|---|---|
| **VM (IaaS)** | Requires manual OS management, installing dependencies, and configuring systemd — significantly more work with no benefit for a single app. |
| **AKS (Kubernetes)** | Provides horizontal scaling and self-healing, but requires Helm charts, networking config, Ingress controllers, and RBAC — far exceeds the complexity needed for one application. |

### Chosen: Azure Database for PostgreSQL — Flexible Server (DBaaS)

| Criterion | Rationale |
|---|---|
| **Fully managed** | Automated daily backups, point-in-time restore, and automatic minor version upgrades. |
| **SSL enforced** | Azure PostgreSQL Flexible Server requires TLS by default; Gitea connects with `SSL_MODE=require`. |
| **Cost** | Burstable B_Standard_B1ms SKU ≈ €12/month — the most affordable managed PostgreSQL option on Azure. |
| **No VM maintenance** | No need to patch the database OS, manage storage volumes, or configure replication manually. |

---

## 4. CI/CD Pipeline

### Tool: GitHub Actions

GitHub Actions was chosen because:
- It is natively integrated with GitHub — no external CI service needed.
- It is taught in Lab 12 of this course.
- It supports reusable Docker actions from the Docker organisation (`docker/login-action`, `docker/build-push-action`, etc.).

### Pipeline File

`.github/workflows/deploy.yml`  
**Trigger:** Every push to the `main` branch (and pull requests for linting only).

### Pipeline Stages

```
Git push to main
      │
      ▼
┌────────────────────┐    ┌───────────────────────┐    ┌─────────────────────────┐
│  Job 1             │───▶│  Job 2                │───▶│  Job 3                  │
│  Lint & Validate   │    │  Build & Push to ACR  │    │  Deploy to App Service  │
└────────────────────┘    └───────────────────────┘    └─────────────────────────┘
  every push / PR           main branch only              main branch only
  ~1 min                    ~3 min                         ~1 min
```

### Job 1 — Lint & Validate

| Step | Tool | What is checked |
|---|---|---|
| Dockerfile lint | `hadolint/hadolint-action` | Best-practice Dockerfile rules (pinned base versions, etc.) |
| Format check | `tofu fmt -check` | HCL code formatting consistency |
| Validate | `tofu validate` | OpenTofu config syntax and provider schema correctness |

This job runs on **every push and every pull request**. If it fails, nothing is built or deployed, giving fast feedback before code is merged.

### Job 2 — Build & Push Image

| Step | What happens |
|---|---|
| `docker/login-action` | Authenticates the runner to ACR using admin credentials |
| `docker/metadata-action` | Generates image tags: `sha-<7char>` (traceability) and `latest` (convenience) |
| `docker/setup-buildx-action` | Enables layer caching via GitHub Actions cache (speeds up subsequent builds) |
| `docker/build-push-action` | Builds the Dockerfile from the repository root and pushes both tags to ACR |

The short SHA (7 characters from `git rev-parse --short HEAD`) is captured as a job output and passed to Job 3. This ensures the exact same tag that was pushed is used for deployment — a tag mismatch would cause App Service to fail to pull the image.

### Job 3 — Deploy to App Service

| Step | What happens |
|---|---|
| `azure/login` | Authenticates with a service principal (`AZURE_CREDENTIALS` secret) |
| `az webapp config container set` | Updates App Service to pull `gitea-custom:sha-<short>` from ACR |
| `az webapp restart` | Restarts the app so the new image is pulled and started |
| Health check | Polls `az webapp show --query state`; fails the job if not `Running` after 30 s |

### How automatic deployment is guaranteed

- The `on: push: branches: [main]` trigger means **every merge to `main` fires the pipeline**.
- Job 3 only runs if Jobs 1 and 2 both succeed (`needs: build`).
- There are **zero manual steps** between a `git push` and the new version running in Azure.
- A failed pipeline leaves the **previous version running** — App Service only switches to the new image after a successful pull and start.

### Secret Management

No credentials appear in any file in the repository. All sensitive values are stored as **GitHub repository secrets** and injected at pipeline runtime:

| Secret | Value source |
|---|---|
| `AZURE_CREDENTIALS` | `az ad sp create-for-rbac --sdk-auth` |
| `ACR_LOGIN_SERVER` | `tofu output acr_login_server` |
| `ACR_ADMIN_USER` | `tofu output -raw acr_admin_username` |
| `ACR_ADMIN_PASSWORD` | Azure Portal → ACR → Access keys |
| `APP_SERVICE_NAME` | `tofu output app_service_name` |
| `RESOURCE_GROUP` | `tofu output resource_group_name` |

---

## 5. Custom Docker Image

The assignment does not simply re-use the official Gitea image. A custom image is built and stored in ACR to demonstrate the CI/CD build artefact:

```dockerfile
ARG GITEA_VERSION=1.22
FROM gitea/gitea:${GITEA_VERSION}

# Bake in organisational defaults (overridable at runtime via App Service env vars)
ENV GITEA__server__APP_NAME="ELTE DevOps Gitea" \
    GITEA__ui__DEFAULT_THEME="gitea-auto" \
    GITEA__log__LEVEL="Info"

# Copy a custom home page template (visible change to demonstrate CI/CD)
COPY custom/templates/home.tmpl /data/gitea/templates/home.tmpl

EXPOSE 3000
```

The `COPY` instruction bakes `custom/templates/home.tmpl` into the image layer at build time. When Gitea starts, it finds this file at `/data/gitea/templates/home.tmpl` and renders it instead of the built-in home page. This is the **visible change** used in the live demo: editing the subtitle text, pushing to `main`, and seeing the change appear on the live site after the pipeline completes (~4 minutes).

---

## 6. Demo Plan

### Part A — Show the running application

1. Open https://app-gitea-i138vq.azurewebsites.net
2. Point out the custom title **"ELTE DevOps Gitea"** and the custom subtitle — these are baked into the Docker image.
3. Create a test user and log in to show the full Gitea UI (repositories, issue tracker, etc.).

### Part B — IaC provisions everything in one command

```bash
cd assignment/terraform
export TF_VAR_db_admin_password="..."
tofu apply          # provisions all 7 resources in ~6 minutes
```

Walk through the output as resources are created. Show the final output block printing the App Service URL.

### Part C — Live CI/CD demo

1. Edit `custom/templates/home.tmpl` — change the subtitle to something new.
2. `git add . && git commit -m "demo: update subtitle" && git push origin main`
3. Show the **GitHub Actions** tab — the three-job pipeline starts within seconds.
4. Walk through each job while it runs.
5. After Job 3 finishes, refresh the Gitea home page — the new subtitle appears.

### Part D — Defend design choices

| Expected question | Answer summary |
|---|---|
| Why App Service and not a VM? | PaaS eliminates OS management; built-in health restarts; integrated ACR pull. |
| Why PostgreSQL Flexible Server? | Fully managed DBaaS; automatic backups; SSL enforced by default. |
| Why OpenTofu not Terraform? | OpenTofu is the course tool (Lab 11) and is binary-compatible with Terraform HCL. |
| How does the pipeline ensure no manual steps? | `on: push: branches: [main]` triggers automatically; `az webapp restart` applies the new image without human intervention. |
| What happens if a deploy fails? | Job 3 health-checks the app state; on failure the workflow is marked red and the previous image stays running. |
| How are secrets protected? | No credentials in code — all stored as GitHub Actions repository secrets, injected at runtime only. |

---

## 7. Alignment with Cloud-Native Principles

| Principle | How this assignment addresses it |
|---|---|
| **Infrastructure as Code** | All Azure resources defined in HCL; zero manual Portal clicks needed after initial setup. |
| **Immutable infrastructure** | Each deployment creates a new, tagged Docker image. Old versions are never patched in place. |
| **Automated delivery** | Every `git push` to `main` triggers a fully automated build → test → deploy chain. |
| **Separation of concerns** | Application (App Service), data (PostgreSQL DBaaS), and image storage (ACR) are independent services. |
| **Secrets management** | Database passwords and ACR credentials are never committed to Git and are injected only at runtime. |
| **Observability** | Azure App Service provides built-in logging (docker.log, startup logs) viewable via `az webapp log`. |
