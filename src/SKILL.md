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
部署成功！

项目: <project-name>
URL: https://<subdomain>.<base_domain>

部署记录已更新。
```

**失败：**
```
部署失败

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
