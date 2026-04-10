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
- nginx_conf_dir: /etc/nginx/conf.d

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
