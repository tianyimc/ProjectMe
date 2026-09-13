# ProjectMe

> 一个无后端依赖的个人文集：网页负责阅读，CLI 和 GUI 负责维护。

当前版本：**v1.1.6** · 作者：`tianyimc.com`

仓库名称：**ProjectMe**（公开发布版，当前本地目录名为 `PubProjectMe`）

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

GUI 使用 WPF 构建，提供文章搜索、属性编辑、删除、新建文章、Obsidian 导入、本地预览、自检、时间轴管理、版本回滚、正文打开和日志入口，并会跟随 Windows 当前应用主题。也可以先启动 CLI，再选择菜单中的 **4. GUI 窗口管理器**。旧版 WinForms 文件仅作为隐藏回退保留。

### 启动 CLI

```powershell
.\ProjectMe.ps1
```

CLI 适合脚本化和完整维护，包含文章列表、属性编辑、删除文章、Obsidian 导入、时间轴、服务控制、日志、项目自检和版本回滚。

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

### 导入 Obsidian

导入器递归读取“阶段/卷/节.md”，按 `##` 标题拆分文章，同时保留阶段级和节级前言。首次运行建议预览：

```powershell
.\Import-ObsidianCorpus.ps1 -SourceRoot "D:\Notes\MyVault" -WhatIf
```

确认结果后去掉 `-WhatIf` 执行正式导入。导入不会修改 Obsidian 源目录；重复执行会保留已修改的文章属性，并仅在来源正文发生变化时同步对应 Markdown 正文。

WPF GUI 的“预览与维护 → Obsidian 导入”可以设置默认导入源。设置后，点击“从 Obsidian 导入”时目录选择窗口会默认定位到该目录；在导入流程中临时选择其他目录只影响本次导入。

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
| `ProjectMe.Common.ps1` | CLI、GUI 共用函数 |
| `project-info.json` | 名称、版本、作者等项目元数据 |
| `projectme.config.json` | 端口、文章列表和新文章默认配置 |
| `old/` | 本地版本 ZIP 快照（已加入 `.gitignore`，公开仓库不包含此目录） |
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

公开版本不提供"更新版本"功能：版本号与个人版保持一致，由维护者手动修改 `project-info.json` 并追加 `CHANGELOG.md` 条目。版本回滚仍然保留：CLI 的 **13. 回滚版本** 或 GUI 的"预览与维护 → 版本管理"会从 `old/` 中的快照恢复项目文件，回滚前自动在 `old/reseted/` 保存当前项目备份。

## 配置

`projectme.config.json` 可以调整：

- `serve.port`：本地预览端口，默认 `4173`；
- `serve.mode`：CLI 默认使用 `background` 或 `foreground`；
- `obsidian.sourceRoot` 与 `obsidian.preview`：导入默认目录和是否先预览；
- GUI 的“预览与维护 → Obsidian 导入”可以直接保存或清除 `obsidian.sourceRoot`。
- `articleList.pageSize` 与 `articleList.groupBySection`：CLI 列表行为；
- 网页文集主页固定按 20 篇一页展示，筛选后同样分页。
- `newArticle`：新文章默认标签、日期和阅读时间。

配置错误时会写入日志，并回退到内置默认值。

## 部署

将 `index.html`、`404.html`、脚本、样式、`project-info.json`、`articles.json`、`timeline.json`、`articles/` 和 `CHANGELOG.md`（"ProjectMe 更新日志"文章直接引用它）一起部署到 GitHub Pages、Netlify 或其他静态托管服务即可。

## 仓库

- 仓库名称：`ProjectMe`，当前本地目录名为 `PubProjectMe`；已执行 `git init`，尚未配置远程地址，需要发布时再 `git remote add origin <仓库地址>`。
- 公开发布版与个人版共用同一套版本号，当前为 `v1.1.6`，公开版不提供自动"更新版本"功能。
- 仓库不包含个人文章存档：`articles.json` 与 `timeline.json` 中的个人条目已清空，示例文章只有"ProjectMe 是什么"和"ProjectMe 更新日志"两篇。
- `logs/`、`old/` 与 `.projectme-serve.json` 是本地运行产物，已在 `.gitignore` 中排除。

## 更新日志

完整记录见 [`CHANGELOG.md`](CHANGELOG.md)。
