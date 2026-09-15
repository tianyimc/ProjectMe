const app = document.querySelector('#app');
let articles = [];
let projectInfo = { name: 'ProjectMe', version: '1.1.10', generation: 2, author: 'tianyimc.com', authorUrl: 'https://tianyimc.com', copyright: '© 2026 tianyimc.com 依据 MIT 许可证开放源代码', license: 'MIT', licenseName: 'MIT 许可证', licenseUrl: 'https://opensource.org/license/mit', description: '一个无后端依赖的文集项目：网页负责阅读，CLI 与 WPF GUI 负责维护。', title: 'ProjectMe · 个人文集' };

function renderHome() {
  const orderedArticles = [...articles].sort((a, b) => (b.order ?? -1) - (a.order ?? -1));
  const tags = [...new Set(orderedArticles.flatMap((article) => articleTags(article)))];
  app.innerHTML = `<section class="intro"><div><p class="eyebrow">A personal collection</p><h1>把走过的路，<br>写成自己的地图。</h1></div><div class="intro-copy"><p>这里收集一些正在形成的想法、生活的切片，以及那些值得被重新理解的时刻。</p></div></section><section class="toolbar"><span class="section-label" id="result-count">全部文章 · ${orderedArticles.length}</span><div class="filters"><label for="search-input">搜索</label><input id="search-input" class="search-input" type="search" placeholder="标题、摘要或标签" autocomplete="off"><label for="tag-filter">主题</label><select id="tag-filter"><option value="all">全部主题</option>${tags.map((tag) => `<option value="${escapeHtml(tag)}">${escapeHtml(tag)}</option>`).join('')}</select></div></section><section class="article-list" id="article-list"></section><nav class="article-pagination" id="article-pagination" aria-label="文章分页"></nav>`;
  const list = document.querySelector('#article-list');
  const resultCount = document.querySelector('#result-count');
  const pagination = document.querySelector('#article-pagination');
  const pageSize = 20;
  let page = 1;
  const renderList = (selected = 'all', query = '', resetPage = false) => {
    const normalizedQuery = query.trim().toLowerCase();
    const visible = orderedArticles.filter((article) => {
      const tagsForArticle = articleTags(article);
      const matchesTag = selected === 'all' || tagsForArticle.includes(selected);
      const searchableText = [article.title, article.excerpt, article.category, ...tagsForArticle].join(' ').toLowerCase();
      return matchesTag && (!normalizedQuery || searchableText.includes(normalizedQuery));
    });
    const totalPages = Math.max(1, Math.ceil(visible.length / pageSize));
    if (resetPage) page = 1;
    if (page > totalPages) page = totalPages;
    resultCount.textContent = `${normalizedQuery || selected !== 'all' ? '筛选结果' : '全部文章'} · ${visible.length}`;
    const start = (page - 1) * pageSize;
    const pageArticles = visible.slice(start, start + pageSize);
    list.innerHTML = pageArticles.length ? pageArticles.map((article) => `<article class="article-row"><div class="article-main"><h2><a style="${article.titleFont ? `font-family:${article.titleFont};` : ''}${article.titleColor ? `color:${article.titleColor};` : ''}" href="#/article/${encodeURIComponent(article.slug)}">${escapeHtml(displayTitle(article.title))}</a></h2><p class="article-excerpt">${escapeHtml(article.excerpt)}</p></div><div class="article-meta"><div class="meta-group"><span class="meta-label">主题</span><div class="meta-values">${articleTags(article).map((tag) => `<span class="tag">${escapeHtml(tag)}</span>`).join('')}</div></div>${article.section ? `<div class="meta-group"><span class="meta-label">节</span><span class="section-value">${escapeHtml(article.section)}</span></div>` : ''}</div></article>`).join('') : '<p class="empty">还没有这个主题的文章。</p>';
    if (visible.length === 0) { pagination.innerHTML = ''; return; }
    const pageButtons = Array.from({ length: totalPages }, (_, index) => index + 1).map((number) => `<button type="button" class="${number === page ? 'active' : ''}" data-page="${number}" aria-label="第 ${number} 页"${number === page ? ' aria-current="page"' : ''}>${number}</button>`).join('');
    pagination.innerHTML = `<button type="button" class="page-nav" data-page="${page - 1}" ${page === 1 ? 'disabled' : ''} aria-label="上一页">上一页</button><span class="page-status">第 ${page} / ${totalPages} 页</span><div class="page-numbers">${pageButtons}</div><button type="button" class="page-nav" data-page="${page + 1}" ${page === totalPages ? 'disabled' : ''} aria-label="下一页">下一页</button>`;
    pagination.querySelectorAll('button').forEach((button) => button.addEventListener('click', () => {
      const targetPage = Number(button.dataset.page);
      if (targetPage >= 1 && targetPage <= totalPages) { page = targetPage; renderList(selected, query); }
    }));
  };
  renderList();
  const tagFilter = document.querySelector('#tag-filter');
  const searchInput = document.querySelector('#search-input');
  tagFilter.addEventListener('change', () => renderList(tagFilter.value, searchInput.value, true));
  searchInput.addEventListener('input', () => renderList(tagFilter.value, searchInput.value, true));
}

function renderAbout() {
  const description = projectInfo.description || 'ProjectMe 是一个无后端依赖的文集项目。';
  app.innerHTML = `<section class="about-page">
    <p class="eyebrow">About ${escapeHtml(projectInfo.name)}</p>
    <h1>关于 ProjectMe</h1>
    <p class="about-lead">${escapeHtml(description)}</p>
    <h2>项目是什么</h2>
    <p>ProjectMe 把文章正文、文章索引和维护工具放在同一个目录里：网页负责阅读，命令行与图形界面负责维护。它不依赖数据库、构建工具或第三方运行库，克隆下来就能直接使用。</p>
    <ul class="about-list">
      <li><strong>文集核心</strong>：基于原生 HTML、CSS 与 JavaScript 实现，没有后端依赖，也不需要构建步骤，任何静态托管都能直接发布。</li>
      <li><strong>命令行管理器</strong>：基于 PowerShell，负责文章索引、时间轴、本地预览、项目自检和版本回滚，并通过插件扩展额外能力。</li>
      <li><strong>GUI 管理器</strong>：基于 WPF + PowerShell 的 Windows 工作台，把同样的维护能力做成可搜索、可编辑的窗口界面。</li>
      <li><strong>插件</strong>：可选能力放在 <code>plugins/</code> 目录，每个插件一个文件夹，配置也放在插件自己的 <code>config.json</code> 里；未启用的插件不会在 CLI 或 GUI 中显示入口。本版本不随包提供任何插件。</li>
      <li><strong>数据</strong>：正文是 Markdown，索引是 JSON，全部是可读的纯文本，便于长期保存、迁移和版本管理。</li>
    </ul>
    <h2>关于作者</h2>
    <p>ProjectMe 由 ${authorLinkHtml(projectInfo)} 设计与维护。项目的出发点是：写作的产物应该以最简单、最容易被长期保存的形式存在，工具负责把它们整理好，而不是把它们锁进某个平台。</p>
    <p>如果你在使用中遇到问题，或者想了解作者的更多内容，欢迎访问 ${authorLinkHtml(projectInfo, '作者主页')}。</p>
    <h2>许可证与版权</h2>
    <p>ProjectMe 以 ${licenseLinkHtml(projectInfo)} 开放源代码，你可以自由地使用、修改和分发本项目，只需保留版权声明。</p>
    <p class="project-meta">版本 ${escapeHtml(displayVersion(projectInfo))}<br>作者 ${authorLinkHtml(projectInfo)}<br>${copyrightHtml(projectInfo)}<br>许可证：${licenseLinkHtml(projectInfo)}</p>
  </section>`;
}

async function route() {
  const [path, rawSlug] = location.hash.slice(2).split('/');
  const slug = rawSlug ? decodeURIComponent(rawSlug) : '';
  try {
    if (path === 'article' && slug) await renderArticleInto(app, articles, slug);
    else if (path === 'about') renderAbout();
    else renderHome();
  } catch (error) {
    app.innerHTML = '<p class="empty">这篇文章暂时无法打开，请检查 Markdown 文件和文章索引。</p>';
    console.error(error);
  }
}

loadSiteData().then((data) => { articles = data.articles; projectInfo = data.projectInfo; applySiteChrome(projectInfo); route(); }).catch(() => { app.innerHTML = '<p class="empty">文章目录暂时无法读取。</p>'; });
window.addEventListener('hashchange', route);
