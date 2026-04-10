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
CONF_FILE="${NGINX_CONF_DIR}/preview-${SUBDOMAIN}.conf"
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
