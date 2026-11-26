#!/bin/bash
# t27-follow 的行为测试：用假的 betterdisplaycli 模拟显示器，跑真实的守护循环。
set -u
. "$(cd "$(dirname "$0")" && pwd)/helper.sh"

echo "== 收起：显示器切到别的输入 =="
new_world
play -- 17 17
check "连续两次读到别的输入 → T27 成为镜像" "on" "$(mirror)"
check "镜像源是主屏(22)" "22" "$(mirror_src)"
check "记下是本脚本收起的，以及镜像源" "22" "$(mark)"
check "没有发出不该发的命令" "(无)" "$(unexpected)"

new_world
play -- 15 17 15 15
check "只读到一次别的输入 → 不发任何改配置的命令" "0" "$(set_calls)"
check "只读到一次别的输入 → 仍是扩展屏" "off" "$(mirror)"

echo "== 放回：显示器切回本机输入 =="
new_world; given_put_away_by_us
play -- 15 15
check "连续两次读到本机输入 → 关掉自己开的镜像" "off" "$(mirror)"
check "放回后清掉标记" "(无)" "$(mark)"
check "放回时没有发出不该发的命令" "(无)" "$(unexpected)"

new_world; given_manual_mirror
play -- 15 15 15
check "用户手动开的镜像 → 不去关" "on" "$(mirror)"
check "用户手动开的镜像 → 不发任何改配置的命令" "0" "$(set_calls)"

new_world; given_put_away_by_us; echo 21 > "$W/fake/main_tag"
play -- 15 15
check "收起之后主屏换了别的屏 → 仍对着当初的镜像源关，能放回" "off" "$(mirror)"

echo "== 稳定性 =="
new_world
play -- abc abc abc
check "读回来的不是数字 → 当作读不到，不动作" "0" "$(set_calls)"

new_world
play -- 17 Failed 17
check "读取失败会打断确认 → 不收起" "off" "$(mirror)"

new_world
play -- 17 17 17 17 17
check "已经收起后 → 不重复下命令" "1" "$(set_calls)"

new_world
play -- 17 17 49 49
check "在两个别的输入之间换 → 仍保持收起" "on" "$(mirror)"
check "在两个别的输入之间换 → 不重复下命令" "1" "$(set_calls)"

new_world; given_put_away_by_us
play -- Failed Failed Failed
check "一直读不到 → 保持收起状态" "on" "$(mirror)"
check "一直读不到 → 不发任何改配置的命令" "0" "$(set_calls)"

new_world; given_put_away_by_us
play -- 17 17 15 15 17 17
check "切走→切回→再切走 → 最终是收起" "on" "$(mirror)"
check "切走→切回→再切走 → 标记仍在" "22" "$(mark)"
check "切走→切回→再切走 → 只发了关和开两条命令" "2" "$(set_calls)"

echo "== 暂停 =="
new_world; : > "$W/state/.paused"
printf '%s\n' 17 17 17 17 > "$W/fake/readings"
start_daemon; sleep 0.5; stop_daemon
check "暂停期间 → 不收起" "off" "$(mirror)"
check "暂停期间 → 不发任何改配置的命令" "0" "$(set_calls)"

new_world; given_put_away_by_us; : > "$W/state/.paused"
# 等到标记被清掉再停：关镜像和清标记是先后两步，只等镜像关掉就停会掐在两步之间
start_daemon; wait_until 5 mark_is "(无)"; stop_daemon
check "暂停期间 → 守护进程把自己收起的屏放回" "off" "$(mirror)"
check "暂停期间 → 放回后清掉标记" "(无)" "$(mark)"

new_world; given_put_away_by_us
sut /bin/bash "$SUT" pause > /dev/null; rc=$?
check "pause 命令 → 返回 0" "0" "$rc"
check "pause 命令（守护进程没在跑）→ 把自己收起的屏放回" "off" "$(mirror)"
check "pause 命令 → 留下暂停标记" "yes" "$(paused)"
sut /bin/bash "$SUT" resume > /dev/null; rc=$?
check "resume 命令 → 返回 0" "0" "$rc"
check "resume 命令 → 去掉暂停标记" "no" "$(paused)"
play -- 17 17
check "resume 之后 → 恢复跟随" "on" "$(mirror)"

new_world; given_manual_mirror
sut /bin/bash "$SUT" pause > /dev/null
check "pause 命令 → 不碰用户手动开的镜像" "on" "$(mirror)"

echo "== status =="
new_world; given_put_away_by_us
printf '%s\n' 17 > "$W/fake/readings"
out=$(sut /bin/bash "$SUT" status); rc=$?
check "status → 返回 0" "0" "$rc"
check "status → 报出当前输入源读数" "1" "$(printf '%s\n' "$out" | grep -c '^输入源: 17')"
check "status → 报出镜像状态" "1" "$(printf '%s\n' "$out" | grep -c '^镜像: on')"
check "status → 报出是本脚本收起的" "1" "$(printf '%s\n' "$out" | grep -c '^由本脚本收起: 是')"
check "status → 报出未暂停" "1" "$(printf '%s\n' "$out" | grep -c '^暂停: 否')"
check "status → 不改动任何配置" "0" "$(set_calls)"

new_world; : > "$W/state/.paused"
out=$(sut /bin/bash "$SUT" status)
check "status → 读不到时如实报告" "1" "$(printf '%s\n' "$out" | grep -c '^输入源: 读不到')"
check "status → 报出已暂停" "1" "$(printf '%s\n' "$out" | grep -c '^暂停: 是')"
check "status → 报出不是本脚本收起的" "1" "$(printf '%s\n' "$out" | grep -c '^由本脚本收起: 否')"

new_world; echo "Failed." > "$W/fake/mirror"     # 显示器不在线时，真机对镜像状态的回答就是 Failed.
out=$(sut /bin/bash "$SUT" status)
check "status → 镜像状态读不到时说人话，不把 Failed. 原样甩出来" "1" "$(printf '%s\n' "$out" | grep -c '^镜像: 读不到')"

echo "== 出错与边界 =="
new_world; echo 19 > "$W/fake/main_tag"
play -- 17 17 17 17
check "T27 自己是主屏 → 不收起" "off" "$(mirror)"
check "T27 自己是主屏 → 不发任何改配置的命令" "0" "$(set_calls)"
check "T27 自己是主屏 → 错误只记一条" "1" "$(log_lines ' ERR ')"

new_world; : > "$W/fake/main_tag"
play -- 17 17 17
check "找不到主屏 → 不发任何改配置的命令" "0" "$(set_calls)"
check "找不到主屏 → 错误只记一条" "1" "$(log_lines ' ERR ')"

new_world; : > "$W/fake/set_fails"
play -- 17 17 17 17 17 17
check "开镜像失败 → 不留标记" "(无)" "$(mark)"
check "开镜像失败 → 冷却期内只试一次" "1" "$(set_calls)"
check "开镜像失败 → 错误只记一条" "1" "$(log_lines ' ERR ')"

new_world; : > "$W/fake/set_fails"
play T27_RETRY_COOLDOWN=0 -- 17 17 17 17 17 17
check "开镜像失败且冷却为 0 → 每个周期都重试" "5" "$(set_calls)"
check "开镜像失败且冷却为 0 → 同样的错误仍只记一条" "1" "$(log_lines ' ERR ')"

new_world; : > "$W/fake/set_noop"
play -- 17 17 17 17 17 17
check "开镜像返回成功却没生效 → 冷却期内不反复重发" "1" "$(set_calls)"

new_world
play -- 17 17 17 unplugged Failed 17 17
check "收起后掉线重连、镜像被系统取消 → 重新收起" "on" "$(mirror)"
check "收起后掉线重连 → 一共发了两次开镜像" "2" "$(set_calls)"

new_world; given_put_away_by_us; : > "$W/fake/set_fails"
play -- 15 15 15 15
check "关镜像失败 → 标记保留（之后还会再试）" "22" "$(mark)"
check "关镜像失败 → 冷却期内只试一次" "1" "$(set_calls)"
check "关镜像失败 → 错误只记一条" "1" "$(log_lines ' ERR ')"

new_world; given_put_away_by_us; echo off > "$W/fake/mirror"
play -- 15 15
check "标记还在但镜像已被别人关掉 → 清掉标记" "(无)" "$(mark)"
check "标记还在但镜像已被别人关掉 → 不发命令" "0" "$(set_calls)"

echo "== 日志 =="
new_world
play -- 15 15 15 15 15 15 15 15
check "状态不变 → 状态只记一条" "1" "$(log_lines ' STATE ')"

new_world
play -- 15 15 17 17 17 15 15 15
check "本机→别的输入→本机 → 状态记三条" "3" "$(log_lines ' STATE ')"
check "本机→别的输入→本机 → 收起和放回各记一条动作" "2" "$(log_lines ' ACT ')"

new_world
play -- 15 15 Failed 15 15 Failed 15 15
check "偶尔读失败一次 → 不记成状态变化" "1" "$(log_lines ' STATE ')"

new_world
play T27_FAIL_NOTE_AFTER=5 -- 15 15 Failed Failed Failed Failed Failed Failed Failed
check "持续读不到（连续 5 次）→ 多记一条状态" "2" "$(log_lines ' STATE ')"

new_world
play T27_FAIL_NOTE_AFTER=5 -- 15 15 Failed Failed Failed Failed 15 15
check "连续读不到没到 5 次就恢复 → 不记" "1" "$(log_lines ' STATE ')"

new_world
head -c 5000 /dev/zero | tr '\0' 'x' > "$W/state/events.log"
play T27_LOG_MAX_BYTES=2000 -- 15 15
check "日志超过上限 → 旧日志挪到 events.log.1" "yes" "$([ -s "$W/state/events.log.1" ] && echo yes || echo no)"
check "日志超过上限 → 新日志从头写起（小于上限）" "yes" "$([ "$(wc -c < "$W/state/events.log" | tr -d ' ')" -lt 2000 ] && echo yes || echo no)"
check "日志超过上限 → 新日志里有本次的状态" "1" "$(log_lines ' STATE ')"

echo "== 命令卡住 =="
new_world
play T27_CMD_TIMEOUT=1 -- hang 17 17
check "读输入源的命令卡住不返回 → 超时后继续工作并正常收起" "on" "$(mirror)"

echo "== 轮询快慢 =="
# 正常间隔设成 1 秒、加快时 0.02 秒，用假显示器记下的读取时刻来判断
new_world; : > "$W/fake/stamp"
play T27_INTERVAL=1 T27_FAST_INTERVAL=0.02 -- 15 15 17 17
check "读数稳定时按正常间隔读（第 2、3 次读取相隔不少于 0.9 秒）" "yes" "$(at_least "$(read_gap 2 3)" 0.9)"
check "读数刚变时加快确认（第 3、4 次读取相隔不到 0.5 秒）" "yes" "$(less_than "$(read_gap 3 4)" 0.5)"

new_world; : > "$W/fake/stamp"
play T27_INTERVAL=1 T27_FAST_INTERVAL=0.02 T27_FAST_TICKS=3 -- Failed Failed Failed Failed Failed
check "刚开始读不到时加快重试（第 1、2 次读取相隔不到 0.5 秒）" "yes" "$(less_than "$(read_gap 1 2)" 0.5)"
check "一直读不到就退回正常间隔（第 4、5 次读取相隔不少于 0.9 秒）" "yes" "$(at_least "$(read_gap 4 5)" 0.9)"

new_world; : > "$W/fake/stamp"
play T27_INTERVAL=0.05 T27_FAST_INTERVAL=1 -- 15 17 15 17
check "加快间隔设得比正常间隔还长时不采用（第 1、2 次读取相隔不到 0.5 秒）" "yes" "$(less_than "$(read_gap 1 2)" 0.5)"

new_world; : > "$W/fake/stamp"
play T27_INTERVAL=1 T27_FAST_INTERVAL=0.02 T27_FAST_TICKS=3 -- 15 15 17 17 15 15 17 17
check "来回切了好几次之后，新的变化照样加快确认（第 7、8 次读取相隔不到 0.5 秒）" "yes" "$(less_than "$(read_gap 7 8)" 0.5)"

echo "== 测试自身的收尾 =="
check "测试结束后没有遗留的守护进程" "0" "$(leftover_daemons)"

finish
