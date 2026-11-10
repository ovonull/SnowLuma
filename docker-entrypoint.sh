#!/usr/bin/env bash
# SnowLuma 容器入口：把程序初始化/同步到持久数据卷，再启动 launcher。
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"

if [ ! -f "$DATA_DIR/.snowluma-initialized" ]; then
  echo "[snowluma] 首次启动：初始化数据目录 $DATA_DIR"
  cp -a /opt/snowluma/. "$DATA_DIR/"
  touch "$DATA_DIR/.snowluma-initialized"
else
  # 升级：同步程序文件，排除用户数据（config / data / logs / tmp 等）。
  echo "[snowluma] 同步程序文件到 $DATA_DIR（保留用户数据）"
  rsync -a --delete \
    --exclude='config' --exclude='data' --exclude='logs' \
    --exclude='tmp' --exclude='.snowluma-initialized' \
    /opt/snowluma/ "$DATA_DIR/"
fi

cd "$DATA_DIR"
exec ./launcher.sh "$@"
