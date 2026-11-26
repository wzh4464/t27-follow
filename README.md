# t27-follow

让本机的显示布局跟随 T27h-30 的输入源：

- 显示器在**本机输入**（DP，编号 15）上：它是正常的扩展屏。
- 显示器在**别的输入**上（给另一台机器用）：把它设成主屏的镜像。这样鼠标和窗口都去不了那块看不见的屏。
- 切回本机后自动关掉镜像，方向、分辨率、HiDPI、位置和原来在那块屏上的窗口都会恢复。

执行引擎是 BetterDisplay，本工具只是一个轮询脚本加一个 LaunchAgent，通过 `betterdisplaycli` 读输入源、开关镜像。BetterDisplay 平时怎么用都不受影响。

## 安装

```sh
./install.sh               # 安装或更新，并启动
./install.sh --uninstall   # 停止并卸载（日志保留；如果屏正被收着，会先放回去）
```

不需要 sudo。装完之后：

| 东西 | 位置 |
|---|---|
| 脚本 | `~/bin/t27-follow.sh` |
| LaunchAgent | `~/Library/LaunchAgents/com.zihan.t27-follow.plist` |
| 日志 | `~/Library/Logs/t27-follow/events.log`（只记状态变化、动作和错误，超过 1 MB 轮转一次） |

前提：BetterDisplay 在运行（Pro），已装 `betterdisplaycli`（`brew install waydabber/betterdisplay/betterdisplaycli`）。

## 日常使用

```sh
~/bin/t27-follow.sh status   # 当前读数、镜像状态、是否暂停
~/bin/t27-follow.sh pause    # 暂停跟随，并把收起的屏放回去
~/bin/t27-follow.sh resume   # 恢复跟随
```

想临时把 T27h-30 当普通扩展屏用（比如显示器在别的输入上，但你就是要往上面放窗口），先 `pause`。

## 行为细节

- 稳定时每 2 秒读一次输入源；读数刚变化或读不到时改成每 0.5 秒读一次，最多加快 20 次。
- 同一个读数连续出现两次才动作。切换输入源后的几秒内显示器答不上来，这段时间保持现状。
- 实测从切换到生效要 3 到 6 秒：显示器切换后有三四秒答不稳，脚本省不掉这段。切回本机后的这几秒里，T27h-30 上显示的是主屏的镜像。
- 实测只在合盖（P27q-30 加 T27h-30 两块屏）的状态下做过，开盖三屏没有实测。
- 读不到输入源（显示器休眠、掉线、BetterDisplay 没运行）时什么都不做。显示器休眠时系统本来就不把它算作屏幕。
- 只关自己开的镜像：你手动开的镜像它不会碰。判断依据是日志目录里的 `.mirrored-by-us`。
- 某个动作没生效时，30 秒内不重复尝试，避免反复重配显示器造成闪屏。
- T27h-30 自己是主屏时无法收起，只在日志里记一条错误。

## 改配置

改默认值就带着环境变量重新安装，它们会写进 LaunchAgent：

```sh
T27_HOME_INPUT=49 ./install.sh      # 本机改接显示器的 USB-C 口之后
T27_NAME="别的名字" ./install.sh     # 显示器在 BetterDisplay 里改了名字之后
```

| 变量 | 默认 | 含义 |
|---|---|---|
| `T27_NAME` | `T27h-30` | 显示器在 BetterDisplay 里的名字 |
| `T27_HOME_INPUT` | `15` | 本机所接的输入源编号（T27h-30：15 = DP，17 = HDMI，49 = USB-C） |
| `T27_INTERVAL` | `2` | 稳定时的轮询间隔（秒） |

其余可调项见 `bin/t27-follow.sh` 开头。

## 已知限制

- 只管 T27h-30。P27q-30 经 HDMI 转接，读不到输入源，这个办法对它不适用。
- 依赖显示器在别的输入上时仍肯通过 DP 回答本机。T27h-30「本机走 DP、对面走 HDMI」实测可以；对面换成 USB-C 没测过。
- 软断开（让系统里彻底没有这块屏）不能用：断开期间读不到输入源，就不知道什么时候该放回来。

## 测试

```sh
tests/run.sh       # 语法检查 + 全部测试，约 20 秒
tests/mutate.sh    # 变异检查：往脚本副本里逐个埋 bug，确认测试能发现，几分钟
```

测试用 `tests/fake-betterdisplaycli` 模拟显示器，跑的是真实的守护循环，不会碰真的 BetterDisplay。
