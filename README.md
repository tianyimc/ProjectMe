# ProjectMe

> 一个无后端依赖的个人文集：网页负责阅读，CLI 和 GUI 负责维护。

当前版本：**v1.1.7** · 作者：[tianyimc.com](https://tianyimc.com)

仓库名称：**ProjectMe** · 许可证：**MIT**（详见 [`LICENSE`](LICENSE)）

## 这是什么

ProjectMe 将文章正文、文章索引和管理工具放在同一个项目目录中：

- **文集核心**：原生 HTML、CSS、JavaScript 和 Markdown，适合静态托管。
- **管理核心**：PowerShell CLI，适合批量维护、导入和版本回滚。
- **GUI 管理器**：Windows WPF 工作台，支持浅色/深色系统主题，适合日常搜索、编辑和本地预览。
- **数据文件**：`articles.json` 管理文章属性，`articles/` 保存正文，`timeline.json` 管理时间轴。

项目不需要数据库、构建工具或第三方运行库。Windows 用户需要 Windows PowerShell 5.1 或 PowerShell 7；网页部署本身只需要静态文件托管。

## 快速开始

### 启动 GUI

```powershell
.\ProjectMe.Gui.ps1
```

GUI 使用 WPF 构建，提供文章搜索、属性编辑、删除、新建文章、本地预览、自检、时间轴管理、版本回滚、正文打开和日志入口，并会跟随 Windows 当前应用主题。也可以先启动 CLI，再选择菜单中的 **4. GUI 窗口管理器**。旧版 WinForms 文件仅作为隐藏回退保留。

### 启动 CLI

```powershell
.\ProjectMe.ps1
```

CLI 适合脚本化和完整维护，包含文章列表、属性编辑、删除文章、时间轴、服务控制、日志、项目自检和版本回滚；启用的插件会作为额外的菜单项追加在末尾。

### 预览网页

```powershell
.\serve.ps1
```

然后打开 `http://localhost:4173/`。也可以在 GUI 中启动预览，或在 CLI 的 `serve` 菜单中选择前台/后台模式。

## 日常操作

### 新建文章

```powershell
.\New-Article.ps1 `
  -Slug "my-first-note" `
  -Title "我的新文章" `
  -Category "随笔" `
  -Excerpt "文章摘要" `
  -Tags "成长", "写作"
```

脚本会创建 `articles/my-first-note.md`，并把文章属性写入 `articles.json`。正文直接编辑对应的 Markdown 文件；标题、摘要、标签等目录属性由管理器维护。

### 删除文章

CLI 选择 **3. 删除文章**，或在 WPF GUI 的文章属性区点击“删除文章”。删除会同时移除文章索引、Markdown 正文和对应的时间轴条目；不会修改 Obsidian 源文件。CLI 需要输入包含 `.md` 的完整文件名确认，GUI 需要勾选“确认删除”。为避免项目索引为空，最后一篇文章不能删除。

### 导入 Obsidian（插件）

“从 Obsidian 导入”是一个**默认关闭**的插件，位于 `plugins/obsidian-import/`。启用后它才会出现在 CLI 菜单（追加为末尾的插件项）与 GUI 中：

```json
"plugins": { "obsidian-import": { "enabled": true } }
```

导入器递归读取“阶段/卷/节.md”，按 `##` 标题拆分文章，同时保留阶段级和节级前言。首次运行建议预览：

```powershell
.\plugins\obsidian-import\Import-ObsidianCorpus.ps1 -SourceRoot "D:\Notes\MyVault" -WhatIf
```

确认结果后去掉 `-WhatIf` 执行正式导入。脚本默认以自身所在目录为项目根，因此从其它位置调用时要显式传入 `-ProjectRoot`。导入不会修改 Obsidian 源目录；重复执行会保留已修改的文章属性，并仅在来源正文发生变化时同步对应 Markdown 正文。

WPF GUI 的“预览与维护 → Obsidian 导入”可以设置默认导入源（写入 `obsidian.sourceRoot`）。设置后，点击“从 Obsidian 导入”时目录选择窗口会默认定位到该目录；在导入流程中临时选择其他目录只影响本次导入。

### 运行自检

```powershell
.\Check-ProjectMe.ps1
```

自检会检查文章索引、Markdown 文件、必要字段、颜色格式和时间轴引用。

## 文件结构

| 路径 | 用途 |
| --- | --- |
| `index.html` / `history.html` | 文集首页与历史时间轴 |
| `app.js` / `history.js` / `site-common.js` | 网页交互和 Markdown 展示 |
| `styles.css` | 网页样式 |
| `articles/` | Markdown 正文，一篇一个文件 |
| `articles.json` | 文章目录属性；`file` 指向 `articles/`，可选的 `path` 可引用仓库内其他 Markdown |
| `timeline.json` | 时间轴条目 |
| `ProjectMe.ps1` | CLI 管理器 |
| `ProjectMe.Gui.ps1` / `ProjectMe.Gui.xaml` | WPF GUI 窗口管理器 |
| `ProjectMe.Gui.WinForms.ps1` | 旧版隐藏回退 GUI |
| `ProjectMe.Common.ps1` | CLI、GUI 共用函数与插件宿主 API |
| `plugins/` | 插件目录，每个插件一个文件夹（默认关闭的 `obsidian-import` 在其中） |
| `project-info.json` | 名称、版本、作者等项目元数据 |
| `projectme.config.json` | 端口、文章列表和新文章默认配置 |
| `LICENSE` | MIT 许可证全文 |
| `old/` | 本地版本 ZIP 快照（已在 `.gitignore` 中排除，仓库不包含此目录） |
| `logs/` | CLI 和 GUI 共用日志目录 |

## 数据约定

文章记录至少需要 `slug`、`title`、`category`、`tags`、`readingTime`、`excerpt` 和 `file`。`tags` 应保存为数组；网页和 CLI 会兼容旧的字符串格式并在保存时统一。

`file` 默认指向 `articles/` 下的 Markdown 文件。如果记录额外提供 `path`，网页会按仓库相对路径读取正文，"ProjectMe 更新日志"文章就是这样直接复用根目录 `CHANGELOG.md` 的；自检脚本同样支持该字段。

时间轴日期使用 `YYYYMMDD`。同一天有多篇文章时，`priority` 越小表示越新，页面会按项目现有规则展示。移除时间轴条目只会禁用条目，不会删除文章。

## 版本规则

版本格式为 `v.A.B.C GenX`：

- `A`：文集网页核心版本。当前为 `1`，只有网页核心发生重大变化时才提升。
- `B`：重要功能版本。当前 GUI 管理器属于重要更新，因此本次为 `1.1.x`。
- `C`：普通更新，例如小功能、优化和修复。
- `GenX`：同一普通版本的 Bug 修复快照。第一版不显示 `Gen1`，第二版开始显示 `Gen2`、`Gen3`。

本项目不提供"更新版本"功能：版本号由维护者手动修改 `project-info.json` 并追加 `CHANGELOG.md` 条目。版本回滚仍然保留：CLI 的 **12. 回滚版本** 或 GUI 的"预览与维护 → 版本管理"会从 `old/` 中的快照恢复项目文件，回滚前自动在 `old/reseted/` 保存当前项目备份。

## 配置

`projectme.config.json` 可以调整：

- `serve.port`：本地预览端口，默认 `4173`；
- `serve.mode`：CLI 默认使用 `background` 或 `foreground`；
- `plugins.<插件名>.enabled`：插件开关，见下文「插件」；
- `obsidian.sourceRoot` 与 `obsidian.preview`：`obsidian-import` 插件的导入默认目录和是否先预览（插件未启用时不生效）；
- GUI 的“预览与维护 → Obsidian 导入”可以直接保存或清除 `obsidian.sourceRoot`。
- `articleList.pageSize` 与 `articleList.groupBySection`：CLI 列表行为；
- 网页文集主页固定按 20 篇一页展示，筛选后同样分页。
- `newArticle`：新文章默认标签、日期和阅读时间。

配置错误时会写入日志，并回退到内置默认值。

## 插件

插件放在项目目录的 `plugins/` 下，每个插件一个文件夹；插件主目录就是包含 `.ps1` 文件的那一层：

```text
plugins/
  obsidian-import/
    plugin.json                  # 插件清单
    ObsidianImport.Plugin.ps1    # 插件入口
    Import-ObsidianCorpus.ps1    # 该插件自己的脚本
```

启用或关闭：

```json
"plugins": {
    "obsidian-import": { "enabled": false }
}
```

- 键名是插件文件夹名；没有配置项时使用清单里的 `defaultEnabled`（缺省 `false`）。
- 插件不存在、被禁用或初始化失败时，CLI 菜单与 GUI 都不显示它的入口，其它功能不受影响（失败只写日志）。
- 配置改动后需要重启 CLI 或 GUI 才会生效。

### 插件清单 `plugin.json`

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `entry` | 是 | 入口脚本，相对插件目录 |
| `id` | 否 | 插件标识，应与文件夹名一致 |
| `name` / `version` / `description` | 否 | 展示与说明信息 |
| `defaultEnabled` | 否 | 未配置开关时的默认状态，缺省 `false` |
| `cli.label` | 声明 `cli` 时必填 | CLI 菜单项文字 |
| `cli.function` | 声明 `cli` 时必填 | 菜单被选中时无参调用的函数 |
| `gui.controls` | 声明 `gui` 时必填 | 插件占用的已命名 XAML 控件列表 |
| `gui.function` | 声明 `gui` 时必填 | 窗口初始化时无参调用的函数 |

### 插件运行方式

宿主用 dot-source 载入 `entry`，插件因此运行在宿主作用域里，可直接使用 `$root`、`$config` / `$script:config`、`Get-Control`、`Show-Message`、`Show-Error`、`Show-TextDialog`、`Write-ProjectLog`、`Refresh-Articles`、`Pause-Menu`；插件脚本可以用 `Split-Path -Parent $MyInvocation.MyCommand.Path` 得到自己的目录。

GUI 插件需要先在 `ProjectMe.Gui.xaml` 里预置自己要用的控件，并默认 `Visibility="Collapsed"`；插件启用且初始化成功后，宿主才按 `gui.controls` 把它们显示出来。这样即使插件文件夹被直接删除，界面上也不会残留入口。

`.\Check-ProjectMe.ps1` 会顺带校验 `plugins/` 下每个插件的清单与入口文件。

> 约定：包含中文的 `.ps1` 必须保存为**带 BOM 的 UTF-8**，否则 Windows PowerShell 5.1 会按系统代码页解码而无法解析脚本。

## 部署

将 `index.html`、`404.html`、脚本、样式、`project-info.json`、`articles.json`、`timeline.json`、`articles/` 和 `CHANGELOG.md`（"ProjectMe 更新日志"文章直接引用它）一起部署到 GitHub Pages、Netlify 或其他静态托管服务即可。

## 仓库

- 仓库名称：`ProjectMe`；已执行 `git init`，尚未配置远程地址，需要发布时再 `git remote add origin <仓库地址>`。
- 当前版本：`v1.1.7`；本项目不提供自动"更新版本"功能，版本号由维护者手动维护。
- 示例文章只有"ProjectMe 是什么"和"ProjectMe 更新日志"两篇，后者直接引用根目录的 `CHANGELOG.md`。
- `logs/`、`old/` 与 `.projectme-serve.json` 是本地运行产物，已在 `.gitignore` 中排除。

## 作者与许可证

ProjectMe 由 [tianyimc.com](https://tianyimc.com) 设计与维护。作者主页：<https://tianyimc.com>。

本项目以 [MIT 许可证](https://opensource.org/license/mit) 开放源代码，完整文本见 [`LICENSE`](LICENSE)。你可以自由地使用、修改和分发本项目，只需保留版权声明。

© 2026 [tianyimc.com](https://tianyimc.com) 依据 MIT 许可证开放源代码

## 更新日志

完整记录见 [`CHANGELOG.md`](CHANGELOG.md)。
