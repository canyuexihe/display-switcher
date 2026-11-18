# DisplaySwitcher 显示器布局切换器

一个原生 macOS 菜单栏小工具：一键保存和切换显示器布局（排列方式 + 分辨率）。预设绑定具体物理显示器，菜单随当前接入的显示器自动变化，重新插回显示器时自动恢复上次使用的布局。

**English: [README.md](README.md)**

## 功能

- **菜单栏应用** —— 点击图标列出当前接入显示器可用的所有预设，正在生效的自动打勾
- **一键切换** —— 排列方式（左右 / 上下 / 多屏）和每台显示器的分辨率、刷新率一起应用
- **保存当前布局** —— 命名即存，记录当前所有接入显示器的排列和分辨率
- **预设绑定显示器** —— 每个预设记录保存时的显示器硬件 ID，所需显示器未接入的预设自动从菜单隐藏
- **多屏支持** —— 支持任意数量显示器，预设所需屏幕全部在线时才显示
- **插拔自动恢复** —— 接入的显示器组合变化时，自动应用该组合上次使用的预设（手动改分辨率不会触发）
- **登录时启动** —— 菜单内开关
- **无需任何隐私权限** —— 不需要辅助功能 / 屏幕录制 / 自动化权限
- 同时提供**命令行**用法（`layout.sh`）

## 环境要求

- macOS 13 及以上
- Xcode Command Line Tools（提供 `swiftc`、`python3`）—— 用 `xcode-select --install` 安装
- [displayplacer](https://github.com/jakehilborn/displayplacer)（MIT 协议）—— 安装脚本自动下载

## 安装

```bash
git clone https://github.com/canyuexihe/display-switcher.git
cd display-switcher
./install.sh
open /Applications/DisplaySwitcher.app
```

`install.sh` 会把运行文件部署到 `~/.display-switcher`，下载 displayplacer 二进制（GitHub 直连失败时自动走 gh-proxy.com 镜像），编译 App 并拷贝到 `/Applications`。

> 为什么放在 `~/.display-switcher` 而不是 `~/Documents`？macOS 隐私保护（TCC）会拦截后台进程访问 `~/Documents`，导致脚本无法执行。放在用户主目录下可避开此限制。

## 使用

### 菜单栏

点击菜单栏的显示器图标：

| 菜单项 | 作用 |
|---|---|
| 预设名称 | 点击切换；✓ 表示当前生效的布局 |
| 保存当前布局… | 命名并保存当前所有接入显示器的排列 + 分辨率 |
| 登录时启动 | 开机自启开关 |
| 退出 | 退出应用 |

所需显示器未接入的预设会自动隐藏。如果当前显示器组合没有任何预设，菜单会提示——为这个组合保存一个新预设即可。

### 插拔自动恢复

App 监听显示器插拔事件。接入组合变化后（2 秒防抖），自动应用该组合上次使用的预设。手动修改分辨率不会触发。

### 命令行

```bash
~/.display-switcher/layout.sh save <名称>    # 保存当前布局（所有接入的显示器）
~/.display-switcher/layout.sh apply <名称>   # 应用预设（所需显示器不在线时拒绝并弹通知）
~/.display-switcher/layout.sh list           # 列出预设
```

## 原理

- [displayplacer](https://github.com/jakehilborn/displayplacer) 通过 CoreGraphics 读写显示器配置
- 预设是 `~/.display-switcher/layouts/` 下的 JSON 文件，记录每台显示器的持久 ID、序列号、名称和完整配置串
- `~/.display-switcher/state.json` 记录每个显示器组合（按硬件 ID 排序）最近使用的预设
- 菜单栏 App 是单个 Swift 文件（`menubar/DisplaySwitcher.swift`），使用 AppKit + `NSStatusItem`，`swiftc` 直接编译——无 Xcode 工程、无第三方依赖
- 修改代码后重新编译：`~/.display-switcher/menubar/build.sh`，然后重新拷贝 `.app` 到 `/Applications`，并把「登录时启动」关掉再打开一次

## 卸载

1. 先在菜单里关闭「登录时启动」，再点「退出」
2. 删除 `/Applications/DisplaySwitcher.app` 和 `~/.display-switcher`

## 许可

MIT —— 见 [LICENSE](LICENSE)。仓库不包含第三方二进制；安装脚本下载的 [displayplacer](https://github.com/jakehilborn/displayplacer) 为 MIT 协议（© Jake Hilborn）。