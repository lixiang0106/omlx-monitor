# oMLX 状态浮窗

[English](README.md) · **简体中文**

> 一个透明、常驻置顶的小浮窗，实时显示本机 [oMLX](https://omlx.app) 正在做什么：生成速度、请求排队情况，以及距离内存上限还有多少余量。

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111111?logo=apple&logoColor=white)](#环境要求)
[![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)](#环境要求)
[![无第三方依赖](https://img.shields.io/badge/依赖-无-2EBDAC)](#环境要求)
[![下载](https://img.shields.io/github/v/release/lixiang0106/omlx-monitor?label=下载&color=2EBDAC)](https://github.com/lixiang0106/omlx-monitor/releases/latest)
[![MIT 许可](https://img.shields.io/badge/许可-MIT-blue)](LICENSE)

![oMLX 状态浮窗预览](docs/preview-zh.svg)

## 一眼看懂

| | |
| --- | --- |
| 这是什么 | 本机 oMLX 服务的 macOS 原生悬浮状态窗 |
| 其他叫法 | oMLX 状态浮窗、oMLX monitor、oMLX HUD |
| 运行环境 | macOS 13 Ventura 及以上；预编译包为 arm64，需要 Apple Silicon（已在 M5 Max 上实测） |
| 技术栈 | Swift 5 + AppKit，无第三方依赖、无包管理器 |
| 安装 | 从 [Releases](https://github.com/lixiang0106/omlx-monitor/releases/latest) 下载，或 `./build.sh` |
| 显示内容 | tok/s、已生成 token、预填充进度、活跃与等待请求数、进程内存与软硬限 |
| 数据来源 | `GET http://127.0.0.1:<端口>/admin/api/activity`，只读，每 2 秒一次 |
| 前置条件 | 本机 oMLX 服务已启动，管理接口可用 |
| 许可 | MIT |

---

## 为什么做这个

oMLX 自带有面板，但它在浏览器标签页里。在这台机器上跑 70B 级模型时，真正需要随时知道的几件事都很朴素：现在是在生成还是仍在预填充？速度多少？后面有没有请求在排队？内存离硬限还有多远？

为了看这些数字切换标签页，成本高于答案本身。这个浮窗把一块半透明的小卡片钉在窗口上方，两秒刷新一次，抬眼就能看到。

## 功能

- **实时生成指标**：当前请求的输出 token 数、`tok/s`、已用时间，以及预填充进度（`processed / total`）。
- **排队可见**：每个模型的活跃与等待请求数，卡顿会直接显示出来，不必再靠猜。
- **内存余量**：进程实际占用与 oMLX 软限、硬限并排显示，取值口径与内存保护器一致。
- **确实不碍事**：默认透明、无边框、置顶，跟随所有桌面空间和全屏应用；任意位置可拖动，并记住上次位置。
- **尺寸可调**：4 档宽度（340 / 448 / 560 / 680 pt）、4 档字号（10–16 pt）、可隐藏明细行的紧凑模式；窗口高度随内容变化。
- **中英双语界面**：默认跟随系统语言，也可在菜单里固定为中文或 English。
- **离线如实提示**：服务不再响应时直接显示不可用，不会把旧数字当作实时值继续展示。
- **零配置**：不需要改 YAML、不需要额外配置文件、不驻留后台守护进程；一个 Swift 源文件加一个构建脚本。

## 环境要求

| 项目 | 要求 |
| --- | --- |
| 系统 | macOS 13 Ventura 及以上。预编译包为 arm64，Intel 机型需要从源码构建。 |
| oMLX | 本地服务已启动，管理接口可用 |
| 工具链 | Xcode Command Line Tools（`xcode-select --install`） |

浮窗访问 `http://127.0.0.1:<端口>/admin/api/activity`，端口与 API key 都从你自己的 `~/.omlx/settings.json` 读取。

## 安装

### 直接下载（最快）

1. 从 [Releases](https://github.com/lixiang0106/omlx-monitor/releases/latest) 下载 `oMLX-Status-HUD-1.1.0.zip` 并解压
2. 把 `oMLX Status HUD.app` 拖进「应用程序」
3. 首次打开：右键点应用 → **打开**

**关于 Gatekeeper。** 应用使用 ad-hoc 签名，没有经过公证。首次启动时 macOS 可能提示无法验证开发者，右键点击应用 → **打开** → **打开** 即可；也可以清除隔离标记：

```bash
xattr -dr com.apple.quarantine "/Applications/oMLX Status HUD.app"
```

### 从源码构建

```bash
git clone https://github.com/lixiang0106/omlx-monitor.git
cd omlx-monitor
./build.sh
open "dist/oMLX Status HUD.app"
```

构建耗时数秒，结束前会跑一遍离线自检。产物是完整的 `.app`，没有运行时依赖，也不需要单独管理图标资源。

需要开机自启时，在 **系统设置 → 通用 → 登录项** 里添加该应用。浮窗本身不会写入任何自启配置。

## 使用方法

| 操作 | 方式 |
| --- | --- |
| 移动浮窗 | 在卡片任意位置拖动 |
| 调整宽度或字号 | 点 **⋯** → **浮窗宽度** / **字体大小** |
| 隐藏模型内存明细 | **⋯** → **精简显示** |
| 切换语言 | **⋯** → **语言** |
| 开关半透明底色 | **⋯** → **启用半透明底色** |
| 回到左上角 | **⋯** → **移回屏幕左上角** |
| 退出 | 卡片上的 **×**，或菜单栏 **oMLX** 图标里的退出项 |

卡片透明时，浅色桌面上文字对比度偏低。打开半透明底色会在文字后加一层深色面板，也可以改为深色文字，适配亮色壁纸。

## 常见问题

**不想切浏览器标签页，怎么看到 oMLX 的实时 tok/s？**
用这个浮窗。它每 2 秒读取一次 `/admin/api/activity`，把当前请求的已生成 token 数、tok/s 和耗时直接显示在桌面上。

**怎么看当前请求是在预填充还是在生成？**
预填充阶段显示「预填充」以及 `processed / total` 的 prompt token 数和预填充速度；进入解码后，同一行切换为「生成中」，改为显示输出 token 和 tok/s。两个阶段的显示刻意做了区分。

**怎么知道后面还有多少请求在排队？**
每个模型行带活跃与等待计数，标题行给总量。本机观察到的单模型调度并发为 1，等待数大于 0 说明你的请求排在后面。

**进程离软限和硬限还有多远？**
最下面一行把 oMLX 进程占用和内存保护器实际执行的阈值并排显示，例如 `74.6GB / 软限 90.0GB / 硬限 97.0GB`。这些就是触发驱逐所用的值，不是另一套估算。

**它会改我的模型、采样参数或内存上限吗？**
不会。程序只发 `GET` 请求，不写入 oMLX 配置，也不加载或卸载模型。

**API key 从哪来，会不会被保存？**
每次请求时从 `~/.omlx/settings.json` 读取，只用于一次发往 `127.0.0.1` 的请求；不写磁盘、不记日志、不显示在界面上。重定向被拒绝，凭据不会被转发到别处。

**能改大小、字号或语言吗？**
可以。**⋯** 菜单提供四档宽度（340–680 pt）、四档字号（10–16 pt）、精简行模式，以及中文与 English 切换。窗口高度随内容变化，位置会被记住。

**它和 oMLX 自带的网页面板有什么区别？**
网页面板在浏览器标签页里，看同样的数据要先切换上下文。浮窗把一块小卡片钉在窗口上方，跨桌面空间和全屏应用都可见，数字停在余光范围内。两者是互补关系，不互相替代。

## 数据来源

每 2 秒发出一次只读请求：

```
GET http://127.0.0.1:<端口>/admin/api/activity
Authorization: Bearer <从 ~/.omlx/settings.json 读取的 API key>
```

读取 `active_requests`、`waiting_requests`、`generating`、`prefilling`、`memory_pressure` 等字段，自身不发送任何推理请求。

## 隐私与安全

- **只连本机环回地址。** 应用不需要访问其他主机，也不会访问；HTTP 重定向被拒绝，凭据不会被转发到别处。
- **API key 不落地。** 每次请求时从现有 oMLX 设置中读取，仅在内存中使用，不写入磁盘、不打印日志、不显示在界面上。
- **无遥测、无统计、无更新检查。**
- **只读。** 不修改 oMLX 的模型、参数或内存上限。

两个固有前提需要说明：设置文件以你的用户权限读取；本机任何能占用所配置端口的进程都可能观察到这次请求。这两点是"通过环回 HTTP 访问本地服务"本身带来的，不是额外设计选择。细节见 [SECURITY.md](SECURITY.md)。

## 故障排查

| 卡片提示 | 含义与处理 |
| --- | --- |
| `无法读取 oMLX 设置` | 当前用户从未运行过 oMLX，或其安装路径不同。启动一次 oMLX 即可。 |
| `oMLX 未连接，正在重试` | 服务未监听。启动 oMLX，或核对其设置中的 `server.port`。 |
| `身份验证失败` | 浮窗启动后 API key 发生了变化。退出后重新打开。 |
| `oMLX 接口不可用（HTTP …）` | 管理接口被关闭，或新版本 oMLX 更换了路径。 |
| 显示 `暂无已加载的模型` | 服务正常但处于空闲状态，当前没有模型驻留内存。 |
| Finder 里没有图标 | 重新运行 `./build.sh`；图标由 `Sources/DrawIcon.swift` 生成。 |

## 开发说明

```
Sources/OMLXMonitor.swift   窗口、轮询、排版与本地化
Sources/DrawIcon.swift      用 AppKit 绘制 10 个尺寸的图标
Info.plist                  Bundle 元数据
build.sh                    编译、生成图标、签名、自检
```

可执行文件提供三种诊断模式，不会干扰正在运行的实例：

```bash
dist/"oMLX Status HUD.app"/Contents/MacOS/OMLXMonitor --self-test        # 解析、排版、双语
dist/"oMLX Status HUD.app"/Contents/MacOS/OMLXMonitor --probe            # 单次真实请求
dist/"oMLX Status HUD.app"/Contents/MacOS/OMLXMonitor --gui-diagnostic   # 窗口几何
```

刻意不引入包管理器、第三方依赖或额外构建系统，`swiftc` 之外没有别的步骤。

供机器读取的项目摘要见 [`llms.txt`](llms.txt)；供编码助手使用的构建与验证说明见 [`AGENTS.md`](AGENTS.md)。

## 已知限制

- 最多展开 4 个已加载模型，其余以数量汇总。
- 在 macOS 27 + M5 Max 上针对 oMLX 0.7.x 验证。旧版本的活动接口字段若有差异，卡片会显示数据不可用，不会猜测取值。
- 仅提供中文与英文。新增语言即逐条补一张 `L.t(...)` 文案表。
- 单实例运行；应用刻意不显示 Dock 图标（`LSUIElement`）。

## 参与贡献

欢迎提交 issue 和 pull request。涉及轮询模型、凭据处理、排版算法这三处的改动，建议先开 issue 讨论：这三块代码刻意保持很小，维持这个规模本身就是设计约束。

## 许可

[MIT](LICENSE)。本项目与 oMLX 官方无隶属关系；oMLX 是独立产品，本工具只读取其本地状态接口。
