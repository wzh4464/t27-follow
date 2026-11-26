#!/bin/bash
# t27-follow：让本机的显示布局跟随 T27h-30 的输入源。
#   显示器在本机输入上      → 它是正常的扩展屏
#   显示器在别的输入上      → 把它设成主屏的镜像，鼠标和窗口就去不了那里
# 执行引擎是 BetterDisplay（betterdisplaycli），本脚本只负责判断和下命令。
#
# 用法: t27-follow.sh [run|pause|resume|status]
#   run     常驻循环（默认，由 LaunchAgent 启动）
#   pause   暂停跟随，并把本脚本收起的屏放回去
#   resume  恢复跟随
#   status  显示当前读数、镜像状态、是否暂停
#
# 注意：bash 3.2 在 set -u 下会把紧跟变量名的中文当成变量名的一部分，
#       所以变量后面紧跟中文时一律写成 ${var}。
set -u

NAME="${T27_NAME:-T27h-30}"                     # 显示器在 BetterDisplay 里的名字
HOME_INPUT="${T27_HOME_INPUT:-15}"              # 本机所接的输入源编号（DP=15）
INTERVAL="${T27_INTERVAL:-2}"                   # 读数稳定时的轮询间隔（秒）
FAST_INTERVAL="${T27_FAST_INTERVAL:-0.5}"       # 读数刚变化或读不到时的轮询间隔（秒）
FAST_TICKS="${T27_FAST_TICKS:-20}"              # 最多连续加快多少次，之后退回正常间隔
CONFIRM="${T27_CONFIRM:-2}"                     # 同一读数连续出现几次才动作
RETRY_COOLDOWN="${T27_RETRY_COOLDOWN:-30}"      # 同一个动作没生效时，隔多少秒才再试（防止反复重配显示器）
FAIL_NOTE_AFTER="${T27_FAIL_NOTE_AFTER:-20}"    # 连续读不到多少次才记成一条状态（默认约 10 秒）
CMD_TIMEOUT="${T27_CMD_TIMEOUT:-5}"             # 单条 betterdisplaycli 命令最多等几秒（整数）
BD="${T27_BD:-/opt/homebrew/bin/betterdisplaycli}"
DIR="${T27_DIR:-$HOME/Library/Logs/t27-follow}"
LOG="$DIR/events.log"                           # 只记状态变化、动作和错误
LOG_MAX_BYTES="${T27_LOG_MAX_BYTES:-1048576}"   # 超过就把旧日志挪到 events.log.1
MARK="$DIR/.mirrored-by-us"                     # 存在 = 镜像是本脚本开的；内容 = 镜像源的 tagID
PAUSED="$DIR/.paused"                           # 存在 = 暂停跟随

LAST_STATE=""     # 上一次记进日志的状态
LAST_ERR=""       # 上一次记进日志的错误（相同的错误不重复记）
TRIED=""          # 最近一次尝试的动作：away / home
TRIED_AT=0        # 以及尝试的时刻

# ---------- 日志 ----------

log() {           # log <类别> <消息>
  local size
  if [ -f "$LOG" ]; then
    size=$(wc -c < "$LOG" | tr -d ' ')
    [ "$size" -gt "$LOG_MAX_BYTES" ] && mv -f "$LOG" "$LOG.1"
  fi
  printf '[%s] %-5s %s\n' "$(date '+%F %T')" "$1" "$2" >> "$LOG"
}

note_state() {    # 状态变了才记
  [ "$1" = "$LAST_STATE" ] && return 0
  LAST_STATE=$1
  log STATE "$1"
}

note_err() {      # 和上一条不同的错误才记
  [ "$1" = "$LAST_ERR" ] && return 0
  LAST_ERR=$1
  log ERR "$1"
}

# ---------- 与 BetterDisplay 交互 ----------

# 调用 betterdisplaycli，最多等 CMD_TIMEOUT 秒。
# 用 perl 的 alarm 做超时：闹钟在 exec 之后依然有效，到点命令会被 SIGALRM 结束，按失败处理。
bd() { /usr/bin/perl -e 'alarm shift; exec @ARGV or exit 127' "$CMD_TIMEOUT" "$BD" "$@" 2>&1; }

# 读当前输入源。成功：输出数字并返回 0；读不到：返回 1
read_input() {
  local out
  out=$(bd get -name="$NAME" -ddc -vcp=inputSelect) || return 1
  case "$out" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$out"
}

# 主屏的 tagID。这个选择器会连显示器组一起返回（如 "22,-1001"），取第一个正整数
main_tag() {
  local out t
  out=$(bd get -displayWithMainStatus -identifier=tagID) || return 1
  local IFS=,
  for t in $out; do
    case "$t" in ''|*[!0-9]*) ;; *) printf '%s' "$t"; return 0 ;; esac
  done
  return 1
}

# 显示器当前是否处于镜像：输出 on / off；读不到时输出别的内容
mirror_state() { bd get -name="$NAME" -mirror; }

# ---------- 动作 ----------

# 同一个动作刚试过且还在冷却期内？
cooling() { [ "$TRIED" = "$1" ] && [ $(( $(date +%s) - TRIED_AT )) -lt "$RETRY_COOLDOWN" ]; }
tried()   { TRIED=$1; TRIED_AT=$(date +%s); }

# 收起：把显示器设成主屏的镜像
put_away() {
  local m src self
  m=$(mirror_state)
  if [ "$m" = "on" ]; then TRIED=""; LAST_ERR=""; return 0; fi    # 已经是镜像（不管谁开的）
  [ "$m" = "off" ] || return 0                                    # 状态读不到：不动
  cooling away && return 0
  if ! src=$(main_tag); then note_err "找不到主屏，无法收起 ${NAME}"; return 0; fi
  self=$(bd get -name="$NAME" -identifier=tagID)
  if [ "$src" = "$self" ]; then note_err "${NAME} 自己是主屏，无法收起"; return 0; fi
  tried away
  if bd set -tagID="$src" -mirror=on -targetName="$NAME" > /dev/null; then
    printf '%s\n' "$src" > "$MARK"
    log ACT "收起：${NAME} 设为主屏(${src})的镜像"
  else
    note_err "开镜像的命令失败（主屏 ${src}）"
  fi
  return 0
}

# 放回：只关本脚本自己开的镜像，用户手动开的不碰
bring_back() {
  local m src
  [ -e "$MARK" ] || return 0
  m=$(mirror_state)
  if [ "$m" = "off" ]; then rm -f "$MARK"; TRIED=""; LAST_ERR=""; return 0; fi   # 镜像已经不在了
  [ "$m" = "on" ] || return 0                                                    # 状态读不到：不动
  cooling home && return 0
  src=$(cat "$MARK")
  tried home
  if bd set -tagID="$src" -mirror=off > /dev/null; then
    log ACT "放回：已关闭镜像，${NAME} 恢复为扩展屏"
    # 确认真的关掉了才清标记；没关掉就留着，冷却后再试
    [ "$(mirror_state)" = "off" ] && rm -f "$MARK"
  else
    note_err "关镜像的命令失败（镜像源 ${src}）"
  fi
  return 0
}

# ---------- 子命令 ----------

run() {
  local v last="" streak=0 fails=0 steady unsteady=0 fast
  mkdir -p "$DIR"
  # 加快时的间隔不能比正常间隔还长
  fast=$(awk -v f="$FAST_INTERVAL" -v i="$INTERVAL" 'BEGIN { print (f < i) ? f : i }')
  log START "显示器=${NAME} 本机输入=${HOME_INPUT} 间隔=${INTERVAL}s（变化时 ${fast}s）"
  trap 'log STOP "收到停止信号"; exit 0' INT TERM
  while true; do
    steady=0
    if [ -e "$PAUSED" ]; then
      # 暂停：不再跟随，并把自己收起的屏放回去
      note_state "已暂停"
      bring_back
      last=""; streak=0; fails=0
      steady=1
    elif v=$(read_input); then
      fails=0
      # 同一个读数连续出现 CONFIRM 次才算数（切换输入源的瞬间读数不可靠）
      if [ "$v" = "$last" ]; then streak=$((streak + 1)); else last=$v; streak=1; fi
      if [ "$streak" -ge "$CONFIRM" ]; then
        steady=1
        if [ "$v" = "$HOME_INPUT" ]; then
          note_state "在本机输入(${v})"
          bring_back
        else
          note_state "在别的输入(${v})"
          put_away
        fi
      fi
    else
      # 读不到：保持现状，并重新开始确认
      last=""; streak=0
      fails=$((fails + 1))
      if [ "$fails" -eq "$FAIL_NOTE_AFTER" ]; then
        note_state "读不到输入源（显示器休眠、掉线，或 BetterDisplay 没在运行）"
      fi
    fi
    # 读数稳定时按正常间隔读；刚变化或读不到时加快，好尽快确认。
    # 连续加快 FAST_TICKS 次还没稳定（比如显示器休眠了），就退回正常间隔。
    if [ "$steady" = 1 ]; then
      unsteady=0
      sleep "$INTERVAL"
    else
      unsteady=$((unsteady + 1))
      if [ "$unsteady" -le "$FAST_TICKS" ]; then sleep "$fast"; else sleep "$INTERVAL"; fi
    fi
  done
}

cmd_pause() {
  mkdir -p "$DIR"
  : > "$PAUSED"
  bring_back          # 守护进程没在跑时也能把屏放回
  echo "已暂停：不再跟随输入源，${NAME} 保持为普通扩展屏。恢复用: $(basename "$0") resume"
}

cmd_resume() {
  rm -f "$PAUSED"
  echo "已恢复跟随。"
}

cmd_status() {
  local v m
  if v=$(read_input); then
    if [ "$v" = "$HOME_INPUT" ]; then echo "输入源: ${v}（本机）"; else echo "输入源: ${v}（别的输入）"; fi
  else
    echo "输入源: 读不到（显示器休眠、掉线，或 BetterDisplay 没在运行）"
  fi
  m=$(mirror_state)
  case "$m" in on|off) ;; *) m="读不到" ;; esac
  echo "镜像: ${m}"
  if [ -e "$MARK" ]; then echo "由本脚本收起: 是"; else echo "由本脚本收起: 否"; fi
  if [ -e "$PAUSED" ]; then echo "暂停: 是"; else echo "暂停: 否"; fi
}

case "${1:-run}" in
  run)    run ;;
  pause)  cmd_pause ;;
  resume) cmd_resume ;;
  status) cmd_status ;;
  *)      echo "用法: $(basename "$0") [run|pause|resume|status]" >&2; exit 2 ;;
esac
