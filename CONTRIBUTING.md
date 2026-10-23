# 开发与贡献

欢迎提交问题和 Pull Request。开始前请先查看 README、使用指南与已知限制。

## 开发环境

Windows 10 1809+ / Windows 11、Windows PowerShell 5.1、.NET Framework 4.x。构建脚本使用系统 `csc.exe`、`System.Runtime.WindowsRuntime.dll`、`System.Runtime.dll` 和 `System32/WinMetadata` 中的 Foundation / Storage 元数据。若组件缺失，脚本会提示具体路径；不要通过提交其他来源的预编译 DLL 代替源码。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build.ps1 -Test
```

`app/*.ps1` 请保存为 **UTF-8 BOM**，否则 Windows PowerShell 5.1 可能误读中文。构建时会为发布副本统一编码。不要将配置、账号信息、歌曲缓存、真实播放记录或下载的适配器二进制提交到仓库。

## 结构

| 文件 | 用途 |
| --- | --- |
| app/Luma.ps1、MenuTheme.xaml | WPF 面板、设置、托盘、视觉状态 |
| app/MediaWorker.ps1 | 歌曲元数据、封面与歌词后台工作 |
| app/TransportWorker.ps1、LocalPlayback.ps1、PlaybackClock.ps1、LiveState.ps1 | 独立播放状态、时钟与暂停恢复 |
| app/AudioSessionReader.cs、PlayerDetection.ps1 | 本机音频会话状态与峰值，不录音 |
| app/Lyrics.ps1、Karaoke.ps1 | 时间标签、逐字与预测 |
| app/LyricFetch.ps1、ChineseLyrics.ps1、QQMusicLyrics.ps1、KugouLyrics.ps1、KrcReader.cs | 歌词获取、匹配、精度补充与文本解码 |
| app/CoverReader.cs、Launcher.cs、Native.cs | 封面读取、启动器、原生亚克力 |
| app/Startup.ps1、Shortcuts.ps1、NeteaseAdapter.ps1 | 自启动、快捷方式、可选适配 |
| scripts/Build.ps1、tests/Smoke.ps1 | 可复现的本地构建入口与离线检查 |

## 提交前

1. 运行构建和离线测试；界面修改还需运行输出目录中的 `Luma.ps1 -SelfTest` 并查看三种风格、窄面板、长中英文内容。
2. 播放器同步修改请说明实测播放器/Windows 版本，以及暂停、恢复、拖进度、切歌的表现。离线检查不代表真实演唱同步已验证。
3. 保留现有自启动/适配器确认流程、独立暂停监控、真实逐字优先、无歌词衬底与无唱片圆环等约定。界面规则见 `app/DESIGN.md`。
4. 新增第三方代码时保留许可证和版权声明，在 `app/third-party/NOTICE.md` 记录改动及来源。

提交贡献即表示你有权提交该内容，并同意按本项目 Apache-2.0 许可证发布。不要提交歌词全文、私人播放记录或别人的专辑图片作为测试数据；请优先使用原创短句和人工构造时间标签。
