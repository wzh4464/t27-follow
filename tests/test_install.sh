#!/bin/bash
# install.sh 的测试：装到临时目录，用假的 launchctl 记录调用，检查装出来的东西。
set -u
. "$(cd "$(dirname "$0")" && pwd)/helper.sh"

exists() { if [ -e "$1" ]; then echo yes; else echo no; fi; }

# 临时目录 $T 里放装出来的东西；$T/fake 是假显示器
# （卸载时脚本要把收起的屏放回去，不能让测试碰到真的 BetterDisplay）
new_world
T=$W

# 假 launchctl：记录调用。print（查询某个服务是否还在）一律答「不在」，其余一律成功
cat > "$T/launchctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$(dirname "$0")/launchctl.calls"
[ "$1" = "print" ] && exit 113
exit 0
EOF
chmod +x "$T/launchctl"
: > "$T/launchctl.calls"

PLIST="$T/agents/com.zihan.t27-follow.plist"
UID_NOW=$(id -u)

install_sh() {   # 参数前可带 K=V 形式的环境变量覆盖
  env T27_INSTALL_BIN_DIR="$T/bin" T27_INSTALL_AGENT_DIR="$T/agents" T27_INSTALL_LOG_DIR="$T/logs" \
      T27_LAUNCHCTL="$T/launchctl" T27_BD="$FAKE" FAKE_DIR="$T/fake" "$@"
}
plist_get() { plutil -extract "$1" raw "$PLIST" 2>/dev/null; }
calls()     { local n; n=$(grep -c -- "$1" "$T/launchctl.calls" 2>/dev/null); echo "${n:-0}"; }

echo "== 安装 =="
install_sh /bin/bash "$REPO/install.sh" > "$T/install.out" 2>&1; rc=$?
check "安装 → 返回 0" "0" "$rc"
check "安装 → 脚本装到目标目录" "yes" "$(exists "$T/bin/t27-follow.sh")"
check "安装 → 装上的脚本可执行" "yes" "$([ -x "$T/bin/t27-follow.sh" ] && echo yes || echo no)"
check "安装 → 装上的脚本与仓库里的一致" "yes" "$(cmp -s "$REPO/bin/t27-follow.sh" "$T/bin/t27-follow.sh" && echo yes || echo no)"
check "安装 → plist 格式合法" "0" "$(plutil -lint "$PLIST" > /dev/null 2>&1; echo $?)"
check "安装 → plist 标签" "com.zihan.t27-follow" "$(plist_get Label)"
check "安装 → 用系统自带 bash 启动" "/bin/bash" "$(plist_get ProgramArguments.0)"
check "安装 → 启动的是装好的那份脚本" "$T/bin/t27-follow.sh" "$(plist_get ProgramArguments.1)"
check "安装 → 以常驻循环方式运行" "run" "$(plist_get ProgramArguments.2)"
check "安装 → 登录后自动启动" "true" "$(plist_get RunAtLoad)"
check "安装 → 退出后自动拉起" "true" "$(plist_get KeepAlive)"
check "安装 → 默认本机输入是 15" "15" "$(plist_get EnvironmentVariables.T27_HOME_INPUT)"
check "安装 → 默认显示器名" "T27h-30" "$(plist_get EnvironmentVariables.T27_NAME)"
check "安装 → 日志目录交给脚本" "$T/logs" "$(plist_get EnvironmentVariables.T27_DIR)"
check "安装 → launchd 的输出也落在日志目录" "$T/logs/launchd.err" "$(plist_get StandardErrorPath)"
check "安装 → 日志目录已建好" "yes" "$(exists "$T/logs")"
check "安装 → 加载了 LaunchAgent" "1" "$(calls "^bootstrap gui/$UID_NOW $PLIST\$")"

echo "== 重复安装（更新）=="
: > "$T/launchctl.calls"
install_sh T27_HOME_INPUT=49 /bin/bash "$REPO/install.sh" > "$T/install.out" 2>&1; rc=$?
check "重复安装 → 返回 0" "0" "$rc"
check "重复安装 → 先卸掉旧的再加载" "bootout gui/$UID_NOW/com.zihan.t27-follow" "$(head -1 "$T/launchctl.calls")"
check "重复安装 → 重新加载" "1" "$(calls "^bootstrap gui/$UID_NOW $PLIST\$")"
check "重复安装 → 可以改本机输入编号" "49" "$(plist_get EnvironmentVariables.T27_HOME_INPUT)"

echo "== 卸载 =="
: > "$T/launchctl.calls"
echo "保留我" > "$T/logs/events.log"
# 假设卸载时屏正被本脚本收着（是主屏 22 的镜像）
echo on > "$T/fake/mirror"; echo 22 > "$T/fake/mirror_src"; echo 22 > "$T/logs/.mirrored-by-us"
install_sh /bin/bash "$REPO/install.sh" --uninstall > "$T/install.out" 2>&1; rc=$?
check "卸载 → 返回 0" "0" "$rc"
check "卸载 → 停掉 LaunchAgent" "1" "$(calls "^bootout gui/$UID_NOW/com.zihan.t27-follow\$")"
check "卸载 → 把收起的屏放回去" "off" "$(cat "$T/fake/mirror")"
check "卸载 → 不留下「由本脚本收起」的标记" "no" "$(exists "$T/logs/.mirrored-by-us")"
check "卸载 → 不留下暂停标记（否则重装后不工作）" "no" "$(exists "$T/logs/.paused")"
check "卸载 → 删掉 plist" "no" "$(exists "$PLIST")"
check "卸载 → 删掉装上的脚本" "no" "$(exists "$T/bin/t27-follow.sh")"
check "卸载 → 日志保留" "保留我" "$(head -1 "$T/logs/events.log" 2>/dev/null)"
check "卸载 → 不再加载任何东西" "0" "$(calls "^bootstrap ")"

finish
