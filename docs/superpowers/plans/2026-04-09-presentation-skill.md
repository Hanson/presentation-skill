# Presentation Skill 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建一个 Claude Code skill，将本地前端 SPA 项目一键部署到专用预览服务器，返回可公开访问的 HTTPS URL。

**Architecture:** 本地 SKILL.md 指导 Claude 执行构建和上传，服务器端 deploy-preview.sh 脚本处理 Nginx 配置和 SSL 证书签发。config.md 存储服务器配置，DEPLOYMENTS.md 记录部署历史。

**Tech Stack:** Claude Code Skill (SKILL.md markdown)、Bash shell script、Nginx、acme.sh、SCP/SSH

---

## File Structure

```
~/.claude/skills/presentation/
├── SKILL.md                  # Skill 定义：触发条件、执行流程、init 流程
├── config.md                 # 服务器配置模板（用户填写 + init 自动检测填充）
├── DEPLOYMENTS.md            # 部署历史记录（空模板）
└── scripts/
    └── deploy-preview.sh     # 服务端部署脚本（init 时 SCP 到服务器）
```

---

### Task 1: 创建目录结构和 config.md

**Files:**
- Create: `~/.claude/skills/presentation/config.md`

- [ ] **Step 1: 创建 skill 目录结构**

```bash
mkdir -p ~/.claude/skills/presentation/scripts
```

- [ ] **Step 2: 创建 config.md 配置模板**

创建 `~/.claude/skills/presentation/config.md`，内容如下：

```markdown
---
name: presentation-config
description: Presentation Skill 服务器配置文件，init 时自动填充检测值
---

# Presentation Skill 配置

## 预览服务器

- IP:
- SSH User: root
- SSH Port: 22

## 域名

- base_domain:

## 服务器路径

- deploy_base_dir: /opt/presentation
- web_root: /var/www/previews
- nginx_conf_dir: /etc/nginx/conf.d/previews

## Nginx（init 时自动检测填充）

- nginx_bin:
- nginx_reload_cmd:
- nginx_include_ok: false

## SSL

- cert_tool: acme.sh
- acme_sh_path:

## 构建检测（本地）

- 优先检查 Makefile 是否有 deploy target
- 否则走标准 build → deploy 流程
```

注意：所有值为空，需要用户运行 `/presentation init` 后自动填充，或手动填写 IP 和 base_domain 后再 init。

- [ ] **Step 3: 验证文件已创建**

```bash
ls -la ~/.claude/skills/presentation/config.md
```

Expected: 文件存在

- [ ] **Step 4: Commit**

```bash
cd ~/.claude/skills/presentation
git init
git add config.md
git commit -m "feat: add presentation skill config template"
```

注意：如果 `~/.claude/` 不是 git repo，跳过 git 操作，仅验证文件创建成功即可。

---

### Task 2: 创建 DEPLOYMENTS.md 部署历史模板

**Files:**
- Create: `~/.claude/skills/presentation/DEPLOYMENTS.md`

- [ ] **Step 1: 创建 DEPLOYMENTS.md**

创建 `~/.claude/skills/presentation/DEPLOYMENTS.md`，内容如下：

```markdown
# 部署历史

| 项目名 | 子域名 | URL | 最后部署时间 | 状态 |
|--------|--------|-----|------------|------|
```

这是一个空表，每次部署后由 SKILL.md 中的流程追加新行。

- [ ] **Step 2: 验证文件已创建**

```bash
ls -la ~/.claude/skills/presentation/DEPLOYMENTS.md
```

Expected: 文件存在

- [ ] **Step 3: Commit**

```bash
git add DEPLOYMENTS.md
git commit -m "feat: add deployment history template"
```

---

### Task 3: 创建 deploy-preview.sh 服务端部署脚本

**Files:**
- Create: `~/.claude/skills/presentation/scripts/deploy-preview.sh`

这是最关键的组件，运行在预览服务器上，负责 Nginx 配置和 SSL 证书。

- [ ] **Step 1: 创建 deploy-preview.sh**

创建 `~/.claude/skills/presentation/scripts/deploy-preview.sh`，内容如下：

```bash
#!/usr/bin/env bash
set -euo pipefail

# ============================================
# Presentation Skill - 服务端部署脚本
# 用途: 配置 Nginx 虚拟主机 + acme.sh 签发 SSL
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

# 加载服务器端配置
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo '{"status":"error","message":"config.env not found at '"${CONFIG_FILE}"'. Run /presentation init first."}'
    exit 1
fi

source "$CONFIG_FILE"

# 参数校验
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

# 确保日志目录存在
mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_DIR}/deploy.log"
}

# ============================================
# Step 1: 创建站点目录
# ============================================
mkdir -p "$SITE_DIR"
log "Site directory ready: ${SITE_DIR}"

# ============================================
# Step 2: 生成 HTTP 版 Nginx 配置
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
# Step 3: 测试并 reload Nginx
# ============================================
if ! ${NGINX_BIN} -t 2>&1; then
    rm -f "$CONF_FILE"
    echo '{"status":"error","message":"nginx -t failed. Config removed."}'
    exit 1
fi

${NGINX_RELOAD_CMD}
log "Nginx reloaded with HTTP config"

# ============================================
# Step 4: 签发 SSL 证书
# ============================================
SSL_SUCCESS=false
CERT_DIR=""

if [[ -x "${ACME_SH_PATH}" ]]; then
    log "Issuing SSL cert for ${DOMAIN}..."

    if ${ACME_SH_PATH} --issue -d "$DOMAIN" --nginx 2>&1 | tee -a "${LOG_DIR}/deploy.log"; then
        SSL_SUCCESS=true
        # acme.sh 默认证书安装路径
        CERT_DIR="/root/.acme.sh/${DOMAIN}_ecc"
        if [[ ! -d "$CERT_DIR" ]]; then
            CERT_DIR="${HOME}/.acme.sh/${DOMAIN}_ecc"
        fi

        # 安装证书到 Nginx
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
# Step 5: 更新 Nginx 配置加入 SSL
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

- [ ] **Step 2: 设置脚本可执行权限**

```bash
chmod +x ~/.claude/skills/presentation/scripts/deploy-preview.sh
```

- [ ] **Step 3: 用 shellcheck 验证脚本（如已安装）**

```bash
shellcheck ~/.claude/skills/presentation/scripts/deploy-preview.sh || echo "shellcheck not installed, skipping"
```

Expected: 无错误，或 shellcheck 未安装时跳过

- [ ] **Step 4: Commit**

```bash
git add scripts/deploy-preview.sh
git commit -m "feat: add server-side deploy script with Nginx + acme.sh"
```

---

### Task 4: 创建 SKILL.md 主文件

**Files:**
- Create: `~/.claude/skills/presentation/SKILL.md`

这是 skill 的入口文件，Claude 读取它来理解如何执行部署。

- [ ] **Step 1: 创建 SKILL.md**

创建 `~/.claude/skills/presentation/SKILL.md`，内容如下：

```markdown
---
name: presentation
description: 将前端 SPA 项目一键部署到预览服务器。当用户说"部署一下"、"deploy"、"发布预览"时使用。支持 /presentation 命令触发。
---

# Presentation Skill - 前端项目预览部署

将当前目录的前端 SPA 项目构建并部署到预览服务器，返回可公开访问的 URL。

## 前置条件

- 预览服务器已配置 Nginx
- 通配符域名 `*.<base_domain>` 已解析到预览服务器
- 已运行 `/presentation init` 完成初始化（或手动填写 config.md）

## 配置文件

配置存储在 SKILL 同目录下的 `config.md`。

本目录: `~/.claude/skills/presentation/`

## 命令格式

- `/presentation` - 部署当前项目到预览服务器
- `/presentation init` - 初始化预览服务器（首次使用）
- "部署一下" / "deploy" / "发布预览" / "部署到预览服务器" - 自然语言触发

## Makefile 路由规则

**重要：** 当用户说"部署"时，先检查当前目录是否有 Makefile 且包含 deploy 相关 target。

- **有 Makefile deploy target** → 执行 `make deploy`，不走本 skill 流程
- **没有 Makefile 或没有 deploy target** → 继续执行下方流程

## 初始化流程 (`/presentation init`)

首次使用时执行：

1. **收集基础信息** - 如果 config.md 中 IP 或 base_domain 为空，使用 AskUserQuestion 询问用户：
   - 预览服务器 IP 地址
   - 基础域名（如 preview.example.com）
   - SSH 用户名（默认 root）
   - SSH 端口（默认 22）

2. **自动检测服务器环境** - 通过 SSH 执行以下命令：
   ```bash
   # 检测 Nginx
   which nginx
   nginx -t 2>&1
   nginx -V 2>&1 | grep "configure arguments"

   # 检测 acme.sh
   which acme.sh || ls ~/.acme.sh/acme.sh 2>/dev/null

   # 检测磁盘空间
   df -h /var/www
   ```

3. **创建服务器端目录结构** - 通过 SSH：
   ```bash
   mkdir -p /opt/presentation/logs
   mkdir -p /opt/presentation/scripts
   mkdir -p /var/www/previews
   mkdir -p /etc/nginx/conf.d/previews
   ```

4. **上传部署脚本** - 使用 SCP：
   ```bash
   scp ~/.claude/skills/presentation/scripts/deploy-preview.sh <user>@<ip>:/opt/presentation/
   ```

5. **生成服务器端 config.env** - 通过 SSH 写入：
   ```bash
   cat > /opt/presentation/config.env << 'ENVEOF'
   WEB_ROOT=/var/www/previews
   NGINX_CONF_DIR=/etc/nginx/conf.d/previews
   NGINX_BIN=<检测到的路径>
   NGINX_RELOAD_CMD=<检测到的命令>
   ACME_SH_PATH=<检测到的路径>
   ENVEOF
   ```

6. **确保 Nginx 包含 previews 目录** - 检查 nginx.conf 是否有：
   ```
   include /etc/nginx/conf.d/previews/*.conf;
   ```
   如果没有，提示用户手动添加此行到 nginx.conf 的 http 块中。

7. **验证** - 执行 `nginx -t` 确认配置正确。

8. **更新 config.md** - 将检测到的值写回 config.md，标记 `nginx_include_ok: true`。

9. **告知用户** - 输出初始化完成信息，列出检测到的配置。

## 部署流程

当用户触发部署（非 init）时，按以下步骤执行：

### Step 1: 读取配置

读取 `~/.claude/skills/presentation/config.md`，获取：
- 服务器 IP、SSH User、SSH Port
- base_domain
- deploy_base_dir、web_root

如果关键字段（IP、base_domain）为空，提示用户先运行 `/presentation init`。

### Step 2: 检测项目信息

读取当前目录的 `package.json`：
- `name` 字段作为项目名（fallback 到目录名）
- `scripts.build` 字段作为构建命令

如果 `package.json` 不存在，提示：
> 当前目录不是前端项目（未找到 package.json），无法部署。

### Step 3: 确定子域名

规则：
1. 用户在消息中指定了子域名 → 使用用户指定的
2. 否则使用 package.json 的 `name` 字段
3. 否则使用当前目录名
4. 转为小写，将非字母数字字符替换为 `-`

### Step 4: 本地构建

**包管理器检测：**
- `pnpm-lock.yaml` 存在 → `pnpm install && pnpm build`
- `yarn.lock` 存在 → `yarn install && yarn build`
- 否则 → `npm install && npm run build`

如果构建失败（非零退出码），展示错误日志，中断流程，不继续部署。

### Step 5: 验证构建产物

检查 `dist/` 或 `build/` 目录：
- 存在且非空 → 继续
- 不存在或为空 → 提示"构建产物为空，请检查构建配置"，中断流程

### Step 6: 上传到服务器

先通过 SSH 确保目标目录存在，再使用 SCP 上传构建产物：

```bash
ssh -p <port> <user>@<ip> "mkdir -p <web_root>/<project-name>"
scp -r -P <port> ./dist/* <user>@<ip>:<web_root>/<project-name>/
```

如果上传失败，提示检查服务器连接。

### Step 7: 执行服务端部署脚本

通过 SSH 执行：

```bash
ssh -p <port> <user>@<ip> "bash <deploy_base_dir>/deploy-preview.sh <project-name> <subdomain> <base-domain>"
```

解析脚本输出（JSON 格式）：
- `{"status":"success","url":"https://..."}` → 部署成功
- `{"status":"error","message":"..."}` → 部署失败，展示错误信息

### Step 8: 更新部署记录

在 `~/.claude/skills/presentation/DEPLOYMENTS.md` 的表格末尾追加一行：

```markdown
| <project-name> | <subdomain> | https://<subdomain>.<base_domain> | <YYYY-MM-DD HH:mm> | ✅ |
```

如果部署失败，状态列写 ❌。

### Step 9: 返回结果给用户

**成功：**
```
✅ 部署成功！

项目: <project-name>
URL: https://<subdomain>.<base_domain>

部署记录已更新。
```

**失败：**
```
❌ 部署失败

项目: <project-name>
错误: <error message>

请检查上方日志，修复后重试。
```

## 错误处理

| 场景 | 处理 |
|------|------|
| config.md 未初始化 | 提示 "请先运行 /presentation init 初始化预览服务器" |
| package.json 不存在 | 提示 "当前目录不是前端项目，无法部署" |
| 构建失败 | 展示错误日志，中断 |
| 构建产物为空 | 提示检查构建配置，中断 |
| SCP 上传失败 | 提示检查服务器连接 |
| SSL 签发失败 | 脚本自动回退到 HTTP，提示证书问题 |

## 注意事项

- 每次部署会覆盖服务器上同一项目的旧文件（幂等）
- 同一子域名重新部署会覆盖 Nginx 配置
- SSL 证书由 acme.sh 自动续期，无需手动处理
- 脚本执行日志保存在服务器的 `/opt/presentation/logs/deploy.log`
```

- [ ] **Step 2: 验证文件已创建**

```bash
ls -la ~/.claude/skills/presentation/SKILL.md
```

Expected: 文件存在，大小 > 0

- [ ] **Step 3: 验证目录结构完整**

```bash
find ~/.claude/skills/presentation -type f
```

Expected 输出:
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

### Task 5: 集成验证

验证 skill 是否能被 Claude Code 正确识别。

- [ ] **Step 1: 检查 SKILL.md frontmatter 格式**

确认 SKILL.md 以正确的 YAML frontmatter 开头：
```
---
name: presentation
description: ...
---
```

- [ ] **Step 2: 检查 deploy-preview.sh 语法**

```bash
bash -n ~/.claude/skills/presentation/scripts/deploy-preview.sh
```

Expected: 无输出（语法正确）

- [ ] **Step 3: 列出完整文件清单验证**

```bash
echo "=== Presentation Skill 文件清单 ==="
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
echo "=== 所有文件 ==="
find ~/.claude/skills/presentation -type f -exec ls -la {} \;
```

Expected: 4 个文件全部存在且内容正确

- [ ] **Step 4: 最终 Commit**

```bash
git add -A
git commit -m "feat: presentation skill complete - one-click SPA preview deployment"
```

---

## Spec Coverage Checklist

| Spec 要求 | Task |
|----------|------|
| SKILL.md 触发条件（/presentation、自然语言） | Task 4 |
| config.md 配置模板 | Task 1 |
| DEPLOYMENTS.md 部署历史 | Task 2 |
| deploy-preview.sh 服务端脚本 | Task 3 |
| Nginx 配置生成（HTTP → SSL） | Task 3 |
| acme.sh 证书签发 | Task 3 |
| config.env 服务器端配置读取 | Task 3 |
| 幂等性（重复部署覆盖） | Task 3 |
| /presentation init 初始化流程 | Task 4 (SKILL.md 中定义) |
| Makefile 路由规则 | Task 4 (SKILL.md 中定义) |
| 包管理器检测 (pnpm/yarn/npm) | Task 4 (SKILL.md 中定义) |
| 子域名生成规则 | Task 4 (SKILL.md 中定义) |
| 错误处理（全部场景） | Task 3 + Task 4 |
