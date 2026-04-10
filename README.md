# Presentation Skill

**One-click frontend SPA deployment for Claude Code.**

Build, upload, configure Nginx, issue SSL certificates, and get a public HTTPS URL — all from a single command.

[简体中文](docs/README.zh-CN.md) | [Official Website](https://preview.juhebot.com)

---

## What It Does

Presentation is a [Claude Code Skill](https://docs.anthropic.com/en/docs/claude-code/skills) that deploys your local frontend SPA project to a dedicated preview server. Just tell Claude:

> "Deploy this project"

And it automatically:

1. Detects your package manager and build command
2. Runs the build locally
3. Uploads the output via SCP
4. Configures Nginx virtual host on the server
5. Issues an SSL certificate via acme.sh (Let's Encrypt)
6. Returns a public HTTPS URL

```
https://my-app.preview.example.com
```

## Features

- **Natural Language Triggers** — Say "deploy", "部署一下", or use `/presentation`
- **Auto-Detection** — Package manager (pnpm/yarn/npm), build output directory, project name
- **Automatic HTTPS** — SSL certificates issued and renewed via acme.sh
- **Idempotent** — Redeploy safely; files and config are overwritten
- **Deployment History** — Every deployment is logged in a Markdown table
- **Makefile Routing** — If your project has `make deploy`, it uses that instead

## Architecture

```
Local (Claude Code)                   Preview Server
┌─────────────────────┐              ┌──────────────────────────┐
│  SKILL.md            │              │  deploy-preview.sh       │
│  (presentation skill)│              │                          │
│                      │              │  1. Create site directory │
│  1. Detect project   │              │  2. Write Nginx vhost    │
│  2. Build locally    │   SCP        │  3. nginx -t && reload   │
│  3. Package dist/ ───┼─────────────>│  4. Issue SSL cert       │
│  4. Run deploy ──────┼── SSH ──────>│  5. Update Nginx HTTPS  │
│  5. Return URL       │              │  6. nginx reload         │
└─────────────────────┘              └──────────────────────────┘
```

## Prerequisites

### Server Side

- A Linux server with **Nginx** installed
- **acme.sh** installed (for SSL certificates)
- **Wildcard DNS** configured: `*.your-domain.com` → your server IP
- SSH access (key or password)

### Local Side

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- A frontend SPA project with `package.json` and a build script

### Supported Projects

| Supported | Not Supported |
|-----------|---------------|
| Vite (React, Vue, Svelte, etc.) | Next.js (SSR) |
| Create React App | Nuxt.js (SSR) |
| Vue CLI | Any server-side rendered app |
| Any static SPA with a build step | Backend services |

## Installation

### Option 1: Clone and Install

```bash
git clone https://github.com/Hanson/presentation-skill.git
cd presentation-skill
# Copy skill files to Claude Code skills directory
mkdir -p ~/.claude/skills/presentation
cp -r src/* ~/.claude/skills/presentation/
chmod +x ~/.claude/skills/presentation/scripts/deploy-preview.sh
```

### Option 2: Manual Setup

Create the skill directory and add the files:

```bash
mkdir -p ~/.claude/skills/presentation/scripts
```

Place the following files in `~/.claude/skills/presentation/`:

```
~/.claude/skills/presentation/
├── SKILL.md              # Skill definition (triggers, workflow)
├── config.md             # Server configuration (filled by init)
├── DEPLOYMENTS.md        # Deployment history log
└── scripts/
    └── deploy-preview.sh # Server-side deployment script
```

## Quick Start

### Step 1: Initialize the Preview Server

Run the init command to set up your server:

```
/presentation init
```

Claude will ask you for:
- **Server IP** — Your preview server's IP address
- **Base Domain** — e.g., `preview.example.com`
- **SSH User** — default: `root`
- **SSH Port** — default: `22`

Then it automatically:
- Detects Nginx and acme.sh paths
- Creates server directories (`/opt/presentation`, `/var/www/previews`, etc.)
- Uploads the deployment script
- Generates server-side config (`config.env`)
- Verifies Nginx configuration

### Step 2: Deploy Your Project

Navigate to any frontend project and say:

```
/presentation
```

Or use natural language:

> "Deploy this project"
> "deploy"
> "发布预览"

Claude will build and deploy, then return the URL:

```
Deployment successful!

Project: my-app
URL: https://my-app.preview.example.com

Deployment record updated.
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `/presentation` | Deploy current project to preview server |
| `/presentation init` | Initialize preview server (first-time setup) |

### Natural Language Triggers

| Language | Examples |
|----------|---------|
| English | "deploy", "deploy this project", "publish preview" |
| Chinese | "部署一下", "发布预览", "部署到预览服务器" |

### Custom Subdomain

You can specify a custom subdomain:

> "Deploy to preview, subdomain name is my-dashboard"

Subdomain generation priority: **User specified** > `package.json` name > directory name

### Makefile Integration

If your project has a `Makefile` with a `deploy` target, the skill will use `make deploy` instead of the built-in flow. This is useful for projects with existing deployment pipelines.

## Configuration

### config.md (Local)

Located at `~/.claude/skills/presentation/config.md`. Filled automatically by `/presentation init`.

```markdown
## Preview Server
- IP: 203.0.113.10
- SSH User: root
- SSH Port: 22

## Domain
- base_domain: preview.example.com

## Server Paths
- deploy_base_dir: /opt/presentation
- web_root: /var/www/previews
- nginx_conf_dir: /etc/nginx/conf.d/previews

## Nginx (auto-detected by init)
- nginx_bin: /usr/sbin/nginx
- nginx_reload_cmd: systemctl reload nginx
- nginx_include_ok: true

## SSL
- cert_tool: acme.sh
- acme_sh_path: /root/.acme.sh/acme.sh
```

### config.env (Server-side)

Located at `/opt/presentation/config.env` on the preview server. Generated by `/presentation init`.

```bash
WEB_ROOT=/var/www/previews
NGINX_CONF_DIR=/etc/nginx/conf.d/previews
NGINX_BIN=/usr/sbin/nginx
NGINX_RELOAD_CMD="systemctl reload nginx"
ACME_SH_PATH=/root/.acme.sh/acme.sh
```

## Deployment History

All deployments are tracked in `~/.claude/skills/presentation/DEPLOYMENTS.md`:

| Project | Subdomain | URL | Last Deployed | Status |
|---------|-----------|-----|--------------|--------|
| my-app | my-app | https://my-app.preview.example.com | 2026-04-09 14:30 | OK |
| dashboard | dash | https://dash.preview.example.com | 2026-04-09 15:00 | OK |

## How It Works

### Build Detection

The skill automatically detects your build setup:

1. **Package manager**: Checks for `pnpm-lock.yaml` → `yarn.lock` → falls back to `npm`
2. **Build command**: Reads `scripts.build` from `package.json`, defaults to `npm run build`
3. **Output directory**: Checks `dist/` then `build/`

### Deployment Flow

```
1. Read config.md → server & domain settings
2. Read package.json → project name & build command
3. Generate subdomain
4. Run build locally (pnpm/yarn/npm)
5. Verify build output exists and is non-empty
6. SCP upload to server
7. SSH execute deploy-preview.sh
8. Parse result JSON
9. Update DEPLOYMENTS.md
10. Return URL to user
```

### Server-Side Script

`deploy-preview.sh` runs on the preview server and handles:

1. Create site directory
2. Write Nginx HTTP vhost config
3. Test and reload Nginx
4. Issue SSL certificate via acme.sh
5. Update Nginx config with HTTPS (HTTP 301 redirect)
6. Test and reload Nginx again

Output is JSON for easy parsing:
- Success: `{"status":"success","url":"https://..."}`
- Failure: `{"status":"error","message":"..."}`

## Error Handling

| Scenario | Behavior |
|----------|----------|
| No `package.json` | "Not a frontend project, cannot deploy" |
| Build failure | Show error log, stop deployment |
| Empty build output | "Build output is empty, check build config" |
| SCP upload failure | "Check server connection" |
| Nginx config conflict | "Subdomain already in use, try another" |
| Nginx reload failure | Rollback config, show error log |
| SSL issue failure | Deploy with HTTP only, warn about SSL |
| Server connection failure | "Check config.md server settings" |

## Limitations

- Static SPA only — no SSR (Next.js, Nuxt.js server rendering)
- No backend service deployment
- No CI/CD — manual trigger only
- No canary releases or rollback
- DNS must be pre-configured (wildcard `*.<base_domain>`)

## File Structure

```
presentation-skill/
├── README.md                              # This file
├── docs/
│   ├── README.zh-CN.md                    # Chinese documentation
│   └── superpowers/
│       ├── specs/                         # Design specifications
│       └── plans/                         # Implementation plans
└── src/                                   # Skill source files
    ├── SKILL.md                           # Skill definition
    ├── config.md                          # Config template
    ├── DEPLOYMENTS.md                     # Deployment history
    └── scripts/
        └── deploy-preview.sh             # Server-side script
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License

---

[presentation-skill](https://preview.juhebot.com) - Deploy frontend SPAs with one command.
