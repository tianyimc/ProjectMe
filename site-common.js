function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[char]));
}

function displayTitle(value) {
  return String(value ?? '').replace(/\*/g, '');
}

function formatArticleDate(value) {
  const raw = String(value ?? '').trim();
  if (!raw) return '';
  const normalized = raw.replace(/[.\/-]/g, '');
  if (/^\d{8}$/.test(normalized)) {
    return `${normalized.slice(0, 4)}年${Number(normalized.slice(4, 6))}月${Number(normalized.slice(6, 8))}日`;
  }
  return raw;
}

function articleTags(article) {
  if (Array.isArray(article?.tags)) return article.tags;
  if (typeof article?.tags === 'string' && article.tags.trim()) return [article.tags];
  return [];
}

function inlineMarkdown(value) {
  const tokens = [];
  const protect = (html) => {
    tokens.push(html);
    return `\uE000${tokens.length - 1}\uE001`;
  };
  const safeUrl = (url) => /^(javascript|data|vbscript):/i.test(String(url).trim()) ? '#' : url;
  let html = escapeHtml(value)
    .replace(/`([^`\n]+)`/g, (_, code) => protect(`<code>${code}</code>`))
    .replace(/!\[([^\]]*)\]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)/g, (_, alt, src) => protect(`<img src="${safeUrl(src)}" alt="${alt}" loading="lazy">`))
    .replace(/\[([^\]]+)\]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)/g, (_, label, url) => protect(`<a href="${safeUrl(url)}" target="_blank" rel="noopener noreferrer">${label}</a>`))
    .replace(/==([^=\n]+)==/g, '<mark>$1</mark>')
    .replace(/~~([^~\n]+)~~/g, '<del>$1</del>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/__([^_]+)__/g, '<strong>$1</strong>')
    .replace(/(^|[^*])\*([^*\n]+)\*/g, '$1<em>$2</em>')
    .replace(/(^|[^_\w])_([^_\n]+)_/g, '$1<em>$2</em>');
  return html.replace(/\uE000(\d+)\uE001/g, (_, index) => tokens[Number(index)] ?? '');
}

function markdownToHtml(markdown) {
  const lines = markdown.replaceAll('\r', '').split('\n');
  let html = '';
  const blockquotePattern = /^\s*>\s?/;
  const headingPattern = /^(#{1,6})\s+(.*)$/;
  const thematicPattern = /^\s*([-*_])(?:\s*\1){2,}\s*$/;
  const unorderedPattern = /^\s*[-+*]\s+/;
  const orderedPattern = /^\s*\d+[.)]\s+/;
  const fencePattern = /^\s*(```+|~~~+)(.*)$/;
  for (let index = 0; index < lines.length;) {
    const line = lines[index];
    if (!line.trim()) { index++; continue; }
    const fence = line.match(fencePattern);
    if (fence) {
      const marker = fence[1][0];
      const fenceLength = fence[1].length;
      const language = fence[2].trim();
      const closingPattern = new RegExp(`^\\s*${marker}{${fenceLength},}\\s*$`);
      const codeLines = [];
      index++;
      while (index < lines.length && !closingPattern.test(lines[index])) {
        codeLines.push(lines[index]);
        index++;
      }
      if (index < lines.length) index++;
      const codeClass = language ? ` class="language-${escapeHtml(language)}"` : '';
      html += `<pre><code${codeClass}>${escapeHtml(codeLines.join('\n'))}</code></pre>`;
      continue;
    }
    const heading = line.match(headingPattern);
    if (heading) {
      const level = Math.min(6, heading[1].length + 1);
      html += `<h${level}>${inlineMarkdown(heading[2])}</h${level}>`;
      index++;
      continue;
    }
    if (thematicPattern.test(line)) { html += '<hr>'; index++; continue; }
    if (blockquotePattern.test(line)) {
      const quoteLines = [];
      while (index < lines.length && blockquotePattern.test(lines[index])) {
        quoteLines.push(lines[index].replace(/^\s*>\s?/, ''));
        index++;
      }
      html += `<blockquote>${markdownToHtml(quoteLines.join('\n'))}</blockquote>`;
      continue;
    }
    if (orderedPattern.test(line)) {
      const items = [];
      while (index < lines.length && orderedPattern.test(lines[index])) {
        items.push(`<li>${inlineMarkdown(lines[index].replace(orderedPattern, ''))}</li>`);
        index++;
      }
      html += `<ol>${items.join('')}</ol>`;
      continue;
    }
    if (unorderedPattern.test(line)) {
      const items = [];
      while (index < lines.length && unorderedPattern.test(lines[index])) {
        const rest = lines[index].replace(unorderedPattern, '');
        const task = rest.match(/^\[([ xX])\]\s+(.*)$/);
        if (task) {
          const checked = task[1].toLowerCase() === 'x' ? ' checked' : '';
          items.push(`<li class="task-list-item"><input type="checkbox" disabled${checked}>${inlineMarkdown(task[2])}</li>`);
        } else {
          items.push(`<li>${inlineMarkdown(rest)}</li>`);
        }
        index++;
      }
      html += `<ul>${items.join('')}</ul>`;
      continue;
    }
    html += `<p>${inlineMarkdown(line.trim())}</p>`;
    index++;
  }
  return html;
}

async function loadSiteData() {
  const fallbackInfo = { name: 'ProjectMe', version: '1.1.8', generation: 1, author: 'tianyimc.com', authorUrl: 'https://tianyimc.com', copyright: '© 2026 tianyimc.com 依据 MIT 许可证开放源代码', license: 'MIT', licenseName: 'MIT 许可证', licenseUrl: 'https://opensource.org/license/mit', description: '一个无后端依赖的文集项目：网页负责阅读，CLI 与 WPF GUI 负责维护。', title: 'ProjectMe · 个人文集' };
  const [articles, projectInfo] = await Promise.all([
    fetch('articles.json').then((response) => response.json()),
    fetch('project-info.json').then((response) => response.json()).catch(() => fallbackInfo)
  ]);
  return { articles, projectInfo: { ...fallbackInfo, ...projectInfo } };
}

function safeHttpUrl(value) {
  const url = String(value ?? '').trim();
  return /^https?:\/\//i.test(url) ? url : '';
}

function linkHtml(url, label) {
  const target = safeHttpUrl(url);
  const text = escapeHtml(label);
  return target ? `<a href="${escapeHtml(target)}" target="_blank" rel="noopener noreferrer">${text}</a>` : text;
}

function authorLinkHtml(projectInfo, label = projectInfo?.author) {
  return linkHtml(projectInfo?.authorUrl, label);
}

function copyrightHtml(projectInfo) {
  const text = String(projectInfo?.copyright ?? '');
  const author = String(projectInfo?.author ?? '').trim();
  const url = safeHttpUrl(projectInfo?.authorUrl);
  if (!author || !url || !text.includes(author)) return escapeHtml(text);
  const escapedAuthor = escapeHtml(author);
  return escapeHtml(text).split(escapedAuthor).join(`<a href="${escapeHtml(url)}" target="_blank" rel="noopener noreferrer">${escapedAuthor}</a>`);
}

function licenseLinkHtml(projectInfo) {
  const name = String(projectInfo?.licenseName ?? projectInfo?.license ?? '').trim();
  if (!name) return '';
  return linkHtml(projectInfo?.licenseUrl, name);
}

function applySiteChrome(projectInfo) {
  document.title = projectInfo.title;
  const brand = document.querySelector('#footer-brand');
  const meta = document.querySelector('#footer-meta');
  if (brand) brand.textContent = projectInfo.name;
  if (meta) meta.innerHTML = `${escapeHtml(displayVersion(projectInfo))} · ${copyrightHtml(projectInfo)}`;
}

function displayVersion(projectInfo) {
  const generation = Number(projectInfo.generation) > 0 ? Number(projectInfo.generation) : 1;
  return generation <= 1 ? `v${projectInfo.version}` : `v${projectInfo.version} Gen${generation}`;
}

async function renderArticleInto(target, articles, slug, backHref = '#/') {
  const article = articles.find((item) => item.slug === slug);
  if (!article) { target.innerHTML = '<p class="empty">找不到这篇文章。</p>'; return; }
  const source = article.path ? encodeURI(String(article.path)) : `articles/${encodeURIComponent(article.file)}`;
  const response = await fetch(source);
  if (!response.ok) throw new Error(`Unable to load ${source}`);
  const markdown = await response.text();
  target.innerHTML = `<article class="article-page"><a class="back-link" href="${backHref}">← 返回文集</a><header class="article-head"><p class="eyebrow">${escapeHtml(article.category)}</p><h1>${escapeHtml(displayTitle(article.title))}</h1><div class="article-info"><span>${escapeHtml(formatArticleDate(article.date))}</span></div></header><div class="article-content">${markdownToHtml(markdown)}</div></article>`;
}
