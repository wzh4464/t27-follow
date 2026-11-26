#!/bin/bash
# 变异检查：逐个往脚本的副本里埋一个 bug，确认测试会因此失败。
# 有变异体没被发现（测试照样全过），说明那段行为没被测试保护。
# 用法: tests/mutate.sh        （不属于日常测试，改了核心逻辑后手动跑一遍，约一两分钟）
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/bin/t27-follow.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

killed=0; survived=0; skipped=0

# mutant <说明> <perl 替换表达式>
mutant() {
  local desc=$1 expr=$2 m="$TMP/t27-follow.sh"
  cp "$SRC" "$m"
  /usr/bin/perl -0pi -e "$expr" "$m"
  if cmp -s "$SRC" "$m"; then
    skipped=$((skipped + 1)); printf '  跳过   %s（替换没有命中，脚本可能改过了）\n' "$desc"; return
  fi
  if ! /bin/bash -n "$m" 2>/dev/null; then
    skipped=$((skipped + 1)); printf '  跳过   %s（变异后语法不通）\n' "$desc"; return
  fi
  if T27_SUT="$m" /bin/bash "$REPO/tests/test_follow.sh" > "$TMP/out" 2>&1; then
    survived=$((survived + 1)); printf '  漏网   %s\n' "$desc"
  else
    killed=$((killed + 1)); printf '  发现   %s（%s 项失败）\n' "$desc" "$(grep -c '^  FAIL' "$TMP/out")"
  fi
}

mutant "去掉防抖：读到一次就动作"            's/-ge "\$CONFIRM"/-ge 1/'
mutant "把本机输入和别的输入判反"            's/if \[ "\$v" = "\$HOME_INPUT" \]; then\n/if [ "\$v" != "\$HOME_INPUT" ]; then\n/'
mutant "读取失败不重新开始确认"              's/\n      last=""; streak=0\n/\n      :\n/'
mutant "读回的不是数字也照单全收"            's/\n  case "\$out" in \x27\x27\|\*\[!0-9\]\*\) return 1 ;; esac\n/\n/'
mutant "收起前不看是否已是镜像"              's/  if \[ "\$m" = "on" \]; then TRIED=""; LAST_ERR=""; return 0; fi[^\n]*\n  \[ "\$m" = "off" \] \|\| return 0[^\n]*\n//'
mutant "收起后不记标记"                      's/    printf \x27%s\\n\x27 "\$src" > "\$MARK"\n//'
mutant "T27 自己是主屏也硬收"                's/  if \[ "\$src" = "\$self" \]; then[^\n]*\n//'
mutant "开镜像没成功也不冷却"                's/  cooling away && return 0\n//'
mutant "放回时不管镜像是谁开的"              's/  \[ -e "\$MARK" \] \|\| return 0\n  m=\$\(mirror_state\)/  m=\$(mirror_state)/'
mutant "放回时对着现在的主屏关而不是当初的镜像源" 's/  src=\$\(cat "\$MARK"\)\n/  src=\$(main_tag)\n/'
mutant "关镜像没成功也不冷却"                's/  cooling home && return 0\n//'
mutant "关掉镜像后不清标记"                  's/    \[ "\$\(mirror_state\)" = "off" \] && rm -f "\$MARK"\n//'
mutant "镜像已被别人关掉时不清标记"          's/then rm -f "\$MARK"; TRIED=""; LAST_ERR=""; return 0; fi/then TRIED=""; LAST_ERR=""; return 0; fi/'
mutant "暂停标记不起作用"                    's/if \[ -e "\$PAUSED" \]; then\n      # 暂停/if false; then\n      # 暂停/'
mutant "暂停时不把收起的屏放回"              's/      note_state "已暂停"\n      bring_back\n/      note_state "已暂停"\n/'
mutant "pause 命令不把收起的屏放回"          's/  bring_back          # 守护进程没在跑时也能把屏放回\n//'
mutant "状态不变也每次都记日志"              's/  \[ "\$1" = "\$LAST_STATE" \] && return 0\n//'
mutant "相同的错误每次都记日志"              's/  \[ "\$1" = "\$LAST_ERR" \] && return 0\n//'
mutant "读不到一次就记成状态变化"            's/-eq "\$FAIL_NOTE_AFTER"/-eq 1/'
mutant "日志不轮转"                          's/    \[ "\$size" -gt "\$LOG_MAX_BYTES" \] && mv -f "\$LOG" "\$LOG.1"\n//'
mutant "命令没有超时保护"                    's/bd\(\) \{ \/usr\/bin\/perl[^\n]*\n/bd() { "\$BD" "\$@" 2>&1; }\n/'
mutant "读数刚变化时不加快轮询"              's/if \[ "\$unsteady" -le "\$FAST_TICKS" \]; then sleep "\$fast"; else sleep "\$INTERVAL"; fi/sleep "\$INTERVAL"/'
mutant "一直读不到也不退回正常间隔"          's/if \[ "\$unsteady" -le "\$FAST_TICKS" \]; then sleep "\$fast"; else sleep "\$INTERVAL"; fi/sleep "\$fast"/'
mutant "稳定下来后不清零加快次数"            's/\n      unsteady=0\n/\n      :\n/'
mutant "加快间隔比正常间隔还长也照用"        's/  fast=\$\(awk[^\n]*\n/  fast=\$FAST_INTERVAL\n/'

echo
printf '变异体：发现 %d，漏网 %d，跳过 %d\n' "$killed" "$survived" "$skipped"
[ "$survived" -eq 0 ] && [ "$skipped" -eq 0 ]
