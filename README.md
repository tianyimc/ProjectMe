# ProjectMe

> 一个无后端依赖的个人文集：网页负责阅读，CLI 和 GUI 负责维护。

当前版本：**v1.1.10** · 作者：[tianyimc.com](https://tianyimc.com)

仓库名称：**ProjectMe** · 许可证：**MIT**（详见 [`LICENSE`](LICENSE)）

## 这是什么

ProjectMe 将文章正文、文章索引和管理工具放在同一个项目目录中：

- **文集核心**：原生 HTML、CSS、JavaScript 和 Markdown，适合静态托管。
- **管理核心**：PowerShell CLI，适合批量维护、项目自检和版本回滚。
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

CLI 选择 **3. 删除文章**，或在 WPF GUI 的文章属性区点击“删除文章”。删除文章不会修改插件导入源里的文件。CLI 需要输入包含 `.md` 的完整文件名确认，GUI 需要勾选“确认删除”。为避免项目索引为空，最后一篇文章不能删除。

### 导入 Obsidian（暂不提供）

ProjectMe 支持插件，但**本版本不随包提供任何插件**。“从 Obsidian 导入”插件仍在完善中（格式兼容性与拆分规则尚未定型），因此暂不提供，仓库里也不包含它的任何内容。

插件机制本身是可用的：把插件包放进 `plugins\` 并用插件管理器安装即可（见下文「插件」）。

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
| `Update-ProjectMe.ps1` | 无损更新器：把新版本包体应用到当前安装 |
| `plugins/` | 插件目录（安装插件时自动创建），每个插件一个文件夹，配置在插件自己的 `config.json` 里；`plugins\*.zip` 是待安装插件包 |
| `Manage-Plugins.ps1` | 插件管理器：安装 / 启用 / 禁用 / 卸载插件，支持安全模式 |
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
- `articleList.pageSize` 与 `articleList.groupBySection`：CLI 列表行为；
- 网页文集主页固定按 20 篇一页展示，筛选后同样分页。
- `newArticle`：新文章默认标签、日期和阅读时间。
- `update.keep`：更新器默认保留本地版本的路径列表（相对项目根，支持 `*` 通配），见下文「升级」。

配置错误时会写入日志，并回退到内置默认值。

> 该文件只保存主程序设置；插件设置一律放在插件自己的 `plugins\<插件名>\config.json` 里。

## 插件

插件放在项目目录的 `plugins/` 下，每个插件一个文件夹；插件主目录就是包含 `.ps1` 文件的那一层：

```text
plugins/
  <插件名>/
    plugin.json       # 插件清单
    config.json       # 插件配置（可带默认值，见下）
    <入口>.ps1        # 插件入口
```

本版本**不自带任何插件**（`plugins\` 目录会在安装插件时自动创建）。

启用或关闭：开关就在插件自己的 `config.json` 里，主程序配置不再保存任何插件数据。

```json
{ "enabled": false }
```

- 插件不存在、被禁用或初始化失败时，CLI 菜单与 GUI 都不显示它的入口，其它功能不受影响（失败只写日志）。
- 开关改动后需要重启 CLI 或 GUI 才会生效（CLI 从插件管理器返回时会自动刷新菜单）。

### 插件配置文件 `config.json`

插件配置放在**插件自己的主目录**里（`plugins\<插件名>\config.json`），`projectme.config.json` 只保存主程序设置。

- 文件可由插件包自带（提供默认值），也可以不存在；缺失时按清单的 `defaultEnabled`（缺省 `false`）判定启用状态。
- 保留键 `enabled`（布尔）由宿主维护，代表插件开关；**其余键完全归插件所有**，宿主机不去解析它们。
- 它是**用户数据**：更新器永不覆盖，插件管理器在升级时保留本地已存在的那一份，卸载时随插件目录一起移入 `old\removed-plugins\`。
- 启用状态优先级：`config.json` 的 `enabled` → 清单的 `defaultEnabled` → `false`。

### 插件管理器

不用手改配置：运行根目录的 `Manage-Plugins.ps1`（CLI 菜单 **14. 插件管理器**、GUI“预览与维护 → 项目维护 → 插件管理器”按钮也能打开）。

```powershell
.\Manage-Plugins.ps1                 # 交互菜单
.\Manage-Plugins.ps1 -List           # 只看清单
.\Manage-Plugins.ps1 -Install .\demo.zip
.\Manage-Plugins.ps1 -Enable demo
.\Manage-Plugins.ps1 -Disable demo
.\Manage-Plugins.ps1 -Uninstall demo
.\Manage-Plugins.ps1 -AllDisabled    # 一键禁用全部插件
.\Manage-Plugins.ps1 -SafeModeCli    # 以安全模式启动 CLI
```

扫描规则与行为：

- `plugins\` 下的**文件夹 = 已安装插件**（显示名称、版本、启用状态、是否损坏）；`plugins\*.zip = 发现的未安装插件`（会只读探测包内 `plugin.json`，标注将安装成什么名字，以及是否与已安装插件同名）。
- **安装**：校验包内路径安全（拒绝 `..`、绝对路径、非法设备名）、必须恰好有一个含 `plugin.json` 的插件主目录、清单与入口必须有效；装好后**默认禁用**（若包内自带 `config.json` 则以其默认值为准，缺失时自动生成）。同名插件已存在时按“升级/重装”处理：显示新旧版本、确认后把旧目录移入 `old\removed-plugins\`，并**保留本地已有的 `config.json`**（开关与插件设置都不丢）。
- **启用 / 禁用**：只改插件自己的 `plugins\<id>\config.json` 的 `enabled`，主程序配置与其它文件都不动；状态损坏的插件会拒绝启用并说明原因。
- **卸载**：需要输入插件名确认，随后把插件目录（含它自己的 `config.json`）移入 `old\removed-plugins\<id>-<时间戳>\`（可用 `-Purge` 直接删除）。
- **安全模式**：`ProjectMe.ps1 -SafeMode` / `ProjectMe.Gui.ps1 -SafeMode` 让**本次运行**忽略全部插件，任何配置文件都不会被改写；管理器的「以安全模式启动」就是替你带上这个开关。需要持久关闭时用「全部禁用」。

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

## 升级

下载新版本的完整包体（zip，或已解压的目录）后，在旧版安装目录运行一次更新器即可，**不需要手动解压覆盖，也不会碰你的文章**：

```powershell
.\Update-ProjectMe.ps1 -Package .\ProjectMe-v1.1.10.zip
```

更新器会先打印计划（新增 / 更新 / 跳过各多少、具体是哪些文件），确认后才开始写入：

- **永不写入、永不删除的用户数据**：`articles/`、`articles.json`、`timeline.json`、`projectme.config.json`、`.gitignore`、`logs/`、`old/`、`.git/`，以及各插件自己的 `plugins\<插件名>\config.json`。即使包体里带了同名文件也会跳过。
- **`project-info.json` 采用合并**：版本号取自包体，你本地自定义的 `title`、`author`、`copyright` 等保持不变。
- **本地改过的程序文件**（例如 `styles.css`、`index.html`）：会被逐个询问「保留本地版本 / 用包体覆盖」，可随时改主意（`A` 之后全部覆盖、`L` 之后全部保留、`Q` 取消）；选择「保留」的还可以写入 `update.keep` 记住，下次不再询问。
- **更新前自动备份**到 `old/v<旧版本>-<日期>-preupdate.zip`（不含 `.git/`）；写入过程中任何失败都会按文件精确回滚。
- 更新结束后自动运行 `Check-ProjectMe.ps1` 自检，并提示需要重启 CLI / GUI。

常用参数：

| 参数 | 用途 |
| --- | --- |
| `-WhatIf` | 只打印计划，不应用包体（项目文件零改动） |
| `-Overwrite` | 不询问，本地不同的程序文件全部用包体覆盖 |
| `-KeepLocal` | 不询问，本地不同的程序文件全部保留 |
| `-Keep <路径>` | 额外指定永不覆盖的路径（可多次、支持通配） |
| `-Force` | 允许同版本重跑（更新中断后续跑也用它） |
| `-ProjectRoot <目录>` | 更新另一个安装目录 |

回滚方式：运行 `ProjectMe.ps1` → **12. 回滚版本**，或直接用 `old/` 里的备份 zip 覆盖回来。

> 更新程序文件期间请关闭正在运行的 GUI 窗口；更新器会尝试自动停止本地预览服务。

## 部署

将 `index.html`、`404.html`、脚本、样式、`project-info.json`、`articles.json`、`timeline.json`、`articles/` 和 `CHANGELOG.md`（"ProjectMe 更新日志"文章直接引用它）一起部署到 GitHub Pages、Netlify 或其他静态托管服务即可。

## 仓库

- 仓库名称：`ProjectMe`；已执行 `git init`，尚未配置远程地址，需要发布时再 `git remote add origin <仓库地址>`。
- 当前版本：`v1.1.10`；本项目不提供自动"更新版本"功能，版本号由维护者手动维护，用户侧用 `Update-ProjectMe.ps1` 应用新包体。
- 示例文章只有"ProjectMe 是什么"和"ProjectMe 更新日志"两篇，后者直接引用根目录的 `CHANGELOG.md`。
- `logs/`、`old/` 与 `.projectme-serve.json` 是本地运行产物，已在 `.gitignore` 中排除。

## 作者与许可证

ProjectMe 由 [tianyimc.com](https://tianyimc.com) 设计与维护。作者主页：<https://tianyimc.com>。

本项目以 [MIT 许可证](https://opensource.org/license/mit) 开放源代码，完整文本见 [`LICENSE`](LICENSE)。你可以自由地使用、修改和分发本项目，只需保留版权声明。

© 2026 [tianyimc.com](https://tianyimc.com) 依据 MIT 许可证开放源代码

## 更新日志

完整记录见 [`CHANGELOG.md`](CHANGELOG.md)。
