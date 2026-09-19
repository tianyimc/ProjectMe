# ProjectMe 更新日志

## v1.1.11 Gen2 - 2026-09-19
- **新增 `Start-ProjectMe.bat`：解除 Windows 的「来自 Internet」下载阻止。** 从浏览器下载的包解压后，Windows 会给 `.ps1` 打上 `Zone.Identifier` 标记，此时脚本在 `RemoteSigned` 与 `Restricted` 下都会被拒（`… cannot be loaded`）。该脚本递归对本目录（含 `plugins\`）的 `.ps1` 执行 `Unblock-File` 并打印一行结果，然后停在「按任意键」界面。**只做许可、不做撤销**：停用或卸载插件都不会把许可收回，脚本里也没有任何 Block/撤销逻辑。
- 三个使用时机：① 首次下载后由用户双击一次；② `Update-ProjectMe.ps1` 应用包体成功后自动调用一次；③ `Manage-Plugins.ps1` 安装或启用插件后自动调用一次（禁用/卸载不调用）。后两者用直接调用批处理的方式运行，**复用当前控制台、不弹出新的控制台窗口**（实测：调用前后可见控制台窗口数不变）。
- **兼容性结论（实测）**：升级与装插件产生的文件是本地复制写入的，`Copy-Item` / `WriteAllText` / `Expand-Archive` 都不会带上下载标记，所以解锁是**保险性**措施，用户"只在首次下载/更新/装插件时跑一次"即可，不需要每次启动都跑；`.bat` 不存在时（例如很旧的安装目录）两个调用方都静默跳过。已知边界：被组策略（MachinePolicy/UserPolicy）或 SRP/AppLocker 强制拦截时，`Unblock-File` 与 `-ExecutionPolicy Bypass` 都可能无效。
- **发布包命名**：`New-Release.ps1` 从本版起在 Gen2 及以上把 `Gen<X>` 写进包名与包内顶层目录（`ProjectMe-v1.1.11Gen2.zip`），因此与 Gen1 的 `ProjectMe-v1.1.11.zip` **并存、不再互相覆盖**；Gen1（`generation` 为 1 或缺省）仍是不带后缀的 `ProjectMe-v<版本>.zip`。
- `README.md`「快速开始」新增第一项说明该阻止现象与双击解决方式，「升级」章节补充"更新后无需再手动解锁"，并同步版本规则里的包名规则。
- 版本号提升到 v1.1.11 Gen2（同一个 `C` 内部的第二个修复包）。

## v1.1.11 - 2026-09-19
- **默认附带插件「从 Markdown 拆分导入」**（id `markdown-split-import`，v1.1.0）：把任意 Markdown 文集目录按文件或 Markdown 标题层级拆分成文章后导入项目。发布包在 `plugins\markdown-split-import.zip` 里附带它，装好后默认禁用，启用命令见 `README.md` 的「从 Markdown 拆分导入（插件）」；导入源始终只读，插件设置保存在它自己的 `plugins\markdown-split-import\config.json`（属用户数据，不随包分发）。
- **插件兼容适配（宿主侧）**：`ProjectMe.Gui.xaml` 新增 `CheckBox` / `ComboBox` / `ComboBoxItem` 三个隐式样式，用自绘 `ControlTemplate` 替换 WPF 里写死浅色系统画刷的默认模板。此前插件通过 `gui.panel` 声明的 `checkbox` / `combo` 控件在深色主题下是白底浅字（悬停态与下拉列表同样是白底，控件实例上设 `Background` 也盖不住），现在背景、边框、前景、箭头、悬停与选中态全部走 `DynamicResource` 引用当前调色板，浅色主题同样正常。
- 下拉框的点击面用完全透明的 `ToggleButton` 模板，`PART_Popup` 按 `IsDropDownOpen` 模板绑定，控件命名与 WPF 默认模板一致，不影响既有代码取用模板部件。
- CLI 主菜单的历史遗留项改为中文，与其余菜单项一致：`5. 运行自检`（原 `Check-ProjectMe`）、`6. 新建文章`（原 `New-Article`）、`7. 启动预览`（原 `serve`）；功能与脚本调用不变。
- **更新器不再覆盖已安装的插件**：`Update-ProjectMe.ps1` 原先只保护 `plugins\<插件名>\config.json`，插件目录里的代码会被包体覆盖。现在安装目录里**已经存在**的插件（`plugins\<插件名>\` 整个目录，含入口脚本与配置）一律跳过，包体永不覆盖，插件的启用状态与设置都不会丢；包体携带的**新**插件包（如 `plugins\markdown-split-import.zip`）或本机还没有的插件目录仍会正常落地，更新计划里会单独列出被跳过的插件名。
- 打包改为可复现：新增维护者脚本 `New-Release.ps1`，按 `project-info.json` 的版本生成 `ProjectMe-v<版本>.zip`（包内顶层目录与包同名），默认把 `plugins\` 下的插件包一并打进发布包，并排除 `old\`、`logs\`、`.git\`、`.projectme-serve.json`、`00Bugs.txt`、既有发布包与打包脚本自身。`.gitignore` 补上发布包目录与 `plugins/*.zip`（插件包属构建产物，不入库）。
- `README.md` 的「版本规则」写清楚 `Gen` 的边界：`Gen` 是同一个 `C` 小版本内部更小的修复快照，**`C` 一提升就重置为 `Gen1`**（`1.1.10 Gen3` 的下一版是 `1.1.11`，不是 `1.1.11 Gen4`）。
- 版本号提升到 v1.1.11（新的 `C`，`generation` 重置为 `1`，按规则显示为 `v1.1.11`，不带 `Gen` 后缀）。

## v1.1.10 Gen3 - 2026-09-18
- **新增第三方插件的 GUI 契约：插件不再需要维护者改 `ProjectMe.Gui.xaml`**。此前规范只允许插件声明「主程序已预留的 XAML 控件名」，而发布版没有为任何第三方插件预留控件，于是「从 Obsidian 导入」这类插件只能退回 CLI，GUI 入口无法合规保留。现在插件在 `plugin.json` 里用 `gui.panel` 声明自己需要的控件，由宿主在运行时创建。
- 宿主在 `ProjectMe.Gui.ps1` 里按 `gui.function` + `gui.panel` 现造控件：类型支持 `button` / `checkbox` / `textbox` / `text` / `combo`，可选 `content`、`width`、`tooltip` 与 `page`（`maintenance` / `articles` / `plugin`，输入类控件默认落在文章页）。控件由宿主套用主题配色，插件不用碰 XAML 也不用硬编码颜色。
- `ProjectMe.Gui.xaml` 预留了插件界面：侧栏「插件」导航项、插件页（`PluginsNavButton`、`PluginPage`、`PluginPagePanel`、`PluginHeaderPanel`）和维护页 / 文章页的插件入口区（`MaintenancePluginHostPanel`、`PluginMaintenancePanel`、`PluginArticlesPanel`），全部默认 `Visibility="Collapsed"`。没有任何启用的 GUI 插件时，界面与「没有插件」完全一致。
- 控件名由控件 id 稳定推导（`<id>_button`、`<id>_input`、`<id>_check`、`<id>_select`、`<id>_text`）；插件可以 `Get-Control 'run_button'`，也可以用新增的 `Get-PluginControl 'run'` 直接按 id 取用，`Set-PluginControlVisible` 可按 id 显示或隐藏自己的入口。
- 入口只在插件初始化成功后才显示；插件抛异常时它申请的控件会被撤销并移出界面，只写一条日志，主程序继续启动。控件名与主程序或其它插件冲突时跳过该控件并记警告，不再让 `RegisterName` 抛异常带走整个插件。
- 新增宿主能力探测 `Test-PluginHostFeature`（`gui-panel` / `gui-page` / `plugin-nav`），插件可据此判断宿主是否支持新契约，再决定是否注册 GUI 入口。
- `Check-ProjectMe.ps1` 按同一套规则校验清单里的 `gui.panel`：id 非空且唯一、类型合法、`button` 必须有 `content`、`page` 合法，并允许「只声明 `gui.controls`」的旧写法。
- `README.md` 的插件设计规范更新到规范版本 2：新增 `gui.panel` 字段说明、§7 的完整 GUI 契约、最小示例插件的 GUI 入口示例，并删去「发布版没有为第三方插件预留任何 GUI 控件」的旧结论。
- 版本号提升到 v1.1.10 Gen3。

## v1.1.10 Gen2 - 2026-09-15
- **修复更新器在旧版本安装目录中必失败的问题**：`Update-ProjectMe.ps1` 原先会加载安装目录里的 `ProjectMe.Common.ps1`，而更新器天生要在旧版本上运行——旧 Common 缺少新函数或新参数（例如 v1.1.6 没有 `Test-ProjectSafeZipEntry`，`New-ProjectSnapshot` 不支持 `-Exclude`，`Get-SnapshotPath` 不支持 `-Label`），于是更新在第一步就报“无法将 … 项识别为 cmdlet、函数、脚本文件或可运行程序的名称”，任何版本跨度的更新都无法完成。
- 更新器改为**自带全部所需实现**，不再依赖安装目录里的 `ProjectMe.Common.ps1`，只依赖 Windows PowerShell 5.1 本身；同时把 `-WhatIf`、插件配置保护、精确回滚等既有行为原样保留（函数使用 `Update-` 前缀，避免覆盖宿主函数）。
- 更新器定位安装目录的顺序改为：`-ProjectRoot` → 当前工作目录（若它是 ProjectMe 安装目录）→ 脚本所在目录，并在开头打印「安装目录」与「包体路径」；相对路径按当前工作目录解析。
- 找不到包体时给出可执行的提示：打印当前工作目录，并列出安装目录 / 当前目录 / 脚本目录里找到的 `ProjectMe-*.zip`，避免因路径写错而误判。
- 停止本地预览时更保守：只结束**确实在监听该项目预览端口**的 PowerShell 进程，不再仅凭状态文件里的 PID 结束进程（PID 可能已被无关程序复用）。
- 修复回滚路径的隐患：备份 zip 里的嵌套条目名用的是反斜杠（`articles\my-note.md`），而精确回滚按正斜杠比较条目名，于是“备份里明明存在的文件”会被判为不存在、进而被**删除**；现在两边归一化后再比较，回滚真正把文件还原成更新前的样子。
- `Manage-Plugins.ps1` 在加载前先只读检查公共脚本：安装目录里的 `ProjectMe.Common.ps1` 解析失败（旧版本常见：含中文却没有 BOM）或缺少插件宿主 API 时，直接给出「请先运行 `Update-ProjectMe.ps1` 更新项目」的提示，而不是抛出一堆难以理解的解析错误。
- 版本号提升到 v1.1.10 Gen2。

## v1.1.10 - 2026-09-14
- **本版本不随包提供任何插件**：“从 Obsidian 导入”插件尚未完善（格式兼容与文章拆分规则尚未定型），故暂不提供；仓库中不再包含它的任何内容（插件本体、GUI 控件与相关配置一并移除）。
- 插件配置改由插件自己提供：统一放在 `plugins\<插件名>\config.json`，主程序配置 `projectme.config.json` 不再保存任何插件数据（`plugins.*` 与 `obsidian.*` 段一并移除）。
- 插件开关 `enabled` 归入插件自己的 `config.json`；安装后默认禁用（包内自带 `config.json` 时使用其默认值，缺失时自动按规范生成）。
- 插件管理器：升级安装时保留本地已有的 `config.json`；卸载时配置随插件目录一起移入 `old\removed-plugins\`；`-List` / 详情显示插件配置路径。
- 无损更新器把 `plugins\<插件名>\config.json` 纳入用户数据保护，永不覆盖、永不删除。
- `Check-ProjectMe.ps1` 新增插件 `config.json` 的 JSON 校验。
- 版本号提升到 v1.1.10。

## v1.1.9 - 2026-09-14
- 新增插件管理器 `Manage-Plugins.ps1`：启动即扫描 `plugins\`，文件夹显示为“已安装插件”、zip 显示为“发现的未安装插件”。
- 支持安装（解压并校验包内结构）、启用、禁用、卸载插件，全部通过脚本完成，无需手改 `projectme.config.json`。
- 安装后默认禁用；同名插件按升级处理，旧目录移入 `old\removed-plugins\` 并保留原启用状态；卸载同样可恢复（`-Purge` 才永久删除）。
- 新增「安全模式」：`ProjectMe.ps1 -SafeMode` / `ProjectMe.Gui.ps1 -SafeMode` 本次运行忽略全部插件且不改配置；管理器可直接以安全模式启动 CLI/GUI。
- CLI 主菜单新增 `14. 插件管理器`，从管理器返回后菜单立即刷新；GUI 维护页新增「插件管理器」按钮。
- `ProjectMe.Common.ps1`：插件清单增加 `Status`/`Problem`（损坏插件会被列出而不是静默跳过，且不会被执行），新增 `Set-ProjectPluginEnabled`、`Remove-ProjectPluginSetting`，zip 路径校验改为全项目共享。
- 版本号提升到 v1.1.9。

## v1.1.8 - 2026-09-14
- 新增无损更新器 `Update-ProjectMe.ps1`：下载新版本包体后运行一次即可升级程序文件，无需手动解压覆盖。
- 更新器永不写入、永不删除用户数据（`articles/`、`articles.json`、`timeline.json`、`projectme.config.json`、`.gitignore`、`logs/`、`old/`、`.git/`），包体即使带有同名文件也会跳过。
- `project-info.json` 采用合并策略：版本号取自包体，本地自定义的标题、作者、版权等保持不变。
- 本地内容与包体不同的文件会逐个询问“保留本地版本 / 用包体覆盖”，也可用 `-Overwrite`、`-KeepLocal`、`-Keep` 或配置项 `update.keep` 预设。
- 更新前自动在 `old/` 生成完整备份（`...-preupdate.zip`），写入过程失败时按文件精确回滚；更新结束后自动运行项目自检。
- 版本号提升到 v1.1.8。

## v1.1.7 - 2026-09-14
- 新增插件机制：插件统一放在 `plugins/` 目录，每个插件一个文件夹，由 `projectme.config.json` 的 `plugins.<插件名>.enabled` 启用或关闭。
- “从 Obsidian 导入”改为插件 `plugins/obsidian-import/`，导入逻辑与行为保持不变，默认关闭。
- 插件不存在、被禁用或初始化失败时，CLI 菜单与 WPF GUI 都不再显示对应入口；插件加载失败只记录日志，不影响其它功能。
- CLI 主菜单调整为 1–13 固定项加动态插件项；`Check-ProjectMe.ps1` 增加插件清单校验。
- 版本号提升到 v1.1.7。

## v1.1.6 - 2026-09-11
- CLI 与 WPF GUI 新增文章删除功能；删除会同步清理文章索引、Markdown 正文和时间轴条目，并通过二次确认避免误删。
- WPF GUI 新增“默认 Obsidian 导入源”设置，可从“预览与维护 → Obsidian 导入”保存或清除。
- 从 Obsidian 导入时，目录选择窗口会默认定位到已保存的导入源；临时选择其他目录不会覆盖默认设置。

## v1.1.5 Gen2 - 2026-09-10
- 修复关闭 WPF 界面后预览仍驻留后台的问题，关闭时会按状态文件及 4173、4174 端口清理残留监听进程。
- “预览与维护 → 本地预览”新增“强停所有预览”，确认后强制停止 4173、4174 端口上的进程。

## v1.1.5 - 2026-09-10
- WPF 文章管理面板默认恢复为 Obsidian 导入顺序，只有点击列表头时才临时切换排序字段。

## v1.1.4 Gen2 - 2026-09-10
- 文集主页分页控件水平居中，页码按钮改为与页面背景相近的浅色样式。
- 修复停止预览后端口未释放的问题，停止时会清理实际监听端口的残留进程并同步移除状态文件。

## v1.1.4 - 2026-09-10
- 文集主页按 20 篇一页分页展示，搜索和主题筛选后保持分页。
- 修复 Obsidian 增量导入覆盖已修改文章属性的问题，重复导入保留已有属性。
- Obsidian 增量导入改为比对正文内容，来源内容变化时同步更新对应 Markdown 文件。
- 完善文章页 Markdown 视觉渲染，支持标题层级、斜体、高亮、删除线、列表、引用、图片、代码块和分割线。

## v1.1.3 - 2026-09-07
- 前端文章详情页不再显示索引中的预计阅读时间。
- 使用文章日期替换原预计阅读时间位置，无日期信息时保持留空。
- 保留 `articles.json` 中的 `readingTime` 数据及管理端编辑功能。

## v1.1.2 Gen2 - 2026-09-07
- 修复打开 WPF 时间轴页面时 PowerShell `if` 表达式导致 GUI 崩溃的问题。
- 兼容 Windows PowerShell 5.1 的时间轴状态和默认值处理。

## v1.1.2 - 2026-09-07
- 修复文章管理副标题在窗口缩放时显示不全的问题。
- 在 WPF GUI 中新增 Obsidian 导入入口，支持预览确认后正式导入。
- 新增独立时间轴页面，支持搜索、选入、编辑、启用/禁用和移除条目。
- 新增预览与维护页面，整合项目维护、版本更新和版本回滚功能。
- 保留底部预览快捷栏，版本更新和回滚不加入快捷栏。

## v1.1.1 Gen2 - 2026-09-07
- 修复 WPF 主题资源颜色未转换为画刷导致 GUI 无法启动的问题。
- 接入 `fonts\` 目录中的思源黑体 Normal 与 Medium 字体。
- 改善窗口最小尺寸、编辑区留白、文章列表换行和文本工具提示，避免文字显示不全。

## v1.1.1 - 2026-09-07
- 用 PowerShell + XAML 重做 GUI 管理器，替换默认 WinForms 界面。
- 新增可调整大小的 WPF 工作台、DataGrid 文章列表、统一资源样式和系统主题跟随。
- 保留文章编辑、新建文章、预览服务、自检、日志和正文打开功能。
- 保留 `ProjectMe.Gui.WinForms.ps1` 作为兼容性入口。

## v1.1.0 - 2026-09-07
- 【重要版本更新】新增 Windows GUI 窗口管理器，支持文章搜索、属性编辑、新建文章、本地预览、自检和日志入口。
- CLI 主菜单新增 GUI 启动入口。
- 重构 README，补充快速开始、文件结构、数据约定、配置和版本规则。
- 版本号提升到 v1.1.0，表示重要功能更新。

## v1.0.9 Gen2 - 2026-09-06
- 修复主题标签读取时被错误复制到全部文章，导致 CLI 编辑提示重复显示标签的问题。
- 保留网页对历史字符串标签的兼容处理，同时避免读取文章时修改标签集合。

## v1.0.9 - 2026-09-06
- 修复 CLI 编辑文章属性后将单个主题标签保存为字符串，导致网页首页渲染失败的问题。
- 增加网页和 CLI 对历史字符串标签的兼容处理，并统一将标签保存为数组。

## v1.0.8 - 2026-09-06
- 新增 `projectme.config.json`，支持手动设置 CLI 默认配置。
- serve 默认模式改为后台运行。
- 修复 CLI 日志显示乱码，并兼容旧日志文件。
- 时间轴菜单返回选项改为 `0`。

## v1.0.7 - 2026-09-06
- 修复时间轴编辑器返回菜单时未清理上一组选项输出的问题。
- 前台 serve 改为独立窗口运行，关闭服务窗口即可停止服务并返回 CLI。

## v1.0.6 - 2026-09-05
- 新增 README 版本更新历史记录。
- 手动更新版本时要求填写更新日志，并在 CLI 关于页显示当前版本日志。
- 统一作者署名和版权信息为 [tianyimc.com](https://tianyimc.com)。
- 测试版本更新和回滚的版本。

## v1.0.5 - 2026-09-05
- 新增手动版本更新、ZIP 快照和版本回滚功能。
- 新增 `old/` 版本快照与 `old/reseted/` 回滚前备份机制。

## v1.0.4 - 2026-09-05
- 新增时间轴维护功能和历史文章页面。
- 增加时间轴条目的选择、编辑、移除和日期排序能力。

## v1.0.3 - 2026-09-05
- 新增 CLI 日志记录和日志查看入口。
- 改进 Obsidian 导入错误提示和失败日志。

## v1.0.2 - 2026-09-05
- 前台 serve 支持独立窗口关闭退出。
- 汉化 New-Article 交互提示。
- 在 CLI 中增加 Obsidian 导入入口。

## v1.0.1 - 2026-09-05
- 修复旧文章缺少 `titleFont` 和 `titleColor` 字段时无法编辑的问题。
- 新增CLI控制台。

## v1.0.0 - 2026-09-05
- ProjectMe文集核心发布。
