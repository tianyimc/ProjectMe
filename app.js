const app = document.querySelector('#app');
let articles = [];
let projectInfo = { name: 'ProjectMe', version: '1.1.6', generation: 1, author: 'tianyimc.com', copyright: '© 2026 tianyimc.com', title: 'ProjectMe · 个人文集' };

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

async function route() {
  const [path, rawSlug] = location.hash.slice(2).split('/');
  const slug = rawSlug ? decodeURIComponent(rawSlug) : '';
  try {
    if (path === 'article' && slug) await renderArticleInto(app, articles, slug);
    else if (path === 'about') app.innerHTML = `<section class="about-page"><p class="eyebrow">About ${escapeHtml(projectInfo.name)}</p><h1>关于这里</h1><p>${escapeHtml(projectInfo.description || 'ProjectMe 是一份持续更新的个人文集。')}</p><p class="project-meta">版本 ${escapeHtml(displayVersion(projectInfo))} · 作者 ${escapeHtml(projectInfo.author)}<br>${escapeHtml(projectInfo.copyright)}</p></section>`;
    else renderHome();
  } catch (error) {
    app.innerHTML = '<p class="empty">这篇文章暂时无法打开，请检查 Markdown 文件和文章索引。</p>';
    console.error(error);
  }
}

loadSiteData().then((data) => { articles = data.articles; projectInfo = data.projectInfo; applySiteChrome(projectInfo); route(); }).catch(() => { app.innerHTML = '<p class="empty">文章目录暂时无法读取。</p>'; });
window.addEventListener('hashchange', route);
