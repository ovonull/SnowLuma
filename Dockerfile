# SnowLuma 私有镜像
# 基于你的发版包（Linux x64 完整版，内置 Node.js）构建，不依赖上游的 CI 跨仓库构建。
FROM ubuntu:24.04

# 版本与来源：默认用你 fork 的 v2.4.2 发版包。换版本/仓库/架构时改这里或 build 时传 --build-arg。
ARG SNOWLUMA_VERSION=v2.4.2
ARG SNOWLUMA_REPO=ovonull/SnowLuma

ENV DEBIAN_FRONTEND=noninteractive

# 系统库：ca-certificates 用于下载与 HTTPS；其余为常见 native 模块运行依赖。
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    rsync \
    bash \
    libnss3 \
    libssl3 \
    libstdc++6 \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

# 按目标架构选包：buildx 注入 TARGETARCH（amd64/arm64），对应 linux-x64 / linux-arm64。
# 国内下载慢时，把对应 SnowLuma-<tag>-<arch>.tar.gz 放进 build 上下文并改用 COPY。
RUN ARCH=$([ "${TARGETARCH:-amd64}" = "arm64" ] && echo linux-arm64 || echo linux-x64) \
    && PKG="SnowLuma-${SNOWLUMA_VERSION}-${ARCH}.tar.gz" \
    && curl -fSL -o /tmp/${PKG} \
       "https://github.com/${SNOWLUMA_REPO}/releases/download/${SNOWLUMA_VERSION}/${PKG}" \
    && mkdir -p /opt/snowluma \
    && tar -xzf /tmp/${PKG} -C /opt/snowluma \
    && chmod +x /opt/snowluma/launcher.sh /opt/snowluma/node \
    && rm -f /tmp/${PKG}

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# 数据卷：首次启动把 /opt/snowluma 复制到 /data 并在此运行；升级镜像时 rsync 同步程序、保留用户数据。
VOLUME ["/data"]
WORKDIR /data

# 容器外访问 WebUI 必须监听 0.0.0.0；无人值守部署自动确认协议；日志落到数据卷内。
ENV SNOWLUMA_WEBUI_HOST=0.0.0.0
ENV SNOWLUMA_ACCEPT_EULA=1
ENV SNOWLUMA_ACCEPT_PRIVACY=1
ENV SNOWLUMA_LOG_DIR=/data/logs

EXPOSE 5099

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD []
