# Presentation Skill

**Claude Code 一键前端 SPA 部署工具。**

构建、上传、配置 Nginx、签发 SSL 证书，一步到位获取公开的 HTTPS 预览 URL。

[English](../README.md) | 简体中文 | [官方网站](https://preview.juhebot.com)

---

## 项目简介

Presentation 是一个 [Claude Code Skill](https://docs.anthropic.com/en/docs/claude-code/skills)，用于将本地前端 SPA 项目一键部署到专用预览服务器。只需告诉 Claude：

> "部署一下这个项目"

它会自动完成：

1. 检测包管理器和构建命令
2. 本地执行构建
3. 通过 SCP 上传构建产物
4. 在服务器上配置 Nginx 虚拟主机
5. 通过 acme.sh（Let's Encrypt）签发 SSL 证书
6. 返回公开的 HTTPS URL

```
https://my-app.preview.example.com
```

## 功能特性

- **自然语言触发** — 说 "deploy"、"部署一下" 或使用 `/presentation` 命令
- **自动检测** — 包管理器（pnpm/yarn/npm）、构建输出目录、项目名称
- **自动 HTTPS** — 通过 acme.sh 自动签发和续期 SSL 证书
- **幂等部署** — 安全重复部署，文件和配置自动覆盖
- **部署历史** — 每次部署记录在 Markdown 表格中
- **Makefile 路由** — 如果项目有 `make deploy`，优先使用

## 架构

```
本地 (Claude Code)                    预览服务器
┌─────────────────────┐              ┌──────────────────────────┐
│  SKILL.md            │              │  deploy-preview.sh       │
│  (presentation skill)│              │                          │
│                      │              │  1. 创建站点目录          │
│  1. 检测项目类型      │              │  2. 写 Nginx vhost 配置  │
│  2. 本地构建          │   SCP        │  3. nginx -t && reload   │
│  3. 打包 dist/ ──────┼─────────────>│  4. acme.sh 签发证书     │
│  4. 调用部署脚本 ─────┼── SSH ──────>│  5. 更新 Nginx 加 HTTPS  │
│  5. 返回 URL 给用户   │              │  6. nginx reload         │
└─────────────────────┘              └──────────────────────────┘
```

## 环境要求

### 服务器端

- Linux 服务器，已安装 **Nginx**
- 已安装 **acme.sh**（用于 SSL 证书）
- 已配置 **通配符 DNS**：`*.your-domain.com` → 服务器 IP
- SSH 访问权限（密钥或密码）

### 本地端

- 已安装 [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- 前端 SPA 项目，包含 `package.json` 和 build 脚本

### 支持的项目类型

| 支持 | 不支持 |
|------|--------|
| Vite（React、Vue、Svelte 等） | Next.js（SSR 模式） |
| Create React App | Nuxt.js（SSR 模式） |
| Vue CLI | 任何服务端渲染应用 |
| 任何有构建步骤的静态 SPA | 后端服务 |

## 安装

### 方式一：克隆安装

```bash
git clone https://github.com/anthropics/presentation-skill.git
cd presentation-skill
# 复制 skill 文件到 Claude Code skills 目录
mkdir -p ~/.claude/skills/presentation
cp -r src/* ~/.claude/skills/presentation/
chmod +x ~/.claude/skills/presentation/scripts/deploy-preview.sh
```

### 方式二：手动创建

创建 skill 目录并添加文件：

```bash
mkdir -p ~/.claude/skills/presentation/scripts
```

将以下文件放置到 `~/.claude/skills/presentation/` 目录下：

```
~/.claude/skills/presentation/
├── SKILL.md              # Skill 定义（触发条件、执行流程）
├── config.md             # 服务器配置（init 时自动填充）
├── DEPLOYMENTS.md        # 部署历史记录
└── scripts/
    └── deploy-preview.sh # 服务端部署脚本
```

## 快速开始

### 第一步：初始化预览服务器

运行初始化命令配置服务器：

```
/presentation init
```

Claude 会询问以下信息：
- **服务器 IP** — 预览服务器的 IP 地址
- **基础域名** — 如 `preview.example.com`
- **SSH 用户名** — 默认：`root`
- **SSH 端口** — 默认：`22`

然后自动完成：
- 检测 Nginx 和 acme.sh 路径
- 创建服务器目录（`/opt/presentation`、`/var/www/previews` 等）
- 上传部署脚本
- 生成服务器端配置（`config.env`）
- 验证 Nginx 配置

### 第二步：部署项目

进入任意前端项目目录，执行：

```
/presentation
```

或使用自然语言：

> "部署一下"
> "deploy"
> "发布预览"

Claude 会构建并部署，然后返回 URL：

```
部署成功！

项目: my-app
URL: https://my-app.preview.example.com

部署记录已更新。
```

## 使用说明

### 命令

| 命令 | 说明 |
|------|------|
| `/presentation` | 部署当前项目到预览服务器 |
| `/presentation init` | 初始化预览服务器（首次使用） |

### 自然语言触发

| 语言 | 示例 |
|------|------|
| 英文 | "deploy", "deploy this project", "publish preview" |
| 中文 | "部署一下", "发布预览", "部署到预览服务器" |

### 自定义子域名

可以指定自定义子域名：

> "部署到预览，子域名叫 my-dashboard"

子域名生成优先级：**用户指定** > `package.json` 的 name 字段 > 目录名

### Makefile 集成

如果项目有 `Makefile` 且包含 `deploy` target，skill 会优先使用 `make deploy`，而非内置部署流程。适用于已有部署流程的项目。

## 配置说明

### config.md（本地）

位于 `~/.claude/skills/presentation/config.md`，由 `/presentation init` 自动填充。

```markdown
## 预览服务器
- IP: 203.0.113.10
- SSH User: root
- SSH Port: 22

## 域名
- base_domain: preview.example.com

## 服务器路径
- deploy_base_dir: /opt/presentation
- web_root: /var/www/previews
- nginx_conf_dir: /etc/nginx/conf.d/previews

## Nginx（init 时自动检测）
- nginx_bin: /usr/sbin/nginx
- nginx_reload_cmd: systemctl reload nginx
- nginx_include_ok: true

## SSL
- cert_tool: acme.sh
- acme_sh_path: /root/.acme.sh/acme.sh
```

### config.env（服务器端）

位于预览服务器的 `/opt/presentation/config.env`，由 `/presentation init` 生成。

```bash
WEB_ROOT=/var/www/previews
NGINX_CONF_DIR=/etc/nginx/conf.d/previews
NGINX_BIN=/usr/sbin/nginx
NGINX_RELOAD_CMD="systemctl reload nginx"
ACME_SH_PATH=/root/.acme.sh/acme.sh
```

## 部署历史

所有部署记录保存在 `~/.claude/skills/presentation/DEPLOYMENTS.md` 中：

| 项目名 | 子域名 | URL | 最后部署时间 | 状态 |
|--------|--------|-----|------------|------|
| my-app | my-app | https://my-app.preview.example.com | 2026-04-09 14:30 | OK |
| dashboard | dash | https://dash.preview.example.com | 2026-04-09 15:00 | OK |

## 工作原理

### 构建检测

Skill 自动检测构建配置：

1. **包管理器**：检查 `pnpm-lock.yaml` → `yarn.lock` → 回退到 `npm`
2. **构建命令**：从 `package.json` 的 `scripts.build` 读取，默认 `npm run build`
3. **输出目录**：检查 `dist/`，然后 `build/`

### 部署流程

```
1. 读取 config.md → 获取服务器和域名配置
2. 读取 package.json → 获取项目名和构建命令
3. 生成子域名
4. 本地执行构建（pnpm/yarn/npm）
5. 验证构建产物存在且非空
6. SCP 上传到服务器
7. SSH 执行 deploy-preview.sh
8. 解析结果 JSON
9. 更新 DEPLOYMENTS.md
10. 返回 URL 给用户
```

### 服务端脚本

`deploy-preview.sh` 在预览服务器上执行：

1. 创建站点目录
2. 生成 Nginx HTTP 虚拟主机配置
3. 测试并 reload Nginx
4. 通过 acme.sh 签发 SSL 证书
5. 更新 Nginx 配置加入 HTTPS（HTTP 301 重定向）
6. 再次测试并 reload Nginx

输出为 JSON 格式，便于解析：
- 成功：`{"status":"success","url":"https://..."}`
- 失败：`{"status":"error","message":"..."}`

## 错误处理

| 场景 | 处理方式 |
|------|---------|
| 没有 `package.json` | "当前目录不是前端项目，无法部署" |
| 构建失败 | 展示错误日志，中断部署 |
| 构建产物为空 | "构建产物为空，请检查构建配置" |
| SCP 上传失败 | "请检查服务器连接" |
| Nginx 配置冲突 | "子域名已被占用，请更换" |
| Nginx reload 失败 | 回滚配置文件，输出错误日志 |
| SSL 签发失败 | 以 HTTP 部署，提示证书问题 |
| 服务器连接失败 | "请检查 config.md 中的服务器信息" |

## 限制

- 仅支持静态 SPA — 不支持 SSR（Next.js、Nuxt.js 服务端渲染）
- 不支持后端服务部署
- 不做 CI/CD — 仅手动触发
- 不做灰度发布、版本回滚等高级部署功能
- DNS 需预先配置好通配符解析（`*.<base_domain>`）

## 项目结构

```
presentation-skill/
├── README.md                              # 英文文档
├── docs/
│   ├── README.zh-CN.md                    # 中文文档（本文件）
│   └── superpowers/
│       ├── specs/                         # 设计规格
│       └── plans/                         # 实现计划
└── src/                                   # Skill 源文件
    ├── SKILL.md                           # Skill 定义
    ├── config.md                          # 配置模板
    ├── DEPLOYMENTS.md                     # 部署历史
    └── scripts/
        └── deploy-preview.sh             # 服务端脚本
```

## 贡献

欢迎贡献代码！请随时提交 Pull Request。

## 许可证

MIT License

---

[presentation-skill](https://preview.juhebot.com) — 一键部署前端 SPA 项目。
