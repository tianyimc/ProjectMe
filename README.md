# ProjectMe

> 一个无后端依赖的个人文集：网页负责阅读，CLI 和 GUI 负责维护。

当前版本：**v1.1.10 Gen2** · 作者：[tianyimc.com](https://tianyimc.com)

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
| `Update-ProjectMe.ps1` | 无损更新器：把新版本包体应用到当前安装；自带所需函数，可直接在旧版本目录里运行 |
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

插件放在项目目录的 `plugins/` 下，每个插件一个文件夹；插件主目录就是包含 `plugin.json` 的那一层：

```text
plugins/
  <插件名>/
    plugin.json       # 插件清单
    config.json       # 插件配置（可带默认值，见下）
    <入口>.ps1        # 插件入口
```

本版本**不自带任何插件**（`plugins\` 目录会在安装插件时自动创建）。

> 自己写插件的话，请看文末的 **插件设计规范**：清单字段、配置与启用规则、生命周期、CLI/GUI 契约、打包与命名约定都在那里，本节只是使用说明。

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

> 上表是速查；每个字段的校验规则、CLI/GUI 的调用时机与失败处理，以文末 **插件设计规范** §3、§6、§7 为准。

### 插件运行方式

宿主用 dot-source 载入 `entry`，插件因此运行在宿主作用域里，可直接使用 `$root`、`$config` / `$script:config`、`Get-Control`、`Show-Message`、`Show-Error`、`Show-TextDialog`、`Write-ProjectLog`、`Refresh-Articles`、`Pause-Menu`；插件脚本可以用 `Split-Path -Parent $MyInvocation.MyCommand.Path` 得到自己的目录。

GUI 插件需要先在 `ProjectMe.Gui.xaml` 里预置自己要用的控件，并默认 `Visibility="Collapsed"`；插件启用且初始化成功后，宿主才按 `gui.controls` 把它们显示出来。这样即使插件文件夹被直接删除，界面上也不会残留入口。

`.\Check-ProjectMe.ps1` 会顺带校验 `plugins/` 下每个插件的清单与入口文件。

> 约定：包含中文的 `.ps1` 必须保存为**带 BOM 的 UTF-8**，否则 Windows PowerShell 5.1 会按系统代码页解码而无法解析脚本。

## 升级

下载新版本的完整包体（zip，或已解压的目录）后，在旧版安装目录运行一次更新器即可，**不需要手动解压覆盖，也不会碰你的文章**：

```powershell
.\Update-ProjectMe.ps1 -Package .\ProjectMe-v1.1.10-Gen2.zip
```

更新器**自带全部所需函数，不加载安装目录里的 `ProjectMe.Common.ps1`**：它运行在旧版本上，而旧版本的公共脚本往往缺少新函数或新参数，依赖它会让更新直接失败。因此无论从多老的版本升级（包括 v1.1.6 这类早于更新器的版本），都能直接运行。

安装目录按以下顺序确定，运行时会先打印「安装目录」与「包体路径」供核对：

1. `-ProjectRoot <目录>` 指定的目录；
2. 当前工作目录（如果它看起来是 ProjectMe 安装目录，即同时有 `project-info.json` 和 `ProjectMe.ps1`）；
3. 更新器脚本所在目录。

路径写错时会打印当前工作目录，并把在安装目录 / 当前目录 / 脚本目录里找到的 `ProjectMe-*.zip` 列出来供核对，而不是只说一句“找不到包体”。

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
- 当前版本：`v1.1.10 Gen2`；本项目不提供自动"更新版本"功能，版本号由维护者手动维护，用户侧用 `Update-ProjectMe.ps1` 应用新包体。
- 示例文章只有"ProjectMe 是什么"和"ProjectMe 更新日志"两篇，后者直接引用根目录的 `CHANGELOG.md`。
- `logs/`、`old/` 与 `.projectme-serve.json` 是本地运行产物，已在 `.gitignore` 中排除。

## 作者与许可证

ProjectMe 由 [tianyimc.com](https://tianyimc.com) 设计与维护。作者主页：<https://tianyimc.com>。

本项目以 [MIT 许可证](https://opensource.org/license/mit) 开放源代码，完整文本见 [`LICENSE`](LICENSE)。你可以自由地使用、修改和分发本项目，只需保留版权声明。

© 2026 [tianyimc.com](https://tianyimc.com) 依据 MIT 许可证开放源代码

## 更新日志

完整记录见 [`CHANGELOG.md`](CHANGELOG.md)。

## 插件设计规范

> 本节是插件开发的**规范性**参考（规范版本 1，对应 ProjectMe v1.1.10 Gen2）。上文「插件」一节是使用说明，两者冲突时以本节为准。
>
> 条款分两级：**【硬性】**违反会导致插件无法安装、无法加载或破坏主程序；**【建议】**违反会影响可维护性与用户体验。

### 1. 定位与设计原则

- 【硬性】插件是运行在**宿主进程内、与宿主同一作用域**的 PowerShell 代码：没有沙箱、没有隔离、没有权限收敛。只安装、只编写可信来源的插件。
- 【硬性】插件是可选增强：被禁用、被删除、损坏或初始化失败时，主程序必须依然完全可用。宿主已保证不执行损坏插件，插件自己也不要把「缺少我」变成主程序的错误。
- 【硬性】插件唯一的持久化位置就是自己的主目录：配置写在 `plugins\<插件名>\config.json`，其余状态自己管理。主程序配置 `projectme.config.json` 与 `project-info.json` 不属于插件。
- 【建议】行为幂等：安装可重装、卸载可恢复，重复执行不产生重复文章、重复时间轴条目或重复副作用。
- 【建议】一个插件只做一件事，入口保持小；复杂逻辑拆到同目录下的其它 `.ps1`，由入口 dot-source。

### 2. 目录与文件布局

```text
plugins/
  <插件名>/                  # 文件夹名 = 插件 Id（权威）
    plugin.json              # 清单，必需
    config.json              # 插件自己的配置，可选（见 §4）
    <名称>.Plugin.ps1        # 入口脚本，文件名由清单 entry 指定
    ...                      # 其它资源、辅助脚本
  <待安装插件>.zip            # 未安装的插件包，由插件管理器扫描
```

- 【硬性】插件主目录 = **包含 `plugin.json` 的那一层**；安装包内必须**恰好只有一个**这样的目录。
- 【硬性】插件 Id 就是**文件夹名**：宿主以文件夹名作为 Id（清单里的 `id` 只是建议值；两者不一致时宿主按文件夹名处理并记警告）。
- 【硬性】`plugins\` 不存在、为空或全部损坏时，主程序照常运行，不报错、不提示缺插件。
- 【硬性】`plugins\` 下的**每个文件夹都必须是插件**（含 `plugin.json`）：主程序运行时会把它标成损坏并跳过，但 `Check-ProjectMe.ps1` 会直接报错。不要往 `plugins\` 里放杂项文件夹（普通文件与 `.zip` 不受影响：非 zip 文件会被管理器忽略）。
- 【建议】插件不要读写 `plugins\` 之外的路径；确需访问外部目录（例如导入源）时，把路径交给用户写在插件自己的 `config.json` 里。
- 【建议】插件要定位自身目录，在入口顶层捕获一次：

  ```powershell
  $DemoPluginRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
  ```

  在插件定义的函数里 `$MyInvocation.MyCommand.Path` 同样指向入口脚本文件，但显式捕获更直观。

### 3. 清单 `plugin.json`

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `entry` | 是 | 入口脚本，**相对插件目录**的路径 |
| `id` | 否 | 插件标识，建议与文件夹名一致 |
| `name` / `version` / `description` | 否 | 管理器与详情展示用 |
| `defaultEnabled` | 否 | 没写 `config.json` 时的默认开关，缺省 `false`（装完默认禁用） |
| `cli.label` | 声明 `cli` 时必填 | CLI 菜单项文字，建议简短 |
| `cli.function` | 声明 `cli` 时必填 | 菜单被选中时**无参**调用的函数名 |
| `gui.controls` | 声明 `gui` 时必填 | 插件占用的已命名 XAML 控件列表（见 §7） |
| `gui.function` | 声明 `gui` 时必填 | 窗口初始化时**无参**调用的函数名 |

校验规则由 `Test-ProjectPluginManifest` 实现，**安装与宿主加载都调用它**；`Check-ProjectMe.ps1` 会按同一套规则再校验一遍（那部分是它自己的实现）。规则是：

- 【硬性】`entry` 非空，且该文件真实存在。
- 【硬性】声明了 `cli` 对象时，`cli.label` 与 `cli.function` 都必须非空。
- 【硬性】声明了 `gui` 对象时，`gui.function` 必须非空，且 `gui.controls` 至少有一个非空项。
- 【硬性】`plugin.json` 必须是合法 JSON，UTF-8 编码。
- 【硬性】只声明自己真正提供的入口：只有 CLI 就只写 `cli`，只有 GUI 就只写 `gui`，两者都有就都写。

最小示例（只提供 CLI 入口）：

```json
{
  "id": "demo",
  "name": "示例插件",
  "version": "1.0.0",
  "description": "统计文章数量，并演示插件自己的 config.json",
  "entry": "Demo.Plugin.ps1",
  "cli": { "label": "示例：统计文章", "function": "Invoke-DemoPlugin" },
  "defaultEnabled": false
}
```

### 4. 插件配置 `config.json` 与启用状态

配置放在插件自己的主目录：`plugins\<插件名>\config.json`。

```json
{
  "enabled": true,
  "sourceRoot": "D:\\Notes",
  "lastRun": ""
}
```

- 【硬性】`enabled`（布尔）是**保留键**，由宿主维护、代表插件开关；插件不得把它当作自己的业务字段或删掉它。
- 【硬性】除 `enabled` 外的键**完全归插件所有**，宿主不解析、不校验、不展示。
- 【硬性】`projectme.config.json` 里不得出现任何插件数据（旧版曾有 `plugins` / `obsidian` 段，现已移除；万一残留会被忽略并写警告）。
- 启用状态优先级：`config.json` 的 `enabled` → 清单的 `defaultEnabled` → `false`。
- 安装与升级：包内自带 `config.json` 就以其为默认值；同名插件升级时**保留本地已有的那一份**；文件不存在时管理器按 `defaultEnabled` 自动生成。
- 【硬性】`config.json` 是**用户数据**：更新器永不覆盖、永不删除；卸载时随插件目录一起移入 `old\removed-plugins\`。

读写配置推荐直接用宿主 API（原子写入，只碰自己那一份）：

```powershell
$config = Get-ProjectPluginConfig -Id 'demo' -Root $root
if ($null -eq $config) { $config = [pscustomobject]@{ enabled = $true } }   # 只有启用时宿主才会调用插件
if ($null -eq $config.PSObject.Properties['lastRun']) { $config | Add-Member -NotePropertyName lastRun -NotePropertyValue '' -Force }
$config.lastRun = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
Save-ProjectPluginConfig -Id 'demo' -Config $config -Root $root
```

- 【硬性】用 `Save-ProjectPluginConfig` 写回时**必须保留 `enabled`**（上面这种「读出来、只改自己的键、再写回」的写法自然满足）。
- 【建议】插件要能容忍用户手改坏的配置：字段缺失、类型不符、整个文件不是合法 JSON 时退回内置默认值并记日志，不要抛错让入口彻底失效。

### 5. 生命周期与失败处理

1. **发现**：宿主扫描 `plugins\` 下每个文件夹，读取清单并给出状态 `ok` / `missing-manifest`（缺 `plugin.json`）/ `invalid-manifest`（清单非法）/ `missing-entry`（入口文件不存在）。
2. **判定启用**：只有状态为 `ok` 的插件才可能启用；任何异常状态的插件一律视为禁用，且**不会执行它的任何代码**，只写一条日志。
3. **加载**：宿主用 dot-source 把启用的入口载入宿主作用域。入口的顶层代码因此会执行；CLI 每次选中插件菜单都会重新 dot-source 一次，所以顶层代码必须**可重复执行**（不要去追加全局列表之类）。
4. **注册**：CLI 追加菜单项（见 §6）；GUI 调用 `gui.function` 并显示 `gui.controls`（见 §7）。
5. **调用**：`cli.function` / `gui.function` 都是**无参**调用，插件函数不要声明必填参数。
6. **失败处理**：插件抛异常时，CLI 记 `ERROR` 日志、在屏幕上提示后回到菜单；GUI 记日志、该插件声明的控件保持隐藏，主程序继续启动。
7. **安全模式**：`ProjectMe.ps1 -SafeMode` / `ProjectMe.Gui.ps1 -SafeMode` 让本次运行把全部插件视为禁用——不加载任何插件代码、不显示任何入口，也**不改写任何配置文件**。插件导致问题时先用它启动排查（CLI 菜单 **14. 插件管理器 → 7. 以安全模式启动** 也能带上这个开关）。

### 6. CLI 插件契约

- 菜单固定为 **1–14**，插件项从 **15** 起，按**文件夹名**排序依次追加。
- 【硬性】菜单编号**不稳定**：有没有其它插件、文件夹怎么命名都会影响编号。插件不得硬编码自己的编号，也不得假定自己在 15。
- 【硬性】`cli.function` 必须无参、可在任何菜单状态下安全调用。
- 【硬性】宿主调用插件后直接回到菜单，**不会**自动暂停。需要用户看完输出再返回时，插件自己要调 `Pause-Menu`。
- 【建议】不要调用 `exit`（那会连同主程序 CLI 一起退出）；只退出插件自己用 `return`。
- 【建议】重要动作写 `Write-ProjectLog`，方便事后排查；面向用户的信息用 `Write-Host`。

插件作用域内可直接使用的宿主能力：

| 类别 | 名称 |
| --- | --- |
| 变量 | `$root`（项目根目录）、`$config` / `$script:config`（主程序配置对象）、`$script:info` / `$info`（项目元数据） |
| 文章 | `Get-Articles`、`Save-Articles`、`Set-ArticlePropertyValue`、`Remove-ProjectArticle` |
| 时间轴 | `Get-Timeline`、`Save-Timeline` |
| 插件自身 | `Get-ProjectPluginConfig`、`Save-ProjectPluginConfig`、`Get-ProjectPluginConfigPath`、`Test-ProjectPluginEnabled`、`Get-ProjectPlugins` |
| 元数据与工具 | `Get-ProjectInfo`、`Get-DisplayVersion`、`Test-ProjectVersion`、`Test-ProjectColor`、`Write-ProjectLog`、`Write-ProjectJsonAtomic`、`Get-CurrentChangelog` |
| 快照 | `Get-SnapshotPath`、`New-ProjectSnapshot`、`Get-VersionSnapshots`、`Restore-ProjectSnapshot` |
| 交互 | `Pause-Menu`、`Clear-Menu` |

【建议】上表之外的同名内部函数（例如各类预览控制、`Read-Optional`）虽然当前也能调用，但**不保证跨版本稳定**，插件应尽量只用上表。

### 7. GUI 插件契约

- 【硬性】GUI 插件不能自己新建 XAML 控件：它只能使用**主程序已经在 `ProjectMe.Gui.xaml` 里声明好**的控件，且这些控件默认带 `Visibility="Collapsed"`。宿主在插件启用并初始化成功后，才按 `gui.controls` 把它们置为 `Visible`——所以插件被禁用或整个目录被删除时，界面上不会残留入口。
- 【硬性】`gui.function` 在窗口初始化阶段无参调用，负责给控件挂事件、填初始内容。调用发生在**控件被显示之前**，所以函数里就应该把控件配置好。
- 【硬性】此阶段文章数据**还没有加载**（`Refresh-Articles` 在插件初始化之后才被调用）。需要使用文章列表的插件要自己先调 `Refresh-Articles`。
- 【硬性】不要声明主程序自己已用的控件（例如 `PluginManagerButton`），那是劫持别人的界面。
- 【建议】控件名全项目唯一；两个插件声明同一控件时，后加载者生效并记警告。
- 【建议】取色用主题资源，不要硬编码颜色，否则深色/浅色主题下不协调：

  ```powershell
  $button.Background = $script:window.Resources['AccentBrush']
  ```

  可用键：`WindowBackground`、`SurfaceBackground`、`SurfaceMuted`、`SidebarBackground`、`SidebarActive`、`SidebarText`、`SidebarMuted`、`TextPrimary`、`TextSecondary`、`BorderBrush`、`InputBackground`、`AccentBrush`、`AccentSoftBrush`、`PurpleBrush`（由 `Set-Theme` 按系统主题写入，另有 `BodyFontFamily`、`TitleFontFamily` 字体资源）。
- 【建议】插件运行在 UI 线程上，耗时操作会卡住界面；长任务请自己开后台作业并回到 Dispatcher 更新界面。

插件作用域内可直接使用的宿主能力：

| 类别 | 名称 |
| --- | --- |
| 控件 | `Get-Control <名称>`、`Set-ControlText <控件> <值>`、`$script:window` |
| 对话框 | `Show-Message`、`Show-Error`、`Show-TextDialog <标题> <文本> [确认按钮文字]` |
| 数据刷新 | `Refresh-Articles`、`Refresh-Timeline`、`Set-Page`（页面名取 `articles` / `maintenance` / `timeline`） |
| 维护动作 | `Run-ProjectCheck`、`Open-Log`、`Start-Preview`、`Stop-Preview` |
| 变量 | `$root`、`$script:config`、`$script:info`、`$script:articles`（插件初始化时为空） |

### 8. 数据访问约定

- 【硬性】文章与时间轴一律走宿主 API：`Get-Articles` / `Save-Articles` / `Set-ArticlePropertyValue` / `Get-Timeline` / `Save-Timeline`。它们负责原子写入，并在保存时把 `tags` 从旧字符串格式统一成数组。
- 【硬性】不要直接写 `articles.json`、`timeline.json`、`projectme.config.json`、`project-info.json`，也不要直接删 `articles\` 下的文件——删除文章要用 `Remove-ProjectArticle`（它会同步维护索引与时间轴，并保证至少留一篇文章）。
- 【建议】给文章加自定义字段时用 `Set-ArticlePropertyValue`；未知字段网页和 CLI 会忽略，不会报错。
- 【硬性】导入类插件的**源数据必须只读**：不得删改、不得移走（例如 Obsidian 库）。写文章时按内容去重，保证重复导入不产生重复文章。
- 【建议】批量改动前先 `New-ProjectSnapshot` 备份一次，失败时用 `Restore-ProjectSnapshot` 恢复。

### 9. 打包与安装

合法的插件包有两种布局，二者等价：

```text
# 布局 A：zip 根目录就是插件主目录
demo.zip
  plugin.json
  Demo.Plugin.ps1

# 布局 B：zip 内恰好一个直接子目录是插件主目录
demo.zip
  demo/
    plugin.json
    Demo.Plugin.ps1
```

安装（`plugins\` 不存在会自动创建）：

```powershell
Compress-Archive -Path .\demo\* -DestinationPath .\demo.zip -Force
.\Manage-Plugins.ps1 -Install .\demo.zip     # 也可以 -Install .\demo（直接给目录）
.\Manage-Plugins.ps1 -Enable demo
```

- 【硬性】包内路径必须安全：拒绝 `..`、绝对路径（含盘符）、`CON`/`NUL`/`COM1` 之类的设备名（由 `Test-ProjectSafeZipEntry` 校验）。
- 【硬性】包内必须**恰好有一个**含 `plugin.json` 的插件主目录，清单与入口都必须有效，否则拒绝安装。
- 【硬性】**安装后默认禁用**（包内自带 `config.json` 时以它的 `enabled` 为准，否则按 `defaultEnabled`）；启用是一件显式动作，由用户决定。
- 同名插件安装按「升级/重装」处理：显示新旧版本、确认后把旧目录移入 `old\removed-plugins\<id>-<时间戳>\`，并**保留本地已有的 `config.json`**。
- 卸载把插件目录（含它自己的 `config.json`）移入 `old\removed-plugins\`，可手工恢复；`-Purge` 才真正删除。
- 【硬性】主程序仓库与发布包体**不含任何插件**：`ProjectMe-v*.zip` 里没有 `plugins\` 目录，插件只通过插件管理器安装。
- 【建议】不打算随仓库分发的插件，请自己把 `plugins/` 加进 `.gitignore`。

### 10. 安全与边界

- 【硬性】插件代码拥有当前用户的完整 PowerShell 能力（可以读写任意文件、启动进程、访问网络）。安装第三方插件前先读一遍它的脚本。
- 【硬性】`entry` 必须是**插件目录内的相对路径**，不得用 `..`、绝对路径或跳转出去（当前宿主不拦这种写法，属于约定；见附录 B）。
- 【硬性】不要修改 `project-info.json`（版本元数据属于主程序与更新器），不要改 `articles\` 之外的他人文件。
- 【建议】日志只写必要信息，不要写入密钥、令牌或隐私路径。
- 【建议】插件要尊重安全模式的语义：被安全模式跳过时，一切照旧，不要在启动阶段抢着做副作用（入口顶层只做定义与轻量初始化）。

### 11. 命名与编码

- 【硬性】含中文的 `.ps1` 必须保存为**带 BOM 的 UTF-8**。不带 BOM 时 Windows PowerShell 5.1 会按系统代码页（简体中文系统为 GBK）解码：**轻则中文全变乱码**（脚本能跑，但输出和字符串都是乱码），**重则直接语法错误**（某个汉字被错误解码后把后面的引号吞掉，脚本整段无法解析，插件会在被选中时报错）。两种情况都会让人误以为"插件坏了"。
- 【硬性】函数与变量加自己的前缀（例如 `Invoke-DemoPlugin`、`$DemoPluginRoot`）。插件是 dot-source 进宿主作用域的：**重名会覆盖**，可能弄坏主程序或其它插件。
- 【建议】入口文件名用 `<名称>.Plugin.ps1`（非强制，但便于一眼认出）。
- 【建议】`plugin.json` / `config.json` 用 UTF-8（有无 BOM 都可以）。
- 【建议】`cli.label` 简短（菜单里和其它 14 项并排显示），需要在菜单里区分时用「来源：动作」的形式。

### 12. 最小示例插件

`plugins\demo\plugin.json`：

```json
{
  "id": "demo",
  "name": "示例插件",
  "version": "1.0.0",
  "description": "统计文章数量，并把运行时间写进插件自己的 config.json",
  "entry": "Demo.Plugin.ps1",
  "cli": { "label": "示例：统计文章", "function": "Invoke-DemoPlugin" },
  "defaultEnabled": false
}
```

`plugins\demo\Demo.Plugin.ps1`：

```powershell
# 入口被宿主 dot-source 时执行一次；函数名带插件前缀，避免与主程序或其它插件重名。
$DemoPluginRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-DemoPlugin {
  $articles = @(Get-Articles -Root $root)
  Write-Host "当前共 $($articles.Count) 篇文章。" -ForegroundColor Cyan

  # 只读写自己的 plugins\<插件名>\config.json，写回时保留 enabled
  $config = Get-ProjectPluginConfig -Id 'demo' -Root $root
  if ($null -eq $config) { $config = [pscustomobject]@{ enabled = $true } }   # 只有启用时宿主才会调用插件
  if ($null -eq $config.PSObject.Properties['lastRun']) { $config | Add-Member -NotePropertyName lastRun -NotePropertyValue '' -Force }
  $config.lastRun = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  Save-ProjectPluginConfig -Id 'demo' -Config $config -Root $root

  Write-Host "插件目录：$DemoPluginRoot"
  Write-ProjectLog "示例插件运行：共 $($articles.Count) 篇文章" 'INFO' $root
  Pause-Menu
}
```

安装并验证：

```powershell
Compress-Archive -Path .\demo\* -DestinationPath .\demo.zip -Force
.\Manage-Plugins.ps1 -Install .\demo.zip     # 装完默认禁用
.\Manage-Plugins.ps1 -Enable demo
.\Manage-Plugins.ps1 -List                   # 应显示 demo 已启用
.\Check-ProjectMe.ps1                        # 会顺带校验插件清单与入口
.\ProjectMe.ps1                              # 菜单 15 起出现「示例：统计文章」
.\ProjectMe.ps1 -SafeMode                    # 安全模式：本次不加载任何插件（排障用）
```

想要 GUI 入口时，除了在清单里声明 `gui`，还必须先由维护者在 `ProjectMe.Gui.xaml` 里预留控件（`x:Name` + 默认 `Visibility="Collapsed"`），例如：

```xml
<Button x:Name="DemoRunButton" Content="统计文章" Visibility="Collapsed"/>
```

```json
"gui": { "controls": [ "DemoRunButton" ], "function": "Initialize-DemoGui" }
```

```powershell
function Initialize-DemoGui {
  $button = Get-Control 'DemoRunButton'          # 找不到只会记警告，不会报错
  if ($null -eq $button) { return }
  $button.Background = $script:window.Resources['AccentBrush']   # 跟随主题，不硬编码颜色
  $button.Add_Click({ Refresh-Articles; Show-Message '文章列表已刷新。' })
}
```

> 当前发布版**没有为第三方插件预留任何 GUI 控件**，所以第三方插件的 GUI 入口暂时不可用；新插件建议先只做 CLI 入口，或与维护者约好预留控件名。

### 13. 提交前检查清单

- [ ] 文件夹名与插件 Id 一致；`plugin.json` 字段齐全且是合法 JSON。
- [ ] `entry` 是插件目录内的相对路径，文件存在；含中文的 `.ps1` 是**带 BOM 的 UTF-8**。
- [ ] 声明的 `cli.function` / `gui.function` 都能**无参**调用；函数与变量都带插件前缀。
- [ ] 入口顶层代码可重复执行（CLI 每次选中都会重新 dot-source）。
- [ ] 只读写自己的 `config.json`，写回时保留 `enabled`；没有往 `projectme.config.json` 里塞数据。
- [ ] 数据改动全部走宿主 API；导入源只读；批量操作前有备份。
- [ ] 抛出异常、写坏配置、缺少宿主函数时，主程序仍能正常使用（只记日志）。
- [ ] 声明了 `gui` 的话：控件已在 `ProjectMe.Gui.xaml` 里预留，且默认 `Collapsed`。
- [ ] `.\Check-ProjectMe.ps1` 通过；`-SafeMode` 下与「没有插件」表现一致。
- [ ] 禁用或删除插件目录后，CLI/GUI 入口都消失，无残留。

### 附录 A：契约实现位置

| 规范条款 | 实现位置 |
| --- | --- |
| 扫描、状态、Id 与文件夹名、启用优先级 | `ProjectMe.Common.ps1` 的 `Get-ProjectPlugins`、`Test-ProjectPluginEnabled`、`Get-ProjectPluginConfig` |
| 清单字段校验 | `ProjectMe.Common.ps1` 的 `Test-ProjectPluginManifest`（安装与宿主加载调用它；`Check-ProjectMe.ps1` 按同一套规则自行校验） |
| 插件配置读写 | `ProjectMe.Common.ps1` 的 `Get-ProjectPluginConfigPath`、`Get-ProjectPluginConfig`、`Save-ProjectPluginConfig`、`Set-ProjectPluginEnabled` |
| CLI 菜单追加与调用 | `ProjectMe.ps1` 的 `Build-MainMenu` 与菜单循环中的插件分支 |
| GUI 控件显示与初始化 | `ProjectMe.Gui.ps1` 的「插件宿主」代码块 |
| 安装 / 升级 / 启用 / 卸载 | `Manage-Plugins.ps1` 的 `Install-PluginPackage`、`Set-PluginEnabledState`、`Uninstall-PluginPackage` |
| 包内路径安全校验 | `ProjectMe.Common.ps1` 的 `Test-ProjectSafeZipEntry` |
| 插件清单、入口与 `config.json` 自检 | `Check-ProjectMe.ps1` |
| 插件 `config.json` 的用户数据保护 | `Update-ProjectMe.ps1` 的 `Test-ProjectProtectedPath`（`^plugins\\[^\\]+\\config\.json$`） |

### 附录 B：当前未强制执行的约定

这些点**规范上要求**，但当前版本没有代码强制；写插件时请自觉遵守：

1. `entry` 可以写成 `..\..\x.ps1` 逃出插件目录，宿主不校验——规范禁止（见 §10）。
2. 清单 `id` 与文件夹名不一致时不会报错：宿主按文件夹名处理并记警告；安装时则按清单 `id` 落成 `plugins\<id>`。
3. `gui.controls` 里声明了不存在的控件只记警告，入口也不会显示。
4. 没有「宿主版本要求」字段（无 `minHostVersion`）。插件应在入口里用 `Get-Command` 自检依赖的宿主函数，缺失时明确报错。
5. 插件之间的函数/变量重名没有检测，会互相覆盖（宿主只对重复的 GUI 控件名发警告）。
6. 第三方插件无法自行新增 GUI 控件或页面，必须由维护者在 `ProjectMe.Gui.xaml` 预留。
7. `plugins/` 不在 `.gitignore` 里：打算只在本地使用的插件，请自行忽略，避免误提交。
