#!/usr/bin/env bash
# install.sh — 安装 / 更新 / 卸载 t27-follow。不需要 sudo，可重复执行。
#   ./install.sh               安装或更新，并（重新）加载 LaunchAgent
#   ./install.sh --uninstall   停止并卸载（日志保留）
# 可用环境变量改默认值。例如本机改接显示器的 USB-C 口之后：
#   T27_HOME_INPUT=49 ./install.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.zihan.t27-follow"
BIN_DIR="${T27_INSTALL_BIN_DIR:-$HOME/bin}"
AGENT_DIR="${T27_INSTALL_AGENT_DIR:-$HOME/Library/LaunchAgents}"
LOG_DIR="${T27_INSTALL_LOG_DIR:-$HOME/Library/Logs/t27-follow}"
LAUNCHCTL="${T27_LAUNCHCTL:-/bin/launchctl}"
NAME="${T27_NAME:-T27h-30}"             # 显示器在 BetterDisplay 里的名字
HOME_INPUT="${T27_HOME_INPUT:-15}"      # 本机所接的输入源编号
INTERVAL="${T27_INTERVAL:-2}"           # 轮询间隔（秒）

SCRIPT="$BIN_DIR/t27-follow.sh"
PLIST="$AGENT_DIR/$LABEL.plist"
DOMAIN="gui/$(id -u)"

# 卸掉正在跑的服务，并等它真的退出（否则紧接着加载会失败）
unload() {
  local i
  "$LAUNCHCTL" bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    "$LAUNCHCTL" print "$DOMAIN/$LABEL" > /dev/null 2>&1 || return 0
    sleep 0.25
  done
}

if [ "${1:-}" = "--uninstall" ]; then
  unload
  if [ -f "$SCRIPT" ]; then
    # 服务停了就没人管那块屏了：如果它正被收着，先放回去（pause 会放回，resume 再去掉暂停标记）
    T27_DIR="$LOG_DIR" T27_NAME="$NAME" /bin/bash "$SCRIPT" pause  > /dev/null 2>&1 || true
    T27_DIR="$LOG_DIR" T27_NAME="$NAME" /bin/bash "$SCRIPT" resume > /dev/null 2>&1 || true
  fi
  rm -f "$PLIST" "$SCRIPT"
  echo "[*] 已卸载 ${LABEL}（日志保留在 ${LOG_DIR}）"
  exit 0
fi

mkdir -p "$BIN_DIR" "$AGENT_DIR" "$LOG_DIR"
install -m 0755 "$REPO_DIR/bin/t27-follow.sh" "$SCRIPT"
sed -e "s|__SCRIPT__|$SCRIPT|g" -e "s|__LOG_DIR__|$LOG_DIR|g" -e "s|__NAME__|$NAME|g" \
    -e "s|__HOME_INPUT__|$HOME_INPUT|g" -e "s|__INTERVAL__|$INTERVAL|g" \
    "$REPO_DIR/launchd/$LABEL.plist.tmpl" > "$PLIST"

unload
"$LAUNCHCTL" bootstrap "$DOMAIN" "$PLIST" || { sleep 1; "$LAUNCHCTL" bootstrap "$DOMAIN" "$PLIST"; }

echo "[*] 已安装并启动 ${LABEL}"
echo "    显示器: ${NAME}    本机输入: ${HOME_INPUT}    轮询间隔: ${INTERVAL}s"
echo "    脚本:   ${SCRIPT}"
echo "    日志:   ${LOG_DIR}/events.log"
echo "    查看状态: ${SCRIPT} status      暂停/恢复: ${SCRIPT} pause | resume"
