## Demo Plan

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

## Alignment with Cloud-Native Principles

| Principle | How this assignment addresses it |
|---|---|
| **Infrastructure as Code** | All Azure resources defined in HCL; zero manual Portal clicks needed after initial setup. |
| **Immutable infrastructure** | Each deployment creates a new, tagged Docker image. Old versions are never patched in place. |
| **Automated delivery** | Every `git push` to `main` triggers a fully automated build → test → deploy chain. |
| **Separation of concerns** | Application (App Service), data (PostgreSQL DBaaS), and image storage (ACR) are independent services. |
| **Secrets management** | Database passwords and ACR credentials are never committed to Git and are injected only at runtime. |
| **Observability** | Azure App Service provides built-in logging (docker.log, startup logs) viewable via `az webapp log`. |
