/* =============================================================================
   Shortcodes Marketplace - search & filters
   ============================================================================= */

(function() {
  var root = document.getElementById('shortcode-market');
  if (!root) return;

  var searchInput = root.querySelector('[data-shortcode-search]');
  var countEl = root.querySelector('[data-shortcode-count]');
  var chips = Array.prototype.slice.call(root.querySelectorAll('[data-shortcode-filter]'));
  var listMount = root.querySelector('[data-shortcode-list]');
  var detailMount = root.querySelector('[data-shortcode-detail]');

  var items = Array.prototype.slice.call(root.querySelectorAll('.sc-item')).map(function(el) {
    var previewTpl = el.querySelector('template[data-preview]');
    var codeTpl = el.querySelector('template[data-code]');
    var templateTpl = el.querySelector('template[data-template]');

    return {
      el: el,
      name: el.getAttribute('data-name') || '',
      tags: (el.getAttribute('data-tags') || '').split(',').map(function(t) { return t.trim(); }).filter(Boolean),
      description: el.getAttribute('data-description') || '',
      previewHtml: previewTpl ? previewTpl.innerHTML.trim() : '',
      codeText: codeTpl ? (codeTpl.content.textContent || '').trim() : '',
      templateText: templateTpl ? (templateTpl.content.textContent || '').trim() : ''
    };
  });

  var activeFilter = 'all';
  var activeName = null;
  var activeTab = 'preview';

  function normalize(str) {
    return (str || '').toLowerCase().trim();
  }

  function itemMatches(item, query, filter) {
    var haystack = normalize(item.name + ' ' + item.tags.join(' ') + ' ' + item.description);
    var matchesQuery = !query || haystack.indexOf(query) !== -1;
    var matchesFilter = !filter || filter === 'all' || item.tags.indexOf(filter) !== -1;
    return matchesQuery && matchesFilter;
  }

  function escapeHtml(str) {
    return (str || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function renderList(visibleItems) {
    if (!listMount) return;

    listMount.innerHTML = '<div class="sc-list"></div>';
    var wrap = listMount.querySelector('.sc-list');

    visibleItems.forEach(function(item) {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'sc-list-item' + (item.name === activeName ? ' is-active' : '');
      btn.setAttribute('data-shortcode-select', item.name);

      var tagsHtml = item.tags.map(function(t) {
        return '<span class="sc-tag">' + escapeHtml(t) + '</span>';
      }).join('');

      btn.innerHTML =
        '<div class="sc-list-item__name">' + escapeHtml(item.name) + '</div>' +
        '<div class="sc-list-item__desc">' + escapeHtml(item.description) + '</div>' +
        '<div class="sc-list-item__tags">' + tagsHtml + '</div>';

      btn.addEventListener('click', function() {
        selectItem(item.name);
      });

      wrap.appendChild(btn);
    });
  }

  function renderDetail(item) {
    if (!detailMount) return;

    if (!item) {
      detailMount.innerHTML = '<div class="sc-detail__empty">No results. Try a different search.</div>';
      return;
    }

    var tagsHtml = item.tags.map(function(t) {
      return '<span class="sc-tag">' + escapeHtml(t) + '</span>';
    }).join('');

    var templatePath = 'templates/shortcodes/' + item.name + '.html';

    detailMount.innerHTML =
      '<div class="sc-detail__head">' +
        '<h2 class="sc-detail__title">' + escapeHtml(item.name) + '</h2>' +
        '<div class="sc-detail__desc">' + escapeHtml(item.description) + '</div>' +
        '<div class="sc-detail__tags">' + tagsHtml + '</div>' +
      '</div>' +
      '<div class="sc-detail__tabs" role="tablist" aria-label="Shortcode tabs">' +
        '<button class="sc-tab' + (activeTab === 'preview' ? ' is-active' : '') + '" type="button" data-tab="preview">Preview</button>' +
        '<button class="sc-tab' + (activeTab === 'usage' ? ' is-active' : '') + '" type="button" data-tab="usage">Usage</button>' +
        '<button class="sc-tab' + (activeTab === 'template' ? ' is-active' : '') + '" type="button" data-tab="template">Template</button>' +
      '</div>' +
      '<div class="sc-detail__body">' +
        '<div class="sc-pane" data-pane="preview"' + (activeTab !== 'preview' ? ' hidden' : '') + '>' + item.previewHtml + '</div>' +
        '<div class="sc-pane sc-code" data-pane="usage"' + (activeTab !== 'usage' ? ' hidden' : '') + '>' +
          '<div class="sc-code__meta">' + escapeHtml('Use in Markdown') + '</div>' +
          '<button class="sc-copy-btn" type="button" data-copy="usage">Copy</button>' +
          '<pre><code class="language-jinja">' + escapeHtml(item.codeText) + '</code></pre>' +
        '</div>' +
        '<div class="sc-pane sc-code" data-pane="template"' + (activeTab !== 'template' ? ' hidden' : '') + '>' +
          '<div class="sc-code__meta">' + escapeHtml(templatePath) + '</div>' +
          '<button class="sc-copy-btn" type="button" data-copy="template">Copy</button>' +
          '<pre><code class="language-jinja">' + escapeHtml(item.templateText) + '</code></pre>' +
        '</div>' +
      '</div>';

    var tabs = Array.prototype.slice.call(detailMount.querySelectorAll('[data-tab]'));
    tabs.forEach(function(tabBtn) {
      tabBtn.addEventListener('click', function() {
        activeTab = tabBtn.getAttribute('data-tab');
        renderDetail(item);
      });
    });

    var copyBtns = Array.prototype.slice.call(detailMount.querySelectorAll('[data-copy]'));
    copyBtns.forEach(function(btn) {
      btn.addEventListener('click', function() {
        var kind = btn.getAttribute('data-copy');
        var text = kind === 'template' ? item.templateText : item.codeText;

        navigator.clipboard.writeText(text).then(function() {
          btn.classList.add('is-copied');
          btn.textContent = 'Copied';
          setTimeout(function() {
            btn.classList.remove('is-copied');
            btn.textContent = 'Copy';
          }, 1400);
        }).catch(function() {
          // Fallback: select text in the same pane
          var pane = btn.closest('.sc-pane');
          var code = pane ? pane.querySelector('pre code') : null;
          if (!code) return;
          var range = document.createRange();
          range.selectNodeContents(code);
          var sel = window.getSelection();
          if (sel) {
            sel.removeAllRanges();
            sel.addRange(range);
          }
        });
      });
    });
  }

  function update() {
    var query = normalize(searchInput && searchInput.value);
    var visibleItems = items.filter(function(item) {
      return itemMatches(item, query, activeFilter);
    });

    if (countEl) {
      countEl.textContent = visibleItems.length + ' / ' + items.length + ' shortcodes';
    }

    if (!activeName || !visibleItems.some(function(i) { return i.name === activeName; })) {
      activeName = visibleItems[0] ? visibleItems[0].name : null;
      activeTab = 'preview';
    }

    renderList(visibleItems);
    renderDetail(visibleItems.find(function(i) { return i.name === activeName; }));
  }

  function setActiveChip(next) {
    activeFilter = next || 'all';
    chips.forEach(function(chip) {
      chip.classList.toggle('is-active', chip.getAttribute('data-shortcode-filter') === activeFilter);
    });
    update();
  }

  function selectItem(name) {
    activeName = name;
    activeTab = 'preview';
    update();
  }

  if (searchInput) {
    searchInput.addEventListener('input', function() {
      update();
    });
  }

  chips.forEach(function(chip) {
    chip.addEventListener('click', function() {
      setActiveChip(chip.getAttribute('data-shortcode-filter'));
    });
  });

  setActiveChip('all');
})();
