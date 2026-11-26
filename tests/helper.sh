#!/bin/bash
# 测试工具：建假环境、按脚本读数跑真实的守护循环、取结果。被各 test_*.sh source。

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="${T27_SUT:-$REPO/bin/t27-follow.sh}"     # 可指向一份改动过的副本，用来做变异检查（见 tests/mutate.sh）
FAKE="$REPO/tests/fake-betterdisplaycli"

PASS=0; FAIL=0
W=""; DPID=""
WORLDS=()

ok()    { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()   { FAIL=$((FAIL + 1)); printf '  FAIL %s (期望 %s, 实际 %s)\n' "$1" "$2" "$3"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }

finish() {
  printf '%s: 通过 %d, 失败 %d\n' "$(basename "$0")" "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}

# 建一个干净的假环境：$W/fake 是假显示器的状态，$W/state 是脚本自己的日志与状态目录。
# 初始：T27h-30(tagID 19) 是扩展屏，主屏是 tagID 22。
new_world() {
  W=$(mktemp -d)
  WORLDS+=("$W")
  mkdir -p "$W/fake" "$W/state"
  echo off > "$W/fake/mirror"
  echo 22 > "$W/fake/main_tag"
  echo 19 > "$W/fake/t27_tag"
  echo 0 > "$W/fake/pos"
  echo 0 > "$W/fake/extra"
  : > "$W/fake/readings"
  : > "$W/fake/calls"
}

# 假设之前已由本脚本把 T27 收成了主屏(22)的镜像
given_put_away_by_us() {
  echo on > "$W/fake/mirror"; echo 22 > "$W/fake/mirror_src"
  echo 22 > "$W/state/.mirrored-by-us"
}

# 假设用户自己手动开了镜像（没有本脚本的标记）
given_manual_mirror() {
  echo on > "$W/fake/mirror"; echo 22 > "$W/fake/mirror_src"
}

# 以脚本身份运行一条子命令（参数前可带 K=V 形式的环境变量覆盖）。
# 读数脚本读完后假显示器会一直读取失败，为了不让「持续读不到」那条状态
# 随测试收尾的快慢时有时无，默认把它的门槛调得很高；专门测它的用例自己覆盖。
sut_env() {
  SUT_ENV=(FAKE_DIR="$W/fake" T27_BD="$FAKE" T27_DIR="$W/state" T27_INTERVAL=0.02 T27_FAIL_NOTE_AFTER=1000)
}

sut() {
  sut_env
  env "${SUT_ENV[@]}" "$@"
}

start_daemon() {   # 参数：额外的环境变量 K=V ...
  sut_env
  # 必须 exec：这样 $! 才是守护进程本身。否则 $! 只是外层子 shell，
  # 杀掉它会让真正的守护进程变成孤儿一直空转（曾因此留下几百个进程）。
  ( exec env "${SUT_ENV[@]}" "$@" /bin/bash "$SUT" run ) > "$W/out" 2>&1 &
  DPID=$!
}

stop_daemon() {
  [ -n "$DPID" ] || return 0
  kill "$DPID" 2>/dev/null
  wait "$DPID" 2>/dev/null
  DPID=""
}

# 本仓库的守护进程此刻还有几个在跑（装到 ~/bin 的正式那份路径不同，不会被算进来）
leftover_daemons() { pgrep -f "$SUT run" | wc -l | tr -d ' '; }

# wait_until <秒> <命令...>：条件成立返回 0，超时返回 1
wait_until() {
  local deadline=$(( $(date +%s) + $1 )); shift
  until "$@"; do
    [ "$(date +%s)" -ge "$deadline" ] && return 1
    sleep 0.02
  done
}

script_done()         { [ "$(cat "$W/fake/extra")" -ge 1 ]; }
daemon_gone()         { ! kill -0 "$DPID" 2>/dev/null; }
script_done_or_dead() { script_done || daemon_gone; }

# play [K=V ...] -- 读数...
# 让假显示器依次给出这些读数，跑守护循环直到读数被读完（之后的读取一律失败），再停掉。
play() {
  local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  printf '%s\n' "$@" > "$W/fake/readings"
  echo 0 > "$W/fake/pos"; echo 0 > "$W/fake/extra"
  start_daemon ${envs[@]+"${envs[@]}"}
  wait_until 15 script_done_or_dead
  if ! script_done; then
    if daemon_gone; then bad "守护循环读完全部读数" "读完" "守护进程提前退出: $(head -1 "$W/out")"
    else bad "守护循环读完全部读数" "读完" "超时未读完"; fi
  fi
  stop_daemon
}

# ---- 取结果 ----
mirror()     { cat "$W/fake/mirror"; }
paused()     { if [ -e "$W/state/.paused" ]; then echo yes; else echo no; fi; }
mirror_src() { cat "$W/fake/mirror_src" 2>/dev/null || echo "(无)"; }
mark()       { if [ -e "$W/state/.mirrored-by-us" ]; then cat "$W/state/.mirrored-by-us"; else echo "(无)"; fi; }
mark_is()    { [ "$(mark)" = "$1" ]; }
unexpected() { if [ -e "$W/fake/unexpected" ]; then cat "$W/fake/unexpected"; else echo "(无)"; fi; }
set_calls()  { local n; n=$(grep -c '^set ' "$W/fake/calls" 2>/dev/null); echo "${n:-0}"; }   # 发出的「改配置」命令数
log_lines()  { local n; n=$(grep -c -- "$1" "$W/state/events.log" 2>/dev/null); echo "${n:-0}"; }

# 第 $1 次与第 $2 次「读输入源」之间隔了多少秒（需要先建 $W/fake/stamp）；读取次数不够时输出 -1
read_gap() {
  awk -v a="$1" -v b="$2" 'NR == a { x = $1 } NR == b { y = $1; ok = 1 } END { if (ok) printf "%.3f", y - x; else printf "-1" }' \
    "$W/fake/read_times" 2>/dev/null
}
less_than() { awk -v x="$1" -v y="$2" 'BEGIN { if (x >= 0 && x < y) print "yes"; else print "no (" x "s)" }'; }
at_least()  { awk -v x="$1" -v y="$2" 'BEGIN { if (x >= y) print "yes"; else print "no (" x "s)" }'; }

cleanup_worlds() {
  stop_daemon
  local w
  # 守护进程被停掉的瞬间，它刚拉起的假命令可能还在往目录里写，所以删不掉就稍等再删一次
  for w in ${WORLDS[@]+"${WORLDS[@]}"}; do
    rm -rf "$w" 2>/dev/null || { sleep 0.2; rm -rf "$w"; }
  done
}
trap cleanup_worlds EXIT
