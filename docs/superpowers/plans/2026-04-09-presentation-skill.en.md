# Presentation Skill Implementation Plan

> [English](2026-04-09-presentation-skill.en.md) | [简体中文](2026-04-09-presentation-skill.md)
>
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a Claude Code skill to deploy local frontend SPA projects to a dedicated preview server with one click, returning a publicly accessible HTTPS URL.

**Architecture:** Local SKILL.md guides Claude to execute build and upload, while server-side deploy-preview.sh script handles Nginx configuration and SSL certificate issuance. config.md stores server configuration, DEPLOYMENTS.md records deployment history.

**Tech Stack:** Claude Code Skill (SKILL.md markdown), Bash shell script, Nginx, acme.sh, SCP/SSH

---

## File Structure

```
~/.claude/skills/presentation/
├── SKILL.md                  # Skill definition: trigger conditions, execution flow, init flow
├── config.md                 # Server configuration template (user fills + auto-detection during init)
├── DEPLOYMENTS.md            # Deployment history (empty template)
└── scripts/
    └── deploy-preview.sh     # Server-side deployment script (SCP to server during init)
```

---

### Task 1: Create Directory Structure and config.md

**Files:**
- Create: `~/.claude/skills/presentation/config.md`

- [ ] **Step 1: Create skill directory structure**

```bash
mkdir -p ~/.claude/skills/presentation/scripts
```

- [ ] **Step 2: Create config.md configuration template**

Create `~/.claude/skills/presentation/config.md` with the following content:

```markdown
---
name: presentation-config
description: Presentation Skill server configuration file, auto-filled with detected values during init
---

# Presentation Skill Configuration

## Preview Server

- IP:
- SSH User: root
- SSH Port: 22

## Domain

- base_domain:

## Server Paths

- deploy_base_dir: /opt/presentation
- web_root: /var/www/previews
- nginx_conf_dir: /etc/nginx/conf.d/previews

## Nginx (auto-detected and filled during init)

- nginx_bin:
- nginx_reload_cmd:
- nginx_include_ok: false

## SSL

- cert_tool: acme.sh
- acme_sh_path:

## Build Detection (local)

- Priority: Check if Makefile has deploy target
- Otherwise: Follow standard build → deploy flow
```

Note: All values are empty and need to be filled by running `/presentation init` or manually filling IP and base_domain before init.

- [ ] **Step 3: Verify file creation**

```bash
ls -la ~/.claude/skills/presentation/config.md
```

Expected: File exists

- [ ] **Step 4: Commit**

```bash
cd ~/.claude/skills/presentation
git init
git add config.md
git commit -m "feat: add presentation skill config template"
```

Note: If `~/.claude/` is not a git repo, skip git operations and only verify file creation was successful.

---

### Task 2: Create DEPLOYMENTS.md Deployment History Template

**Files:**
- Create: `~/.claude/skills/presentation/DEPLOYMENTS.md`

- [ ] **Step 1: Create DEPLOYMENTS.md**

Create `~/.claude/skills/presentation/DEPLOYMENTS.md` with the following content:

```markdown
# Deployment History

| Project Name | Subdomain | URL | Last Deployed | Status |
|--------------|-----------|-----|--------------|--------|
```

This is an empty table that will be appended with new rows by the flow in SKILL.md on each deployment.

- [ ] **Step 2: Verify file creation**

```bash
ls -la ~/.claude/skills/presentation/DEPLOYMENTS.md
```

Expected: File exists

- [ ] **Step 3: Commit**

```bash
git add DEPLOYMENTS.md
git commit -m "feat: add deployment history template"
```

---

### Task 3: Create deploy-preview.sh Server-side Deployment Script

**Files:**
- Create: `~/.claude/skills/presentation/scripts/deploy-preview.sh`

This is the most critical component that runs on the preview server and handles Nginx configuration and SSL certificates.

- [ ] **Step 1: Create deploy-preview.sh**

Create `~/.claude/skills/presentation/scripts/deploy-preview.sh` with the following content:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ============================================
# Presentation Skill - Server-side Deployment Script
# Purpose: Configure Nginx virtual host + acme.sh SSL certificate issuance
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

# Load server-side configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo '{"status":"error","message":"config.env not found at '"${CONFIG_FILE}"'. Run /presentation init first."}'
    exit 1
fi

source "$CONFIG_FILE"

# Parameter validation
PROJECT_NAME="${1:-}"
SUBDOMAIN="${2:-}"
BASE_DOMAIN="${3:-}"

if [[ -z "$PROJECT_NAME" || -z "$SUBDOMAIN" || -z "$BASE_DOMAIN" ]]; then
    echo '{"status":"error","message":"Usage: deploy-preview.sh <project-name> <subdomain> <base-domain>"}'
    exit 1
fi

DOMAIN="${SUBDOMAIN}.${BASE_DOMAIN}"
SITE_DIR="${WEB_ROOT}/${PROJECT_NAME}"
CONF_FILE="${NGINX_CONF_DIR}/${SUBDOMAIN}.conf"
LOG_DIR="${SCRIPT_DIR}/logs"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_DIR}/deploy.log"
}

# ============================================
# Step 1: Create site directory
# ============================================
mkdir -p "$SITE_DIR"
log "Site directory ready: ${SITE_DIR}"

# ============================================
# Step 2: Generate HTTP version of Nginx config
# ============================================
mkdir -p "$NGINX_CONF_DIR"

cat > "$CONF_FILE" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root ${SITE_DIR};
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    access_log /var/log/nginx/${SUBDOMAIN}.access.log;
    error_log /var/log/nginx/${SUBDOMAIN}.error.log;
}
EOF

log "HTTP config written: ${CONF_FILE}"

# ============================================
# Step 3: Test and reload Nginx
# ============================================
if ! ${NGINX_BIN} -t 2>&1; then
    rm -f "$CONF_FILE"
    echo '{"status":"error","message":"nginx -t failed. Config removed."}'
    exit 1
fi

${NGINX_RELOAD_CMD}
log "Nginx reloaded with HTTP config"

# ============================================
# Step 4: Issue SSL certificate
# ============================================
SSL_SUCCESS=false
CERT_DIR=""

if [[ -x "${ACME_SH_PATH}" ]]; then
    log "Issuing SSL cert for ${DOMAIN}..."

    if ${ACME_SH_PATH} --issue -d "$DOMAIN" --nginx 2>&1 | tee -a "${LOG_DIR}/deploy.log"; then
        SSL_SUCCESS=true
        # acme.sh default certificate installation path
        CERT_DIR="/root/.acme.sh/${DOMAIN}_ecc"
        if [[ ! -d "$CERT_DIR" ]]; then
            CERT_DIR="${HOME}/.acme.sh/${DOMAIN}_ecc"
        fi

        # Install certificate to Nginx
        ${ACME_SH_PATH} --install-cert -d "$DOMAIN" \
            --key-file "${CERT_DIR}/${DOMAIN}.key" \
            --fullchain-file "${CERT_DIR}/fullchain.cer" \
            --reloadcmd "${NGINX_RELOAD_CMD}" 2>&1 | tee -a "${LOG_DIR}/deploy.log" || true
    else
        log "SSL issue failed, keeping HTTP-only config"
    fi
else
    log "acme.sh not found at ${ACME_SH_PATH}, skipping SSL"
fi

# ============================================
# Step 5: Update Nginx config to include SSL
# ============================================
if [[ "$SSL_SUCCESS" == "true" && -d "$CERT_DIR" ]]; then
    CERT_FILE="${CERT_DIR}/fullchain.cer"
    KEY_FILE="${CERT_DIR}/${DOMAIN}.key"

    if [[ -f "$CERT_FILE" && -f "$KEY_FILE" ]]; then
        cat > "$CONF_FILE" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    root ${SITE_DIR};
    index index.html;

    ssl_certificate ${CERT_FILE};
    ssl_certificate_key ${KEY_FILE};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    access_log /var/log/nginx/${SUBDOMAIN}.access.log;
    error_log /var/log/nginx/${SUBDOMAIN}.error.log;
}
EOF

        if ${NGINX_BIN} -t 2>&1; then
            ${NGINX_RELOAD_CMD}
            log "Nginx reloaded with HTTPS config"
            echo "{\"status\":\"success\",\"url\":\"https://${DOMAIN}\"}"
        else
            log "nginx -t failed after SSL config, reverting to HTTP"
            rm -f "$CONF_FILE"
            ${NGINX_RELOAD_CMD}
            echo '{"status":"error","message":"nginx -t failed after adding SSL. Reverted to no config."}'
            exit 1
        fi
    else
        log "Cert files not found, keeping HTTP-only"
        echo "{\"status\":\"success\",\"url\":\"http://${DOMAIN}\",\"warning\":\"SSL cert files not found, HTTP only\"}"
    fi
else
    echo "{\"status\":\"success\",\"url\":\"http://${DOMAIN}\",\"warning\":\"SSL not configured\"}"
fi

log "Deploy complete for ${DOMAIN}"
```

- [ ] **Step 2: Set script executable permission**

```bash
chmod +x ~/.claude/skills/presentation/scripts/deploy-preview.sh
```

- [ ] **Step 3: Verify script with shellcheck (if installed)**

```bash
shellcheck ~/.claude/skills/presentation/scripts/deploy-preview.sh || echo "shellcheck not installed, skipping"
```

Expected: No errors, or skip if shellcheck is not installed

- [ ] **Step 4: Commit**

```bash
git add scripts/deploy-preview.sh
git commit -m "feat: add server-side deploy script with Nginx + acme.sh"
```

---

### Task 4: Create SKILL.md Main File

**Files:**
- Create: `~/.claude/skills/presentation/SKILL.md`

This is the entry file for the skill that Claude reads to understand how to execute deployments.

- [ ] **Step 1: Create SKILL.md**

Create `~/.claude/skills/presentation/SKILL.md` with the following content:

```markdown
---
name: presentation
description: Deploy frontend SPA projects to preview server with one click. Use when user says "deploy it", "deploy", or "publish preview". Supports /presentation command trigger.
---

# Presentation Skill - Frontend Project Preview Deployment

Build and deploy the current directory's frontend SPA project to a preview server, returning a publicly accessible URL.

## Prerequisites

- Preview server has Nginx configured
- Wildcard domain `*.<base_domain>` is resolved to the preview server
- `/presentation init` has been run to complete initialization (or config.md filled manually)

## Configuration File

Configuration is stored in `config.md` in the same directory as the SKILL.

This directory: `~/.claude/skills/presentation/`

## Command Format

- `/presentation` - Deploy current project to preview server
- `/presentation init` - Initialize preview server (first time use)
- "deploy it" / "deploy" / "publish preview" / "deploy to preview server" - Natural language trigger

## Makefile Routing Rules

**Important:** When user says "deploy", first check if current directory has Makefile with deploy-related target.

- **Has Makefile deploy target** → Execute `make deploy`, skip this skill flow
- **No Makefile or no deploy target** → Continue with flow below

## Initialization Flow (`/presentation init`)

Execute on first-time use:

1. **Collect basic information** - If IP or base_domain in config.md is empty, use AskUserQuestion to ask user:
   - Preview server IP address
   - Base domain (e.g., preview.example.com)
   - SSH username (default: root)
   - SSH port (default: 22)

2. **Auto-detect server environment** - Execute via SSH:
   ```bash
   # Detect Nginx
   which nginx
   nginx -t 2>&1
   nginx -V 2>&1 | grep "configure arguments"

   # Detect acme.sh
   which acme.sh || ls ~/.acme.sh/acme.sh 2>/dev/null

   # Detect disk space
   df -h /var/www
   ```

3. **Create server-side directory structure** - Via SSH:
   ```bash
   mkdir -p /opt/presentation/logs
   mkdir -p /opt/presentation/scripts
   mkdir -p /var/www/previews
   mkdir -p /etc/nginx/conf.d/previews
   ```

4. **Upload deployment script** - Use SCP:
   ```bash
   scp ~/.claude/skills/presentation/scripts/deploy-preview.sh <user>@<ip>:/opt/presentation/
   ```

5. **Generate server-side config.env** - Write via SSH:
   ```bash
   cat > /opt/presentation/config.env << 'ENVEOF'
   WEB_ROOT=/var/www/previews
   NGINX_CONF_DIR=/etc/nginx/conf.d/previews
   NGINX_BIN=<detected_path>
   NGINX_RELOAD_CMD=<detected_command>
   ACME_SH_PATH=<detected_path>
   ENVEOF
   ```

6. **Ensure Nginx includes previews directory** - Check if nginx.conf has:
   ```
   include /etc/nginx/conf.d/previews/*.conf;
   ```
   If not, prompt user to manually add this line to the http block of nginx.conf.

7. **Verify** - Execute `nginx -t` to confirm configuration is correct.

8. **Update config.md** - Write detected values back to config.md, mark `nginx_include_ok: true`.

9. **Inform user** - Output initialization completion message, listing detected configuration.

## Deployment Flow

When user triggers deployment (non-init), execute following steps:

### Step 1: Read Configuration

Read `~/.claude/skills/presentation/config.md`, get:
- Server IP, SSH User, SSH Port
- base_domain
- deploy_base_dir, web_root

If key fields (IP, base_domain) are empty, prompt user to run `/presentation init` first.

### Step 2: Detect Project Information

Read current directory's `package.json`:
- `name` field as project name (fallback to directory name)
- `scripts.build` field as build command

If `package.json` doesn't exist, prompt:
> Current directory is not a frontend project (package.json not found), cannot deploy.

### Step 3: Determine Subdomain

Rules:
1. User specified subdomain in message → Use user-specified
2. Otherwise use package.json `name` field
3. Otherwise use current directory name
4. Convert to lowercase, replace non-alphanumeric characters with `-`

### Step 4: Local Build

**Package manager detection:**
- `pnpm-lock.yaml` exists → `pnpm install && pnpm build`
- `yarn.lock` exists → `yarn install && yarn build`
- Otherwise → `npm install && npm run build`

If build fails (non-zero exit code), show error logs, interrupt flow, do not continue deployment.

### Step 5: Verify Build Output

Check `dist/` or `build/` directory:
- Exists and not empty → Continue
- Doesn't exist or empty → Prompt "Build output is empty, please check build configuration", interrupt flow

### Step 6: Upload to Server

First ensure target directory exists via SSH, then use SCP to upload build output:

```bash
ssh -p <port> <user>@<ip> "mkdir -p <web_root>/<project-name>"
scp -r -P <port> ./dist/* <user>@<ip>:<web_root>/<project-name>/
```

If upload fails, prompt to check server connection.

### Step 7: Execute Server-side Deployment Script

Execute via SSH:

```bash
ssh -p <port> <user>@<ip> "bash <deploy_base_dir>/deploy-preview.sh <project-name> <subdomain> <base-domain>"
```

Parse script output (JSON format):
- `{"status":"success","url":"https://..."}` → Deployment successful
- `{"status":"error","message":"..."}` → Deployment failed, show error message

### Step 8: Update Deployment Record

Append a row to the end of the table in `~/.claude/skills/presentation/DEPLOYMENTS.md`:

```markdown
| <project-name> | <subdomain> | https://<subdomain>.<base_domain> | <YYYY-MM-DD HH:mm> | ✅ |
```

If deployment failed, put ❌ in status column.

### Step 9: Return Result to User

**Success:**
```
✅ Deployment successful!

Project: <project-name>
URL: https://<subdomain>.<base_domain>

Deployment record updated.
```

**Failed:**
```
❌ Deployment failed

Project: <project-name>
Error: <error message>

Please check logs above, fix issues, and retry.
```

### Step 10: Generate Makefile deploy target

**Only execute on successful deployment.** Generate or append Makefile `deploy` target in user project root directory for easy `make deploy` redeployment.

**Logic:**

1. Check if project root directory has `Makefile`
2. If Makefile exists and has `deploy` target (check with `grep` for `^deploy`) → **Skip**, don't override user's custom deployment flow
3. If no Makefile → Create new file
4. If exists but no deploy target → Append

**Generated target template (using actual parameters from this deployment):**

```makefile
# Auto-generated by presentation skill
# Can run make deploy directly for redeployment later

.PHONY: deploy

deploy:
	{pkg_install_and_build}
	scp -r -P {ssh_port} ./{build_dir}/* {ssh_user}@{server_ip}:{web_root}/{project_name}/
	ssh -p {ssh_port} {ssh_user}@{server_ip} "bash {deploy_base_dir}/deploy-preview.sh {project_name} {subdomain} {base_domain}"
```

**Variable sources:**

| Variable | Source |
|----------|--------|
| pkg_install_and_build | Result from Step 4 detection, e.g., `pnpm install && pnpm build` |
| build_dir | Result from Step 5 detection, `dist` or `build` |
| ssh_port / ssh_user / server_ip | config.md |
| web_root / deploy_base_dir | config.md |
| project_name / subdomain / base_domain | Results from Step 2, 3 |

**Example generated result:**

```makefile
.PHONY: deploy

deploy:
	pnpm install && pnpm build
	scp -r -P 22 ./dist/* root@203.0.113.10:/var/www/previews/my-app/
	ssh -p 22 root@203.0.113.10 "bash /opt/presentation/deploy-preview.sh my-app my-app preview.example.com"
```

**Operation commands:**

```bash
# Check if deploy target already exists
if grep -q '^deploy' Makefile 2>/dev/null; then
    echo "Makefile already has deploy target, skipping"
else
    # Append to existing Makefile or create new file
    cat >> Makefile << 'MAKEFILE_EOF'
# Auto-generated by presentation skill
# Can run make deploy directly for redeployment later

.PHONY: deploy

deploy:
	pnpm install && pnpm build
	scp -r -P 22 ./dist/* root@203.0.113.10:/var/www/previews/my-app/
	ssh -p 22 root@203.0.113.10 "bash /opt/presentation/deploy-preview.sh my-app my-app preview.example.com"
MAKEFILE_EOF
fi
```

After generation, prompt user:
> Makefile deploy target generated in project root directory, can run `make deploy` directly for redeployment later.

## Error Handling

| Scenario | Handling |
|----------|----------|
| config.md not initialized | Prompt "Please run /presentation init to initialize preview server first" |
| package.json doesn't exist | Prompt "Current directory is not a frontend project, cannot deploy" |
| Build failed | Show error logs, interrupt |
| Build output empty | Prompt to check build configuration, interrupt |
| SCP upload failed | Prompt to check server connection |
| SSL issuance failed | Script automatically falls back to HTTP, prompt about certificate issues |

## Notes

- Each deployment will overwrite old files for the same project on server (idempotent)
- Redeploying with same subdomain will overwrite Nginx configuration
- SSL certificates are auto-renewed by acme.sh, no manual handling needed
- Script execution logs are saved on server at `/opt/presentation/logs/deploy.log`
- Makefile deploy target is only generated on first deployment, won't override existing
```

- [ ] **Step 2: Verify file creation**

```bash
ls -la ~/.claude/skills/presentation/SKILL.md
```

Expected: File exists and size > 0

- [ ] **Step 3: Verify complete directory structure**

```bash
find ~/.claude/skills/presentation -type f
```

Expected output:
```
~/.claude/skills/presentation/SKILL.md
~/.claude/skills/presentation/config.md
~/.claude/skills/presentation/DEPLOYMENTS.md
~/.claude/skills/presentation/scripts/deploy-preview.sh
```

- [ ] **Step 4: Commit**

```bash
git add SKILL.md
git commit -m "feat: add presentation skill main definition"
```

---

### Task 5: Integration Verification

Verify if the skill can be correctly recognized by Claude Code.

- [ ] **Step 1: Check SKILL.md frontmatter format**

Confirm SKILL.md starts with correct YAML frontmatter:
```
---
name: presentation
description: ...
---
```

- [ ] **Step 2: Check deploy-preview.sh syntax**

```bash
bash -n ~/.claude/skills/presentation/scripts/deploy-preview.sh
```

Expected: No output (syntax correct)

- [ ] **Step 3: List complete file list for verification**

```bash
echo "=== Presentation Skill File List ==="
echo ""
echo "SKILL.md:"
head -3 ~/.claude/skills/presentation/SKILL.md
echo ""
echo "config.md:"
head -5 ~/.claude/skills/presentation/config.md
echo ""
echo "DEPLOYMENTS.md:"
cat ~/.claude/skills/presentation/DEPLOYMENTS.md
echo ""
echo "deploy-preview.sh:"
head -3 ~/.claude/skills/presentation/scripts/deploy-preview.sh
echo ""
echo "=== All Files ==="
find ~/.claude/skills/presentation -type f -exec ls -la {} \;
```

Expected: All 4 files exist with correct content

- [ ] **Step 4: Final Commit**

```bash
git add -A
git commit -m "feat: presentation skill complete - one-click SPA preview deployment"
```

---

## Spec Coverage Checklist

| Spec Requirement | Task |
|------------------|------|
| SKILL.md trigger conditions (/presentation, natural language) | Task 4 |
| config.md configuration template | Task 1 |
| DEPLOYMENTS.md deployment history | Task 2 |
| deploy-preview.sh server-side script | Task 3 |
| Nginx config generation (HTTP → SSL) | Task 3 |
| acme.sh certificate issuance | Task 3 |
| config.env server-side config reading | Task 3 |
| Idempotency (redeployment overwrites) | Task 3 |
| /presentation init initialization flow | Task 4 (defined in SKILL.md) |
| Makefile routing rules | Task 4 (defined in SKILL.md) |
| Package manager detection (pnpm/yarn/npm) | Task 4 (defined in SKILL.md) |
| Subdomain generation rules | Task 4 (defined in SKILL.md) |
| Error handling (all scenarios) | Task 3 + Task 4 |