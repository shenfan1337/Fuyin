# 浮音 · Fuyin

Windows 桌面上的亚克力悬浮歌词。左侧旋转专辑原图，右侧显示当前与下一句歌词；可以拖动、固定位置，也可以在暂停时自动隐藏。

![浮音月白风格演示](docs/images/panel.png)

> 图片为程序实际 WPF 离屏渲染，使用原创演示文字；离屏图不包含桌面壁纸的实时模糊采样。

## 下载与启动

1. 打开 [Releases](https://github.com/shenfan1337/Fuyin/releases/latest)，下载 **Fuyin-Windows-v1.31.zip**。首次发布附在 Releases 下的运行包可直接使用；GitHub 自动生成的 Source code 压缩包需要自行构建。
2. 将压缩包**完整解压到固定文件夹**，不要只取出 EXE，也不要在压缩包内启动。
3. 双击 `Luma.exe`，然后打开播放器播放歌曲。
4. 点右上角三个点或右键面板打开设置；点击叉号隐藏后，双击系统托盘的浮音图标恢复。

运行环境：Windows 10 1809 及以上 / Windows 11，系统自带的 Windows PowerShell 5.1、WPF 和 .NET Framework。推荐先在 Windows 11 使用；没有逐一验证所有系统、播放器和设备组合。当前安装包未做代码签名。

**完整教程：[使用指南](docs/使用指南.md) · [常见问题](docs/常见问题.md) · [隐私与联网说明](docs/隐私说明.md)**

## 能做什么

- 月白、雾蓝、深夜三种风格，桌面背景亚克力模糊及通透度切换。
- 读取 Spotify、网易云音乐、QQ 音乐向 Windows 提供的歌曲、封面、播放状态与进度。
- 默认纯白歌词，当前句更亮；可选择逐字或整句变色，自定义歌词和进度条颜色。
- 真实逐字时间优先；普通整句歌词使用预测，并自动尝试补充匹配的逐字数据。
- 本机播放状态检测、暂停冻结、唱片暂停及恢复旋转。
- 游戏模式：暂停后渐出隐藏，播放后渐入出现。
- 拖动与固定位置、系统托盘、导入本地 LRC、时间微调、经用户确认的开机自启动。

## 播放器连接与准确性

浮音通过 Windows SMTC / GSMTC 获取歌曲信息，**不靠录音识曲**。部分播放器必须先在设置中开启系统媒体控件，再完全退出并重新打开。网易云的可选进度增强组件见使用指南；它不会自动安装。

播放器版本、媒体信息、歌词源和歌曲录音版本都会影响结果。没有真实逐字数据时，预测无法保证每个字都对准快唱、拖长音或停顿。在线来源暂时不可用、缺失封面、Spotify Connect、长时间静音等场景详见常见问题。请勿将“逐字变色”理解为对任意歌曲的精确音频对齐。

## 从源码构建

在 Windows PowerShell 5.1 中执行：

```powershell
git clone https://github.com/shenfan1337/Fuyin.git
cd Fuyin
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build.ps1 -Test
```

构建使用 Windows 自带的 .NET Framework C# 编译器和系统 WinRT 元数据，无需 Node、Python、NuGet、音乐账号 Cookie 或 API 密钥。默认输出 `dist/Fuyin-Windows-v1.31/` 和同名 ZIP；可运行输出目录中的 `Luma.exe`。`-ExecutionPolicy Bypass` 只作用于该次启动，不改系统策略，受企业策略限制的设备仍可能无法运行。

可选界面自检（会短暂显示测试面板，不修改真实使用配置）：

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File dist/Fuyin-Windows-v1.31/Luma.ps1 -SelfTest
```

源码结构见 [开发与贡献](CONTRIBUTING.md)。项目提供 Windows 构建工作流，但在线歌词接口及播放器端到端同步不属于离线测试保证范围。

## 许可与反馈

本项目以 [Apache License 2.0](LICENSE) 开源，允许依许可证免费使用、修改、分发及商业使用。修改和再分发时请保留许可证、版权与适用的声明。第三方代码、可选组件和歌词/封面的权利不由本项目重新授权，详见 [NOTICE](NOTICE) 与 [第三方声明](app/third-party/NOTICE.md)。

图标包含 AI 生成的原创视觉素材，来源记录在 [BRAND.md](app/BRAND.md)。软件按现状提供，不承诺所有播放器与歌词来源持续可用。

反馈问题请到 [Issues](https://github.com/shenfan1337/Fuyin/issues)，附上浮音版本、Windows 版本、播放器版本、歌名和歌手，以及问题属于整句、逐字、暂停或封面哪一项。**不要上传账号密码、Cookie、私人日志或完整歌词缓存。**

## English

Fuyin is an open-source floating desktop lyrics overlay for Windows. It features acrylic themes, rotating original album artwork, current/next lyric lines, configurable colors, a tray icon, and a game mode that fades out on pause. Download the Windows ZIP from [Releases](https://github.com/shenfan1337/Fuyin/releases/latest), extract all files and run `Luma.exe`. Media detection depends on the player's Windows media-session support. Word timing is estimated when exact data is unavailable. See the Chinese guides above for setup and limitations. Licensed under Apache-2.0.
