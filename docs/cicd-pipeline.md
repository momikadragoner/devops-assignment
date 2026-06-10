# CI/CD Pipeline Documentation

## 1. Overview

The pipeline automates the full software delivery lifecycle:

```
Git push to main
      │
      ▼
┌──────────────────┐    ┌──────────────────────┐    ┌─────────────────────────┐
│  Job 1           │───▶│  Job 2               │───▶│  Job 3                  │
│  Lint & Validate │    │  Build & Push to ACR │    │  Deploy to App Service  │
└──────────────────┘    └──────────────────────┘    └─────────────────────────┘
  every push/PR           main branch only              main branch only
```

**Tool:** GitHub Actions  
**File:** [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml)  
**Trigger:** Any push to the `main` branch → automatic build + deploy, no manual steps.

---

## 2. Pipeline Jobs

### Job 1 — Lint & Validate

Runs on **every push and pull request**.

| Step | Tool | What it checks |
|---|---|---|
| Checkout | `actions/checkout` | Gets the source code |
| Dockerfile lint | `hadolint` | Best-practice Dockerfile rules (pinned base image versions, etc.) |
| OpenTofu fmt | `tofu fmt -check` | HCL formatting consistency |
| OpenTofu validate | `tofu validate` | Config syntax and provider schema |

Fast feedback for developers — if this job fails, nothing gets built or deployed.

### Job 2 — Build & Push Image

Runs only on merges to `main` (skipped for PRs).

| Step | What happens |
|---|---|
| ACR login | Authenticates with ACR admin credentials stored as GitHub secrets |
| Image metadata | Generates tags: `sha-<commit>` and `latest` |
| Docker Buildx | Builds the custom Gitea image (with baked-in env defaults and custom template) |
| Push to ACR | Pushes the tagged image to your Azure Container Registry |

The image tag `sha-<commit>` ties every deployed version directly to a Git commit — full traceability.

### Job 3 — Deploy to App Service

Runs only after Job 2 succeeds.

| Step | What happens |
|---|---|
| Azure login | Authenticates using the service principal (`AZURE_CREDENTIALS` secret) |
| `az webapp config container set` | Updates the App Service to pull the newly built image from ACR |
| `az webapp restart` | Restarts the app so Azure pulls and starts the new container |
| Health check | Polls App Service state; fails the job if it's not `Running` within 30 s |
| Print URL | Logs the public Gitea URL for quick verification |

---

## 3. Setting Up the Pipeline (Step by Step)

### Step 1 — Create a GitHub repository

```bash
# In the assignment directory
git init
git add .
git commit -m "Initial commit"

# Create a new GitHub repo (via github.com or CLI) then:
git remote add origin https://github.com/<your-username>/<repo-name>.git
git push -u origin main
```

### Step 2 — Create the Azure service principal

The pipeline needs an Azure identity to deploy. Create it with the Azure CLI:

```bash
# Get your subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Create the service principal with Contributor rights
az ad sp create-for-rbac \
  --name "gitea-cicd-sp" \
  --role contributor \
  --scopes /subscriptions/$SUBSCRIPTION_ID \
  --sdk-auth
```

**Copy the entire JSON output** — you will need it in the next step. It looks like:
```json
{
  "clientId": "xxxxxxxx-...",
  "clientSecret": "xxxxxxxx-...",
  "subscriptionId": "xxxxxxxx-...",
  "tenantId": "xxxxxxxx-...",
  ...
}
```

### Step 3 — Run OpenTofu and collect outputs

```bash
cd terraform
export TF_VAR_db_admin_password="MySecure#Pass1"
tofu apply -auto-approve

# Collect values for GitHub secrets
tofu output acr_login_server
tofu output app_service_name
tofu output resource_group_name

# Get ACR admin credentials
ACR_NAME=$(tofu output -raw acr_login_server | cut -d. -f1)
az acr credential show --name $ACR_NAME --query "{user:username, pass:passwords[0].value}" -o table
```

### Step 4 — Add GitHub repository secrets

Go to your GitHub repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add these secrets one by one:

| Secret name | Value |
|---|---|
| `AZURE_CREDENTIALS` | The full JSON from Step 2 |
| `ACR_LOGIN_SERVER` | e.g. `acrgiteaabcdef.azurecr.io` |
| `ACR_ADMIN_USER` | e.g. `acrgiteaabcdef` |
| `ACR_ADMIN_PASSWORD` | The password from `az acr credential show` |
| `APP_SERVICE_NAME` | e.g. `app-gitea-abcdef` |
| `RESOURCE_GROUP` | e.g. `rg-gitea-prod-abcdef` |

### Step 5 — Trigger the first pipeline run

The pipeline triggers automatically on every push to `main`. Make any small change and push:

```bash
# Make a visible change to prove the pipeline deploys it
echo "# DevOps Assignment" >> README.md
git add README.md
git commit -m "trigger: initial CI/CD pipeline run"
git push origin main
```

### Step 6 — Monitor the pipeline

1. Go to your GitHub repo → **Actions** tab.
2. Click the running workflow named **"Build & Deploy Gitea"**.
3. Watch Job 1 (Lint), then Job 2 (Build), then Job 3 (Deploy) complete in sequence.
4. Once Job 3 finishes, click its logs to find the printed URL.

### Step 7 — Verify the deployment

```bash
# Check App Service is running the new image
az webapp config container show \
  --name <APP_SERVICE_NAME> \
  --resource-group <RESOURCE_GROUP>

# Open Gitea in the browser
start https://<APP_SERVICE_NAME>.azurewebsites.net
```

You should see the Gitea welcome page with the custom title **"ELTE DevOps Gitea"**.

---

## 4. End-to-End Flow Diagram

```
Developer pushes to main
         │
         ▼
GitHub Actions triggers deploy.yml
         │
         ├─ Job 1: Lint & Validate
         │   ├─ hadolint Dockerfile          ✓
         │   ├─ tofu fmt -check              ✓
         │   └─ tofu validate                ✓
         │
         ├─ Job 2: Build & Push  (needs: lint)
         │   ├─ docker login to ACR          ✓
         │   ├─ docker buildx build          ✓  (custom Gitea image)
         │   └─ docker push → ACR            ✓  tag: sha-<commit>
         │
         └─ Job 3: Deploy  (needs: build)
             ├─ az login                     ✓
             ├─ az webapp config container set ✓  new image from ACR
             ├─ az webapp restart            ✓
             ├─ health check (state=Running) ✓
             └─ New Gitea version is live   🚀
```

Any job failure stops the pipeline — a broken commit can never reach production.

---

## 5. Demo Script (Live Demonstration)

Follow these steps during the end-of-semester demo.

### Part A — Show the running application

1. Open `https://app-gitea-<suffix>.azurewebsites.net` in the browser.
2. Point out: **"ELTE DevOps Gitea"** title in the top bar (baked in by our custom image).
3. Create a test user and log in to show the full Gitea UI.

### Part B — Show the IaC provisions everything in one command

```bash
# (If infrastructure was already applied, show the state instead)
tofu show

# Or, if doing a fresh demo, destroy first then re-apply:
tofu destroy -auto-approve
export TF_VAR_db_admin_password="MySecure#Pass1"
tofu apply -auto-approve
```

Point out during apply:
- Resources being created in order
- The final output block with the App Service URL

### Part C — Live CI/CD demo (code change → auto deploy)

1. **Make a visible code change:**

   Open `custom/templates/home.tmpl` and change the subtitle text:
   ```html
   <!-- Change this line -->
   Self-hosted Git service · ELTE MSc DevOps Assignment 2026
   <!-- to something new, e.g. -->
   Self-hosted Git service · Live Demo — May 2026
   ```

2. **Commit and push:**
   ```bash
   git add custom/templates/home.tmpl
   git commit -m "demo: update home page subtitle for live demo"
   git push origin main
   ```

3. **Show the GitHub Actions tab** — the workflow starts within seconds.

4. **Walk through each job** while it runs:
   - Job 1: "Linting the Dockerfile and validating the OpenTofu config"
   - Job 2: "Building the custom Gitea image and pushing to ACR"
   - Job 3: "Updating the App Service to pull the new image and restarting it"

5. **After Job 3 finishes** (~3–4 minutes total), refresh the Gitea home page in the browser.
   - The subtitle now shows **"Live Demo — May 2026"** — proving the code change was automatically deployed.

6. **Show the Azure Portal** (optional):
   - App Service → Deployment Center → shows latest container image tag (`sha-<commit>`)
   - ACR → Repositories → `gitea-custom` → shows all pushed tags

### Part D — Answer expected questions

| Question | Answer |
|---|---|
| Why App Service and not a VM? | App Service is PaaS — no OS management, built-in health restarts, and direct container support. Cost-effective for a single app. |
| Why PostgreSQL Flexible Server? | It's a fully-managed DBaaS. No VM to patch, automatic backups, and SSL enforced by default. |
| Why OpenTofu? | OpenTofu is the open-source fork of Terraform with identical HCL syntax — the tool taught in Lab 11. |
| How does the pipeline ensure no manual steps? | Every merge to `main` triggers the workflow. The `deploy` job uses `az webapp config container set` to update the image without human intervention. |
| What happens if a deployment fails? | Job 3 includes a health check step that fails the workflow if App Service is not in `Running` state, leaving the previous version active. |
| How are secrets managed? | Passwords never appear in code. They are stored as GitHub Actions secrets and injected at runtime. |

---

## 6. Rollback Procedure

If a bad image is deployed:

```bash
# Find the previous good image tag in ACR
az acr repository show-tags --name <ACR_NAME> --repository gitea-custom --output table

# Roll back to a specific commit's image
az webapp config container set \
  --name <APP_SERVICE_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --container-image-name <ACR_LOGIN_SERVER>/gitea-custom:sha-<previous-good-commit>

az webapp restart --name <APP_SERVICE_NAME> --resource-group <RESOURCE_GROUP>
```
