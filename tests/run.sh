#!/usr/bin/env bash
# 跑全部测试：bash -n 语法检查 + shellcheck（若有）+ 各 test_*.sh。
set -uo pipefail
cd "$(dirname "$0")/.."

rc=0

echo "== bash -n 语法检查 =="
for f in bin/* install.sh tests/*.sh tests/fake-betterdisplaycli; do
  [ -e "$f" ] || continue
  if /bin/bash -n "$f" 2>/dev/null; then echo "  ok  $f"; else echo "  ERR $f"; rc=1; fi
done

if command -v shellcheck >/dev/null 2>&1; then
  echo "== shellcheck =="
  files=()
  for f in bin/* install.sh; do [ -e "$f" ] && files+=("$f"); done
  if [ "${#files[@]}" -gt 0 ]; then shellcheck -S warning "${files[@]}" || rc=1; fi
else
  echo "== shellcheck 未安装，跳过 =="
fi

echo "== 测试 =="
for t in tests/test_*.sh; do
  if /bin/bash "$t"; then echo "  ok  $t"; else echo "  FAIL $t"; rc=1; fi
done

[ "$rc" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $rc
