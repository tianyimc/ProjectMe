const app = document.querySelector('#app');
let articles = [];

function formatDate(date) {
  if (!date) return '日期待补';
  const [year, month, day] = [date.slice(0, 4), date.slice(4, 6), date.slice(6, 8)];
  return day ? `${year}年${Number(month)}月${Number(day)}日` : `${year}年`;
}

function renderHistory(entries) {
  const articleBySlug = new Map(articles.map((article) => [article.slug, article]));
  const active = entries.filter((entry) => !entry.disabled).map((entry) => ({ ...entry, article: articleBySlug.get(entry.slug) })).filter((entry) => entry.article).sort((a, b) => (a.date || a.article.date || '99999999').localeCompare(b.date || b.article.date || '99999999') || ((b.priority ?? 1) - (a.priority ?? 1)));
  const years = [...new Set(active.map((entry) => (entry.date || entry.article.date || '').slice(0, 4)).filter(Boolean))];
  const seenYears = new Set();
  app.innerHTML = `<section class="history-intro"><div><p class="eyebrow">A selected history</p><h1>那些改变了<br>方向的文章。</h1></div><p class="history-lead">这不是完整的编年史，而是由我主动挑出的节点：一些文章在这里获得新的位置，也重新照亮它们发生过的时间。</p></section>${active.length ? `<section class="history-toolbar"><span class="section-label">历史文章 · ${active.length}</span><div class="history-controls"><nav class="year-nav" aria-label="年份导航">${years.map((year) => `<a href="#year-${year}">${year}</a>`).join('')}</nav><label class="sr-only" for="history-search">搜索历史文章</label><input id="history-search" class="search-input" type="search" placeholder="搜索时间轴" autocomplete="off"></div></section><section class="timeline" id="timeline-list">${active.map((entry) => { const date = entry.date || entry.article.date; const year = (date || '').slice(0, 4) || '待定'; const anchor = seenYears.has(year) ? '' : ` id="year-${year}"`; seenYears.add(year); return `<article class="timeline-item"${anchor}><div class="timeline-date">${formatDate(date)}</div><div class="timeline-marker" aria-hidden="true"></div><div class="timeline-content"><p class="eyebrow">${escapeHtml(entry.article.category || '历史文章')}</p><h2><a href="index.html#/article/${encodeURIComponent(entry.article.slug)}">${escapeHtml(displayTitle(entry.article.title))}</a></h2>${entry.description ? `<p>${escapeHtml(entry.description)}</p>` : ''}</div></article>`; }).join('')}</section>` : '<section class="history-empty"><h2>时间轴还没有文章</h2><p>请在 CLI 主菜单中进入“时间轴”，使用 select 主动选择历史文章。</p><code>ProjectMe.ps1 → 时间轴 → select</code></section>'}`;
  const search = document.querySelector('#history-search');
  if (search) search.addEventListener('input', () => { const query = search.value.trim().toLowerCase(); document.querySelectorAll('.timeline-item').forEach((item) => { item.hidden = query && !item.textContent.toLowerCase().includes(query); }); });
}

loadSiteData().then(async ({ articles: loadedArticles, projectInfo }) => {
  articles = loadedArticles; applySiteChrome(projectInfo); document.title = `${projectInfo.name} · 历史时间轴`;
  const response = await fetch('timeline.json');
  const data = response.ok ? await response.json() : { entries: [] };
  renderHistory(data.entries || []);
}).catch(() => { app.innerHTML = '<p class="empty">历史时间轴暂时无法读取。</p>'; });
