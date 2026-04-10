# Presentation Skill - Design Document

> Date: 2026-04-09
> Status: Confirmed
>
> English | [简体中文](2026-04-09-presentation-skill-design.md)

## Overview

Presentation is a Claude Code skill for one-click deployment of local frontend SPA projects to a dedicated preview server, generating publicly accessible HTTPS preview URLs.

Users only need to say "deploy this project", and the skill will automatically complete: build → upload → configure Nginx → issue SSL certificate → return preview URL.

## Constraints & Prerequisites

| Dimension | Decision |
|----------|----------|
| Project Type | Only static SPA projects (dist directory after Vite/React/Vue build) |
| Target Server | Dedicated preview server with Nginx installed |
| Domain Scheme | Wildcard `*.preview.example.com`, DNS resolved to preview server |
| HTTPS | acme.sh automatically applies and renews free certificates |
| Deployment Method | Local build → SCP upload → SSH call server-side script |

## Architecture

```
Local (Claude Code)                    Preview Server
┌─────────────────────┐              ┌──────────────────────────┐
│  SKILL.md            │              │  deploy-preview.sh       │
│  (presentation skill)│              │  (installed in working dir)│
│                      │              │                          │
│  1. Detect project type │              │  1. Create site directory │
│  2. npm/pnpm build   │   SCP        │  2. Write Nginx vhost config │
│  3. Package dist/ ────┼──────────────>│  3. nginx -t && reload   │
│  4. Call deploy script ─┼── SSH ──────>│  4. acme.sh issue cert  │
│  5. Return URL to user│              │  5. Update Nginx with HTTPS │
│                      │              │  6. nginx reload         │
└─────────────────────┘              └──────────────────────────┘
```

## File Structure

```
~/.claude/skills/presentation/
├── SKILL.md              # Skill definition (triggers, execution steps)
├── config.md             # Preview server configuration (IP, domain, paths, Nginx params)
├── DEPLOYMENTS.md        # Deployment history (project name, URL, time, status)
└── scripts/
    └── deploy-preview.sh # Server-side deployment script (SCP to server working dir)
```

## Component Responsibilities

| Component | Responsibility |
|----------|----------------|
| SKILL.md | Trigger condition recognition, execution flow orchestration, config reading, local build |
| config.md | Server connection info, path configuration, Nginx parameters (including auto-detected values) |
| DEPLOYMENTS.md | Deployment history, append after each deployment |
| deploy-preview.sh | Server operations: create directory, generate Nginx config, reload, issue SSL |

## Trigger Conditions

| Trigger Method | Example |
|---------------|---------|
| Command | `/presentation` |
| Natural Language | "deploy", "发布预览", "deploy to preview server" |
| With Parameters | "deploy to preview, subdomain name my-app" |

## Configuration File (config.md)

```markdown
# Presentation Skill Configuration

## Preview Server
- IP: <user-filled>
- SSH User: root
- SSH Port: 22

## Domain
- base_domain: preview.example.com

## Server Paths
- deploy_base_dir: /opt/presentation    # Working directory (scripts, logs, configs)
- web_root: /var/www/previews           # Site files directory
- nginx_conf_dir: /etc/nginx/conf.d/previews/  # vhost config directory

## Nginx (auto-detected during first init)
- nginx_bin: <auto-detected, usually /usr/sbin/nginx>
- nginx_reload_cmd: <auto-detected, usually systemctl reload nginx>
- nginx_include_ok: <auto-detected, confirms nginx.conf includes conf.d/*.conf>

## SSL
- cert_tool: acme.sh
- acme_sh_path: <auto-detected, usually ~/.acme.sh/acme.sh>

## Build Detection (local)
- Priority: Check if Makefile has deploy target first
- Otherwise: go through standard build → deploy flow
```

## Execution Flow

### Makefile Routing Rules

When user says "deploy", first check if Makefile has deploy-related targets:

- **Has deploy target** → Completely execute `make deploy` via Makefile, not following presentation skill flow. This is for projects with existing complete deployment workflows.
- **No Makefile or no deploy target** → Follow presentation skill's standard flow.

This is routing-level judgment, not a step within the skill.

### Build Command Detection

```
1. package.json → scripts.build
2. Default: npm run build
```

### Package Manager Detection

```
1. pnpm-lock.yaml exists → pnpm build
2. yarn.lock exists → yarn build
3. Otherwise → npm run build
```

### Subdomain Generation Rules

```
Priority: User specified > package.json name field > current directory name
Rule: Convert to lowercase, replace non-alphanumeric characters with -
```

### Deployment Steps

```
1. Read config.md for server and domain configuration
2. Read package.json to identify project name and build command
3. Generate subdomain
4. Execute local build (choose npm/pnpm/yarn based on package manager detection)
5. Verify dist/ or build/ directory exists and is not empty
6. SCP upload to server {web_root}/{project-name}/
7. SSH execute: bash {deploy_base_dir}/deploy-preview.sh {project} {subdomain} {base_domain}
8. Parse script output, return result to user
9. Update DEPLOYMENTS.md deployment record
10. Generate Makefile deploy target (during first deployment, for subsequent make deploy)
```

## deploy-preview.sh Design

### Configuration Reading

The script reads path parameters from the server-side config file `{deploy_base_dir}/config.env` (generated during init):

```bash
# /opt/presentation/config.env (auto-generated during init)
WEB_ROOT=/var/www/previews
NGINX_CONF_DIR=/etc/nginx/conf.d/previews
NGINX_BIN=/usr/sbin/nginx
NGINX_RELOAD_CMD="systemctl reload nginx"
ACME_SH_PATH=/root/.acme.sh/acme.sh
```

### Invocation Method

```bash
bash {deploy_base_dir}/deploy-preview.sh <project-name> <subdomain> <base-domain>
```

### Execution Flow

```
1. source config.env to load path configuration
2. Parameter validation (project-name, subdomain, base-domain not empty)
3. Create site directory {web_root}/{project-name}/ (if not exists)
4. Generate HTTP version Nginx config:
   - Path: {nginx_conf_dir}/{subdomain}.conf
   - server_name: {subdomain}.{base-domain}
   - root: {web_root}/{project-name}
   - location /: try_files $uri $uri/ /index.html
5. nginx -t to test config validity
6. nginx reload
7. acme.sh --issue -d {subdomain}.{base-domain} --nginx
8. Update Nginx config to include SSL:
   - listen 443 ssl
   - ssl_certificate points to acme.sh issued certificate
   - ssl_certificate_key points to private key
   - HTTP server_block added with 301 redirect to HTTPS
9. nginx -t && nginx reload
10. Output result:
    Success: {"status":"success","url":"https://{subdomain}.{base-domain}"}
    Failure: {"status":"error","message":"failure reason"}
```

### Idempotency

- Re-deploying same project: overwrite site files, Nginx config overwritten, certificate renewed if exists
- Re-deploying same subdomain: complete overwrite, no cleanup needed

## First Initialization (`/presentation init`)

When using for the first time, execute initialization flow to prepare preview server environment:

```
1. Prompt user to fill in basic config.md info (IP, SSH user, domain)
2. SSH connect to server, auto-detect:
   - Nginx installation path (which nginx / nginx -V)
   - Nginx config directory (parse nginx -t output)
   - Nginx include already contains previews directory
   - acme.sh installation path
   - Disk space is sufficient
3. Create server directory structure:
   - {deploy_base_dir}/           (working directory)
   - {deploy_base_dir}/logs/      (log directory)
   - {web_root}/                  (site root directory)
   - {nginx_conf_dir}/            (vhost config directory)
4. Upload deploy-preview.sh to {deploy_base_dir}/
5. Generate {deploy_base_dir}/config.env (contains detected path values)
6. Ensure nginx.conf includes include {nginx_conf_dir}/*.conf
7. Verify: nginx -t
8. Write detected values back to config.md
9. Output: Preview server initialization completed
```

## Error Handling

| Scenario | Handling |
|----------|----------|
| package.json doesn't exist | Prompt "Current directory is not a frontend project, cannot deploy" |
| build fails | Show error logs, stop deployment |
| dist directory is empty | Prompt "Build artifacts are empty, please check build configuration" |
| SCP upload fails | Check server connection, prompt to retry |
| Nginx config conflict | Prompt subdomain already in use, suggest changing |
| Nginx reload fails | Rollback config file, output error logs |
| SSL issuance fails | Deploy with HTTP first, prompt certificate issuance failure reason, suggest manual handling |
| Server connection fails | Prompt to check server info in config.md |

## Deployment Record Format (DEPLOYMENTS.md)

```markdown
# Deployment History

| Project Name | Subdomain | URL | Last Deployment Time | Status |
|--------------|-----------|-----|---------------------|--------|
| my-app | my-app | https://my-app.preview.example.com | 2026-04-09 14:30 | ✅ |
| dashboard | dash | https://dash.preview.example.com | 2026-04-09 15:00 | ✅ |
```

## Makefile Auto-generation

After first successful deployment, the skill automatically generates or appends a Makefile `deploy` target in the user project root directory, for subsequent direct `make deploy` re-deployment without going through Claude again.

### Behavior Rules

```
1. After successful deployment, check if Makefile exists in project root
2. If no Makefile → create Makefile
3. If Makefile exists but no deploy target → append deploy target
4. If Makefile already has deploy target → don't overwrite, skip (respect user customization)
5. Commands in deploy target use parameters actually detected during this deployment (package manager, server info, etc.)
```

### Generated Makefile Example

```makefile
# Auto-generated by presentation skill
# Can run make deploy directly afterwards

.PHONY: deploy

deploy:
	pnpm install && pnpm build
	scp -r -P 22 ./dist/* root@203.0.113.10:/var/www/previews/my-app/
	ssh -p 22 root@203.0.113.10 "bash /opt/presentation/deploy-preview.sh my-app my-app preview.example.com"
```

### Template

```
.PHONY: deploy

deploy:
	{pkg_install} && {pkg_build}
	scp -r -P {ssh_port} ./{build_dir}/* {ssh_user}@{server_ip}:{web_root}/{project_name}/
	ssh -p {ssh_port} {ssh_user}@{server_ip} "bash {deploy_base_dir}/deploy-preview.sh {project_name} {subdomain} {base_domain}"
```

Variables come from config.md and actual values detected during this deployment.

## What It Doesn't Do

- Doesn't support SSR applications (Next.js/Nuxt.js projects that require Node runtime)
- Doesn't support backend service deployment
- Doesn't do CI/CD (manual trigger only)
- Doesn't do advanced deployment features like gray release, rollback
- Doesn't manage domain DNS (prerequisite is wildcard already configured)