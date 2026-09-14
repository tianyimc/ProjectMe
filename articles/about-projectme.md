# ProjectMe 是什么

> 一个无后端依赖的文集项目：网页负责阅读，CLI 与 GUI 负责维护。

ProjectMe 把文章正文、文章索引和维护工具放在同一个目录里。它不需要数据库、构建工具或第三方运行库：文章是 Markdown，索引是 JSON，界面是原生的 HTML、CSS 和 JavaScript，管理端是 PowerShell。

这套结构的目标很直接——**你的文字应该以最容易被长期保存的格式存在**。即使十年后网页技术换了模样，`articles/` 里的 Markdown 和 `articles.json` 里的 JSON 依然可以被任何工具读取。

## 三个组成部分

### 文集核心（静态网页）

`index.html`、`app.js`、`site-common.js` 和 `styles.css` 构成阅读界面，支持：

- 文集首页的文章列表、主题筛选、搜索和分页；
- 文章详情页的 Markdown 渲染，涵盖标题、列表、引用、代码块、图片、链接、高亮与删除线；
- `history.html` 历史时间轴页面，用来标记那些"改变了方向"的文章。

它是一组纯静态文件，直接放在 GitHub Pages、Netlify 或任意静态托管上就能访问。

### 管理核心（PowerShell CLI）

`ProjectMe.ps1` 是交互式控制台，适合脚本化和完整的日常维护：文章列表、属性编辑、删除文章、时间轴管理、本地预览、日志查看、项目自检和版本回滚。启用的插件会作为额外的菜单项追加在固定项之后。

### GUI 管理器（Windows WPF）

`ProjectMe.Gui.ps1` 配合 `ProjectMe.Gui.xaml` 提供窗口化管理：文章搜索与排序、属性编辑、新建与删除、时间轴编辑、本地预览、自检、日志和版本回滚。界面会跟随 Windows 的浅色/深色主题，并使用 `fonts/` 目录中的思源黑体。插件可以按自己的开关往界面上增加入口，未启用的插件不会出现在窗口里。

## 数据文件

ProjectMe 的全部状态都由这几个可读文件描述：

- `articles.json`：文章目录属性，每篇文章是一条记录；
- `articles/`：Markdown 正文，一个文件对应一篇文章；
- `timeline.json`：历史时间轴的条目、日期与说明；
- `project-info.json`：项目名称、版本、作者与描述；
- `projectme.config.json`：端口、文章列表和新文章的默认配置。

每条文章记录至少需要 `slug`、`title`、`category`、`tags`、`readingTime`、`excerpt` 和 `file`。`file` 默认指向 `articles/` 下的 Markdown 文件；如果记录里额外提供了 `path`，网页会直接读取该仓库相对路径——本仓库的"ProjectMe 更新日志"文章就是这样复用根目录 `CHANGELOG.md` 的，更新日志只有一份。

## 快速开始

启动 GUI：

```powershell
.\ProjectMe.Gui.ps1
```

启动 CLI：

```powershell
.\ProjectMe.ps1
```

预览网页：

```powershell
.\serve.ps1
```

然后打开 `http://localhost:4173/`。也可以先运行 `.\Check-ProjectMe.ps1` 检查索引、正文、必要字段和时间轴引用是否一致。

## 新建自己的文章

```powershell
.\New-Article.ps1 `
  -Slug "my-first-note" `
  -Title "我的第一篇文章" `
  -Category "随笔" `
  -Excerpt "文章摘要" `
  -Tags "成长", "写作"
```

脚本会创建 `articles/my-first-note.md` 并写入索引。之后直接编辑 Markdown 正文，标题、摘要、标签等目录属性交给 CLI 或 GUI 维护。

## 插件

可选能力以插件形式放在 `plugins/` 目录，每个插件一个文件夹，插件主目录就是包含 `.ps1` 文件的那一层。插件的配置也放在它自己的目录里（`plugins\<插件名>\config.json`），主程序配置 `projectme.config.json` 只保存主程序设置：

```json
{ "enabled": false }
```

`enabled` 是宿主维护的保留键，其余键归插件自己使用。插件不存在、被禁用或初始化失败时，CLI 与 GUI 都不会显示它的入口；安装、启用、禁用、卸载都可以交给根目录的 `Manage-Plugins.ps1` 完成。

**本版本不随包提供任何插件。** “从 Obsidian 导入”插件仍在完善中（格式兼容与拆分规则尚未定型），因此暂不提供，仓库里也不包含它的内容。

## 适合谁

- 想要一份**长期可迁移**的个人文集，而不想把文字锁进某个平台的人；
- 喜欢纯文本工作流，希望用 Obsidian 写作、用静态站点发布的人；
- 想在 Windows 上顺手维护内容，又不想为此引入 Node、Python 或数据库的开发者。

## 关于这个仓库

仓库名称为 `ProjectMe`。正文的示例文章只有本介绍和"ProjectMe 更新日志"两篇，后者直接引用仓库根目录的 [`CHANGELOG.md`](CHANGELOG.md)，因此更新日志始终只有一份。

本项目不提供自动"更新版本"能力：版本号由维护者手动维护，避免工具在读者机器上生成项目快照；版本回滚仍然保留。

## 作者与许可证

ProjectMe 由 [tianyimc.com](https://tianyimc.com) 设计与维护。作者主页：`https://tianyimc.com`。

本项目以 [MIT 许可证](https://opensource.org/license/mit) 开放源代码，完整文本见仓库根目录的 `LICENSE`。你可以自由地使用、修改和分发本项目，只需保留版权声明。

© 2026 [tianyimc.com](https://tianyimc.com) 依据 MIT 许可证开放源代码

完整版本历史见"ProjectMe 更新日志"一文，或直接查看仓库根目录的 [`CHANGELOG.md`](CHANGELOG.md)。
