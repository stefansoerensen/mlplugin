---
name: jenkins-pipeline
description: Jenkins CI/CD pipeline setup via cicd-service API — creating jobs, Gitea webhooks, and triggering builds
user-invocable: false
---

# Jenkins Pipeline Setup (via cicd-service)

All Jenkins pipeline management goes through the **cicd-service API** at:
- Internal: `http://cicd-service:8000/api/`
- Via nginx: `https://tasktool.medialine.com/api/cicd/`

The cicd-service API has **no auth** on its own endpoints. It stores encrypted Jenkins credentials internally.

## Full Setup Process for a New Project

### Step 1: Ensure a Jenkins Server is Registered

```bash
# List existing servers
curl -sk https://tasktool.medialine.com/api/cicd/servers

# If none exist, register the Jenkins server (one-time):
curl -sk -X POST https://tasktool.medialine.com/api/cicd/servers \
  -H "Content-Type: application/json" \
  -d '{
    "name": "jenkins-prod",
    "display_name": "Production Jenkins",
    "url": "http://jenkins:8080",
    "environment": "prod",
    "auth_type": "token",
    "auth_user": "admin",
    "auth_token": "<jenkins-api-token>"
  }'
```

Save the returned `id` — this is the `jenkins_server_id` for pipelines.

### Step 2: Create a Pipeline Record

```bash
curl -sk -X POST https://tasktool.medialine.com/api/cicd/pipelines \
  -H "Content-Type: application/json" \
  -d '{
    "target_type": "app",
    "target_slug": "<project-slug>",
    "jenkins_server_id": "<jenkins-server-uuid>",
    "job_name": "<project-slug>",
    "jenkinsfile_path": "Jenkinsfile",
    "branch_pattern": "*",
    "is_multibranch": false,
    "auto_trigger_on_push": true
  }'
```

Notes:
- `target_type`: `"app"` for applications, `"service"` for infrastructure/shared
- `job_name`: becomes the Jenkins job name (use project slug)
- `is_multibranch`: `false` for standard Pipeline from SCM

### Step 3: Provision the Jenkins Job

This creates the actual job in Jenkins via its API:

```bash
curl -sk -X POST https://tasktool.medialine.com/api/cicd/pipelines/<pipeline-id>/provision-job \
  -H "Content-Type: application/json" \
  -d '{
    "repo_url": "http://gitea:3000/medialine/<project-slug>.git",
    "branch": "main"
  }'
```

This generates Pipeline XML config and creates the job via Jenkins `/createItem` API.

**Important:** The `repo_url` must use the **internal Docker hostname** (`gitea:3000`), not the public URL, because Jenkins runs on the same Docker network.

### Step 4: Create Gitea Webhook

Set up a webhook so pushes trigger Jenkins builds:

```bash
curl -sk -X POST "https://gitea.medialine.com/api/v1/repos/medialine/<project-slug>/hooks" \
  -u "admin:<gitea-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "gitea",
    "active": true,
    "config": {
      "url": "http://jenkins:8080/generic-webhook-trigger/invoke?token=<project-slug>",
      "content_type": "json",
      "secret": ""
    },
    "events": ["push"],
    "branch_filter": "main"
  }'
```

Alternative: Use Jenkins Generic Webhook Trigger plugin URL or Gitea plugin URL depending on Jenkins configuration.

### Step 5: Trigger a Test Build

```bash
# List pipelines to get the pipeline ID
curl -sk https://tasktool.medialine.com/api/cicd/pipelines

# Trigger build
curl -sk -X POST https://tasktool.medialine.com/api/cicd/pipelines/<pipeline-id>/trigger \
  -H "Content-Type: application/json" \
  -d '{
    "branch": "main",
    "triggered_by": "manual"
  }'
```

## Checking Existing Pipelines

```bash
# List all pipelines
curl -sk https://tasktool.medialine.com/api/cicd/pipelines | python3 -m json.tool

# List all servers
curl -sk https://tasktool.medialine.com/api/cicd/servers | python3 -m json.tool

# Get builds for a pipeline
curl -sk https://tasktool.medialine.com/api/cicd/pipelines/<pipeline-id>/builds | python3 -m json.tool
```

## Jenkinsfile Conventions

Every project MUST have a `Jenkinsfile` at the repo root. See the integrator agent for the standard template. Key stages:

1. **Checkout** — `checkout scm`
2. **Build** — Docker image build (backend + frontend)
3. **Test** — Run tests inside containers
4. **Push** — Push to local registry (`localhost:5000`)
5. **Deploy** — Copy compose file to server, `docker compose up -d`

For **infrastructure/shared repos** (no Docker build):
1. **Checkout** — `checkout scm`
2. **Pull on Server** — `git fetch + checkout -f` to deploy path
3. **Reload** — Restart affected services
