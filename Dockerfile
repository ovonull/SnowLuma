# SnowLuma 全功能镜像（noVNC 远程桌面 + Linux QQ + OneBot）
#
# 与旧版只打包 Node 产物的轻量镜像不同，这个镜像把上游桌面层一并打进来：
#   - Xvfb + fluxbox + x11vnc + noVNC 提供浏览器远程桌面（6081），用来扫二维码登录 QQ
#   - Linux QQ 本体（qq --no-sandbox）由 supervisord 拉起，SnowLuma 通过 Hook 注入管理
#   - SnowLuma 本体用 lite 发版包（不含 node，node 由基础镜像提供）
#
# 基础镜像必须是 Node 24：lite 包的 native 模块按 24.22.1+ 编译，跑在 node 22 会 ABI 报错。
FROM node:24-bookworm-slim

ARG SNOWLUMA_VERSION=v2.4.2
ARG SNOWLUMA_REPO=ovonull/SnowLuma
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    VNC_PASSWD=vncpasswd \
    TZ=Asia/Shanghai \
    SNOWLUMA_HOME=/app/snowluma \
    SNOWLUMA_DATA=/app/snowluma-data \
    SNOWLUMA_WEBUI_PORT=5099 \
    SNOWLUMA_WEBUI_HOST=0.0.0.0 \
    SNOWLUMA_LOG_LEVEL=info \
    SNOWLUMA_LOG_DIR=/app/snowluma-data/logs \
    SNOWLUMA_SCREEN=1920x1080x16 \
    SNOWLUMA_HOOK_AUTOLOAD=1 \
    SNOWLUMA_ACCEPT_EULA=1 \
    SNOWLUMA_ACCEPT_PRIVACY=1 \
    DISPLAY=:1

# 桌面 / VNC / QQ 运行所需的系统库与工具
RUN apt-get update && apt-get install -y --no-install-recommends \
      aria2 \
      ca-certificates \
      curl \
      dbus-user-session \
      ffmpeg \
      fluxbox \
      fonts-wqy-zenhei \
      git \
      gnutls-bin \
      libasound2 \
      libatspi2.0-0 \
      libgbm1 \
      libgtk-3-0 \
      libnotify4 \
      libnss3 \
      libsecret-1-0 \
      openbox \
      procps \
      supervisor \
      tzdata \
      unzip \
      x11vnc \
      xdg-utils \
      xorg \
      xvfb \
    && rm -rf /var/lib/apt/lists/*

# noVNC + websockify：浏览器远程桌面（6081）依赖，把 VNC(5900) 转成 websocket
RUN cd /opt \
    && git clone --depth=1 https://github.com/novnc/noVNC.git \
    && cd /opt/noVNC/utils && git clone --depth=1 https://github.com/novnc/websockify.git \
    && cp /opt/noVNC/vnc.html /opt/noVNC/index.html

# Linux QQ 本体（QQ 官方 CDN；证书问题用 --check-certificate=false 绕开）
# 这一步是构建里唯一的外网非 GitHub 依赖，CI 拉不到时整个镜像会构建失败。
ARG QQ_VERSION=3.2.28-48517
ARG QQ_CHANNEL=f9cbaab2
ARG QQ_BASE_URL=https://dldir1v6.qq.com/qqfile/qq/QQNT
RUN qq_arch="$(dpkg --print-architecture)" \
    && case "${qq_arch}" in \
         amd64|arm64) ;; \
         *) echo "Unsupported Debian architecture: ${qq_arch}" >&2; exit 1 ;; \
       esac \
    && apt-get update \
    && aria2c --check-certificate=false -x16 -s16 -o /tmp/linuxqq.deb \
         "${QQ_BASE_URL}/${QQ_CHANNEL}/linuxqq_${QQ_VERSION}_${qq_arch}.deb" \
    && (dpkg -i /tmp/linuxqq.deb || apt-get -f install -y --no-install-recommends) \
    && rm -f /tmp/linuxqq.deb \
    && chmod 777 /opt/QQ \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# SnowLuma lite 包（含 index.mjs + native 模块，不含 node；node 由基础镜像提供）
RUN ARCH=$([ "${TARGETARCH:-amd64}" = "arm64" ] && echo linux-arm64 || echo linux-x64) \
    && PKG="SnowLuma-${SNOWLUMA_VERSION}-${ARCH}-lite.tar.gz" \
    && curl -fSL -o /tmp/${PKG} \
         "https://github.com/${SNOWLUMA_REPO}/releases/download/${SNOWLUMA_VERSION}/${PKG}" \
    && mkdir -p "${SNOWLUMA_HOME}" \
    && tar -xzf /tmp/${PKG} -C "${SNOWLUMA_HOME}" \
    && test -f "${SNOWLUMA_HOME}/index.mjs" \
    && rm -f /tmp/${PKG}

COPY supervisord.conf /etc/supervisord.conf
COPY start.sh /root/start.sh
RUN chmod +x /root/start.sh \
    && groupadd --gid 1001 snowluma \
    && useradd --no-log-init --uid 1001 --gid 1001 --home-dir /app --shell /bin/bash snowluma \
    && mkdir -p "${SNOWLUMA_DATA}" /app/.cache /app/.config /app/.local/share \
    && chown -R snowluma:snowluma /app /opt/QQ

WORKDIR /app/snowluma-data

# 5900=原生 VNC(默认不映射也行) 6081=noVNC 5099=WebUI 3000=OneBot HTTP 3001=OneBot WS
EXPOSE 5900 6081 5099 3000 3001

VOLUME ["/app/snowluma-data", "/app/.config", "/app/.local/share"]

CMD ["/root/start.sh"]
