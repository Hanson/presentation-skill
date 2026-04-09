# Presentation Skill - 设计文档

> 日期: 2026-04-09
> 状态: 已确认

## 概述

Presentation 是一个 Claude Code skill，用于将本地前端 SPA 项目一键部署到专用预览服务器，生成可公开访问的 HTTPS 预览 URL。

用户只需说"部署一下这个项目"，skill 即可自动完成：构建 → 上传 → 配置 Nginx → 签发 SSL 证书 → 返回预览 URL。

## 约束与前提

| 维度 | 决策 |
|------|------|
| 项目类型 | 仅支持静态 SPA（Vite/React/Vue 打包后的 dist 目录） |
| 目标服务器 | 专用预览服务器，已安装 Nginx |
| 域名方案 | 通配符 `*.preview.example.com`，DNS 已解析到预览服务器 |
| HTTPS | acme.sh 自动申请续费免费证书 |
| 部署方式 | 本地 build → SCP 上传 → SSH 调用服务端脚本 |

## 架构

```
本地 (Claude Code)                    预览服务器
┌─────────────────────┐              ┌──────────────────────────┐
│  SKILL.md            │              │  deploy-preview.sh       │
│  (presentation skill)│              │  (安装在工作目录)          │
│                      │              │                          │
│  1. 检测项目类型      │              │  1. 创建站点目录          │
│  2. npm/pnpm build   │   SCP        │  2. 写 Nginx vhost 配置  │
│  3. 打包 dist/ ──────┼──────────────>│  3. nginx -t && reload   │
│  4. 调用部署脚本 ─────┼── SSH ──────>│  4. acme.sh 签发证书     │
│  5. 返回 URL 给用户   │              │  5. 更新 Nginx 加 HTTPS  │
│                      │              │  6. nginx reload         │
└─────────────────────┘              └──────────────────────────┘
```

## 文件结构

```
~/.claude/skills/presentation/
├── SKILL.md              # Skill 定义（触发词、执行步骤）
├── config.md             # 预览服务器配置（IP、域名、路径、Nginx 参数）
├── DEPLOYMENTS.md        # 部署历史记录（项目名、URL、时间、状态）
└── scripts/
    └── deploy-preview.sh # 服务端部署脚本（SCP 到服务器工作目录）
```

## 组件职责

| 组件 | 职责 |
|------|------|
| SKILL.md | 触发条件识别、执行流程编排、配置读取、本地构建 |
| config.md | 服务器连接信息、路径配置、Nginx 参数（含自动检测后的值） |
| DEPLOYMENTS.md | 部署历史记录，每次部署后追加 |
| deploy-preview.sh | 服务端操作：创建目录、生成 Nginx 配置、reload、签发 SSL |

## 触发条件

| 触发方式 | 示例 |
|---------|------|
| 命令触发 | `/presentation` |
| 自然语言 | "部署一下"、"deploy"、"发布预览"、"部署到预览服务器" |
| 带参数 | "部署到预览，子域名叫 my-app" |

## 配置文件 (config.md)

```markdown
# Presentation Skill 配置

## 预览服务器
- IP: <用户填写>
- SSH User: root
- SSH Port: 22

## 域名
- base_domain: preview.example.com

## 服务器路径
- deploy_base_dir: /opt/presentation    # 工作目录（脚本、日志、配置）
- web_root: /var/www/previews           # 站点文件目录
- nginx_conf_dir: /etc/nginx/conf.d/previews/  # vhost 配置目录

## Nginx（首次 init 时自动检测）
- nginx_bin: <自动检测，通常 /usr/sbin/nginx>
- nginx_reload_cmd: <自动检测，通常 systemctl reload nginx>
- nginx_include_ok: <自动检测，确认 nginx.conf 包含 conf.d/*.conf>

## SSL
- cert_tool: acme.sh
- acme_sh_path: <自动检测，通常 ~/.acme.sh/acme.sh>

## 构建检测（本地）
- 优先检查 Makefile 是否有 deploy target
- 否则走标准 build → deploy 流程
```

## 执行流程

### Makefile 路由规则

当用户说"部署"时，先检查 Makefile 是否有 deploy 相关 target：

- **有 deploy target** → 完全交给 Makefile 执行 `make deploy`，不走 presentation skill 流程。这适用于已有完善部署流程的项目。
- **没有 Makefile 或没有 deploy target** → 走 presentation skill 的标准流程。

这是路由层面的判断，不是 skill 内部的步骤。

### 构建命令检测

```
1. package.json → scripts.build
2. 默认: npm run build
```

### 包管理器检测

```
1. pnpm-lock.yaml 存在 → pnpm build
2. yarn.lock 存在 → yarn build
3. 否则 → npm run build
```

### 子域名生成规则

```
优先级: 用户指定 > package.json 的 name 字段 > 当前目录名
规则: 转为小写，替换非字母数字字符为 -
```

### 部署步骤

```
1. 读取 config.md 获取服务器和域名配置
2. 读取 package.json 识别项目名和 build 命令
3. 生成子域名
4. 本地执行构建（根据包管理器检测选择 npm/pnpm/yarn）
5. 验证 dist/ 或 build/ 目录存在且非空
6. SCP 上传到服务器 {web_root}/{project-name}/
7. SSH 执行: bash {deploy_base_dir}/deploy-preview.sh {project} {subdomain} {base_domain}
8. 解析脚本输出，返回结果给用户
9. 更新 DEPLOYMENTS.md 部署记录
```

## deploy-preview.sh 设计

### 配置读取

脚本从服务器端配置文件 `{deploy_base_dir}/config.env` 读取路径参数（init 时生成）：

```bash
# /opt/presentation/config.env（init 时自动生成）
WEB_ROOT=/var/www/previews
NGINX_CONF_DIR=/etc/nginx/conf.d/previews
NGINX_BIN=/usr/sbin/nginx
NGINX_RELOAD_CMD="systemctl reload nginx"
ACME_SH_PATH=/root/.acme.sh/acme.sh
```

### 调用方式

```bash
bash {deploy_base_dir}/deploy-preview.sh <project-name> <subdomain> <base-domain>
```

### 执行流程

```
1. source config.env 加载路径配置
2. 参数校验（project-name, subdomain, base-domain 非空）
2. 创建站点目录 {web_root}/{project-name}/（如不存在）
3. 生成 HTTP 版 Nginx 配置:
   - 路径: {nginx_conf_dir}/{subdomain}.conf
   - server_name: {subdomain}.{base-domain}
   - root: {web_root}/{project-name}
   - location /: try_files $uri $uri/ /index.html
4. nginx -t 测试配置合法性
5. nginx reload
6. acme.sh --issue -d {subdomain}.{base-domain} --nginx
7. 更新 Nginx 配置加入 SSL:
   - listen 443 ssl
   - ssl_certificate 指向 acme.sh 签发的证书
   - ssl_certificate_key 指向私钥
   - HTTP server_block 加 301 重定向到 HTTPS
8. nginx -t && nginx reload
9. 输出结果:
   成功: {"status":"success","url":"https://{subdomain}.{base-domain}"}
   失败: {"status":"error","message":"失败原因"}
```

### 幂等性

- 重复部署同一项目：覆盖站点文件，Nginx 配置覆盖更新，证书已有则跳过或续签
- 同一子域名重新部署：完全覆盖，无需清理

## 首次初始化 (`/presentation init`)

用户首次使用时，执行初始化流程准备预览服务器环境：

```
1. 提示用户填写 config.md 基础信息（IP、SSH 用户、域名）
2. SSH 连接服务器，自动检测:
   - Nginx 安装路径 (which nginx / nginx -V)
   - Nginx 配置目录 (解析 nginx -t 输出)
   - Nginx include 是否已包含 previews 目录
   - acme.sh 安装路径
   - 磁盘空间是否充足
3. 创建服务器端目录结构:
   - {deploy_base_dir}/           (工作目录)
   - {deploy_base_dir}/logs/      (日志目录)
   - {web_root}/                  (站点根目录)
   - {nginx_conf_dir}/            (vhost 配置目录)
4. 上传 deploy-preview.sh 到 {deploy_base_dir}/
5. 生成 {deploy_base_dir}/config.env（包含检测到的路径值）
6. 确保 nginx.conf 包含 include {nginx_conf_dir}/*.conf
6. 验证: nginx -t
7. 将检测到的值写回 config.md
8. 输出: 预览服务器初始化完成
```

## 错误处理

| 场景 | 处理方式 |
|------|---------|
| package.json 不存在 | 提示 "当前目录不是前端项目，无法部署" |
| build 失败 | 展示错误日志，中断部署 |
| dist 目录为空 | 提示 "构建产物为空，请检查构建配置" |
| SCP 上传失败 | 检查服务器连接，提示重试 |
| Nginx 配置冲突 | 提示子域名已被占用，建议更换 |
| Nginx reload 失败 | 回滚配置文件，输出错误日志 |
| SSL 签发失败 | 先以 HTTP 部署，提示证书签发失败原因，建议手动处理 |
| 服务器连接失败 | 提示检查 config.md 中的服务器信息 |

## 部署记录格式 (DEPLOYMENTS.md)

```markdown
# 部署历史

| 项目名 | 子域名 | URL | 最后部署时间 | 状态 |
|--------|--------|-----|------------|------|
| my-app | my-app | https://my-app.preview.example.com | 2026-04-09 14:30 | ✅ |
| dashboard | dash | https://dash.preview.example.com | 2026-04-09 15:00 | ✅ |
```

## 不做的事情

- 不支持 SSR 应用（Next.js/Nuxt.js 等需要 Node 运行时的项目）
- 不支持后端服务部署
- 不做 CI/CD（仅手动触发）
- 不做灰度发布、版本回滚等高级部署功能
- 不管理域名 DNS（前提是通配符已配好）
