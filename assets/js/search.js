// Hwaro docs search — ⌘K command palette. Styles live in css/05-components.css.
(function () {
  // The palette follows the page language: Korean pages search only Korean
  // index entries (search.json rows carry a `lang` field) and render the
  // UI strings below in Korean.
  var DOC_LANG = (document.documentElement.lang || "en").split("-")[0];

  var I18N = {
    en: {
      sections: {
        start: "Start",
        writing: "Writing",
        templates: "Templates",
        features: "Features",
        deploy: "Deploy",
        integrations: "Integrations",
      },
      fallbackSection: "Docs",
      quickLinks: [
        { title: "Start", description: "Install Hwaro and build your first site", url: "/start/" },
        { title: "Writing", description: "Pages, sections, taxonomies, and shortcodes", url: "/writing/" },
        { title: "Templates", description: "Template syntax, data model, and functions", url: "/templates/" },
        { title: "Features", description: "Search, SEO, builds, and platform features", url: "/features/" },
        { title: "Deploy", description: "Ship your site to GitHub Pages, Netlify, and more", url: "/deploy/" },
      ],
      searchLabel: "Search documentation",
      placeholder: "Search documentation…",
      close: "Close search",
      jumpTo: "Jump to",
      loading: "Loading search index…",
      hintNavigate: "navigate",
      hintOpen: "open",
      hintClose: "close",
      noResults: function (query) {
        return 'No results for <span class="search-empty-query">&ldquo;' + query + '&rdquo;</span>';
      },
      count: function (n) {
        return n === 1 ? "1 result" : n + " results";
      },
    },
    ko: {
      sections: {
        start: "시작하기",
        writing: "콘텐츠 작성",
        templates: "템플릿",
        features: "기능",
        deploy: "배포",
        integrations: "연동",
      },
      fallbackSection: "문서",
      quickLinks: [
        { title: "시작하기", description: "Hwaro 설치와 첫 사이트 만들기", url: "/ko/start/" },
        { title: "콘텐츠 작성", description: "페이지, 섹션, 택소노미, 숏코드", url: "/ko/writing/" },
        { title: "템플릿", description: "템플릿 문법, 데이터 모델, 함수", url: "/ko/templates/" },
        { title: "기능", description: "검색, SEO, 빌드와 플랫폼 기능", url: "/ko/features/" },
        { title: "배포", description: "GitHub Pages, Netlify 등으로 배포", url: "/ko/deploy/" },
      ],
      searchLabel: "문서 검색",
      placeholder: "문서 검색…",
      close: "검색 닫기",
      jumpTo: "바로 가기",
      loading: "검색 인덱스를 불러오는 중…",
      hintNavigate: "이동",
      hintOpen: "열기",
      hintClose: "닫기",
      noResults: function (query) {
        return '<span class="search-empty-query">&ldquo;' + query + '&rdquo;</span>에 대한 결과가 없습니다';
      },
      count: function (n) {
        return "결과 " + n + "개";
      },
    },
  };

  var L = I18N[DOC_LANG] || I18N.en;

  var ICONS = {
    search:
      '<svg class="search-head-icon" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="7" cy="7" r="4.5"/><path d="m13.5 13.5-3.2-3.2"/></svg>',
    doc:
      '<svg class="search-result-icon" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9.5 1.5h-5a1 1 0 0 0-1 1v11a1 1 0 0 0 1 1h7a1 1 0 0 0 1-1V4.5l-3-3z"/><path d="M9.5 1.5v3h3"/><path d="M5.5 8h5M5.5 10.5h5"/></svg>',
    arrow:
      '<svg class="search-result-icon" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2.5 8h11M9.5 4l4 4-4 4"/></svg>',
    enter:
      '<svg class="search-result-enter" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M13.5 3v4a2 2 0 0 1-2 2h-9"/><path d="M5.5 6 2.5 9l3 3"/></svg>',
  };

  var fuse = null;
  var searchLoading = false;
  var selectedIndex = 0;
  var isMac = /Mac|iP(hone|ad|od)/.test(navigator.platform || navigator.userAgent);

  // Vendored Fuse.js and the index are loaded lazily, on the first time the
  // palette opens, so regular page views cost zero search bytes.
  function ensureSearch() {
    if (fuse || searchLoading) return;
    searchLoading = true;

    function initIndex() {
      fetch("/search.json")
        .then(function (response) {
          return response.json();
        })
        .then(function (data) {
          // Scope results to the page language (entries without a lang
          // field belong to the default language).
          data = data.filter(function (item) {
            return (item.lang || "en") === DOC_LANG;
          });
          fuse = new Fuse(data, {
            keys: ["title", "content", "description"],
            threshold: 0.3,
            ignoreLocation: true,
            includeMatches: true,
            includeScore: true,
            minMatchCharLength: 2,
          });
          if (searchInput.value.trim()) performSearch();
        })
        .catch(function (error) {
          searchLoading = false;
          console.error("Error loading search data:", error);
        });
    }

    if (typeof Fuse === "undefined") {
      var script = document.createElement("script");
      script.src = "/vendor/fuse.basic.min.js";
      script.onload = initIndex;
      script.onerror = function () {
        searchLoading = false;
      };
      document.head.appendChild(script);
    } else {
      initIndex();
    }
  }

  // Build modal
  var searchModal = document.createElement("div");
  searchModal.id = "search-modal";
  searchModal.innerHTML =
    '<div class="search-overlay"></div>' +
    '<div class="search-dialog" role="dialog" aria-modal="true" aria-label="' + L.searchLabel + '">' +
    '<div class="search-head">' +
    ICONS.search +
    '<input type="text" id="search-input" placeholder="' + L.placeholder + '" autocomplete="off" spellcheck="false" aria-label="' + L.searchLabel + '">' +
    '<button class="search-esc" type="button" aria-label="' + L.close + '">esc</button>' +
    "</div>" +
    '<div id="search-results" class="search-body"></div>' +
    '<div class="search-foot">' +
    '<span class="search-foot-hint"><kbd>↑</kbd><kbd>↓</kbd>' + L.hintNavigate + "</span>" +
    '<span class="search-foot-hint"><kbd>↵</kbd>' + L.hintOpen + "</span>" +
    '<span class="search-foot-hint"><kbd>esc</kbd>' + L.hintClose + "</span>" +
    '<span class="search-foot-count" id="search-count"></span>' +
    "</div>" +
    "</div>";
  searchModal.style.display = "none";
  document.body.appendChild(searchModal);

  var searchInput = document.getElementById("search-input");
  var resultsEl = document.getElementById("search-results");
  var countEl = document.getElementById("search-count");

  // Header trigger: platform-aware shortcut label + click to open
  document.querySelectorAll(".search-trigger-mod").forEach(function (el) {
    el.textContent = isMac ? "⌘" : "Ctrl";
  });
  document.querySelectorAll(".search-trigger").forEach(function (btn) {
    btn.setAttribute(
      "aria-label",
      L.searchLabel + " (" + (isMac ? "⌘K" : "Ctrl+K") + ")"
    );
    btn.addEventListener("click", showSearch);
  });

  document.addEventListener("keydown", function (e) {
    if ((e.metaKey || e.ctrlKey) && e.key === "k") {
      e.preventDefault();
      showSearch();
    }
    if (e.key === "Escape" && searchModal.style.display !== "none") {
      hideSearch();
    }
  });

  searchModal.querySelector(".search-overlay").addEventListener("click", hideSearch);
  searchModal.querySelector(".search-esc").addEventListener("click", hideSearch);

  searchInput.addEventListener("input", performSearch);

  searchInput.addEventListener("keydown", function (e) {
    var results = resultsEl.querySelectorAll(".search-result");
    if (results.length === 0) return;

    if (e.key === "ArrowDown") {
      e.preventDefault();
      selectedIndex = (selectedIndex + 1) % results.length;
      applySelection(true);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      selectedIndex = selectedIndex <= 0 ? results.length - 1 : selectedIndex - 1;
      applySelection(true);
    } else if (e.key === "Enter") {
      e.preventDefault();
      var target = results[selectedIndex] || results[0];
      if (target) target.click();
    }
  });

  // Hovering a row moves the selection, keeping mouse and keyboard in sync
  resultsEl.addEventListener("mouseover", function (e) {
    var row = e.target.closest(".search-result");
    if (!row) return;
    var results = Array.prototype.slice.call(
      resultsEl.querySelectorAll(".search-result")
    );
    var index = results.indexOf(row);
    if (index !== -1 && index !== selectedIndex) {
      selectedIndex = index;
      applySelection(false);
    }
  });

  function applySelection(scroll) {
    var results = resultsEl.querySelectorAll(".search-result");
    results.forEach(function (result, index) {
      if (index === selectedIndex) {
        result.classList.add("selected");
        if (scroll) result.scrollIntoView({ block: "nearest" });
      } else {
        result.classList.remove("selected");
      }
    });
  }

  function showSearch() {
    ensureSearch();
    searchModal.style.display = "block";
    document.documentElement.style.overflow = "hidden";
    searchInput.value = "";
    renderQuickLinks();
    searchInput.focus();
  }

  function hideSearch() {
    searchModal.style.display = "none";
    document.documentElement.style.overflow = "";
  }

  function renderQuickLinks() {
    resultsEl.innerHTML =
      '<div class="search-group">' +
      '<div class="search-group-label">' + L.jumpTo + "</div>" +
      L.quickLinks.map(function (link) {
        return resultRow(link.url, ICONS.arrow, escapeHtml(link.title), escapeHtml(link.description));
      }).join("") +
      "</div>";
    countEl.textContent = "";
    selectedIndex = 0;
    applySelection(false);
  }

  function performSearch() {
    var query = searchInput.value.trim();

    if (!query) {
      renderQuickLinks();
      return;
    }

    if (!fuse) {
      resultsEl.innerHTML = '<div class="search-empty">' + L.loading + "</div>";
      countEl.textContent = "";
      return;
    }

    var results = fuse.search(query).slice(0, 12);

    if (results.length === 0) {
      resultsEl.innerHTML =
        '<div class="search-empty">' + L.noResults(escapeHtml(query)) + "</div>";
      countEl.textContent = L.count(0);
      return;
    }

    // Group by top-level section, preserving rank order. Non-default
    // language URLs carry the language prefix (/ko/start/…), so the
    // section segment sits one step further in.
    var groups = [];
    var byName = {};
    results.forEach(function (result) {
      var parts = result.item.url.split("/");
      var key = ((parts[1] === DOC_LANG ? parts[2] : parts[1]) || "").toLowerCase();
      var name = L.sections[key] || L.fallbackSection;
      if (!byName[name]) {
        byName[name] = [];
        groups.push({ name: name, items: byName[name] });
      }
      byName[name].push(result);
    });

    resultsEl.innerHTML = groups
      .map(function (group) {
        return (
          '<div class="search-group">' +
          '<div class="search-group-label">' + group.name + "</div>" +
          group.items.map(renderResult).join("") +
          "</div>"
        );
      })
      .join("");
    countEl.textContent = L.count(results.length);
    selectedIndex = 0;
    applySelection(false);
  }

  function renderResult(result) {
    var item = result.item;
    var titleMatch, contentMatch, descriptionMatch;
    (result.matches || []).forEach(function (m) {
      if (m.key === "title") titleMatch = m;
      else if (m.key === "content") contentMatch = m;
      else if (m.key === "description") descriptionMatch = m;
    });

    var snippet = "";
    if (contentMatch && contentMatch.indices && contentMatch.indices.length > 0) {
      snippet = getContentSnippet(item.content, contentMatch);
    } else if (item.description) {
      snippet = highlightMatches(item.description, descriptionMatch);
    }

    return resultRow(item.url, ICONS.doc, highlightMatches(item.title, titleMatch), snippet);
  }

  // titleHtml/snippetHtml are pre-escaped by the callers
  function resultRow(url, icon, titleHtml, snippetHtml) {
    return (
      '<a class="search-result" href="' + url + '">' +
      icon +
      '<span class="search-result-text">' +
      '<span class="search-result-title">' + titleHtml + "</span>" +
      (snippetHtml ? '<span class="search-result-snippet">' + snippetHtml + "</span>" : "") +
      "</span>" +
      ICONS.enter +
      "</a>"
    );
  }

  function getContentSnippet(text, match) {
    if (!match || !match.indices || match.indices.length === 0) return "";

    // Pick the longest (most relevant) match index
    var best = match.indices.reduce(function (a, b) {
      return b[1] - b[0] > a[1] - a[0] ? b : a;
    });
    var start = best[0];
    var end = best[1];
    var snippetRadius = 60;
    var snippetStart = Math.max(0, start - snippetRadius);
    var snippetEnd = Math.min(text.length, end + 1 + snippetRadius);

    var snippet = "";
    if (snippetStart > 0) snippet += "…";
    snippet += escapeHtml(text.slice(snippetStart, start));
    snippet += "<mark>" + escapeHtml(text.slice(start, end + 1)) + "</mark>";
    snippet += escapeHtml(text.slice(end + 1, snippetEnd));
    if (snippetEnd < text.length) snippet += "…";

    return snippet;
  }

  function escapeHtml(text) {
    var div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }

  function highlightMatches(text, match) {
    if (!match || !match.indices) return escapeHtml(text);

    var result = "";
    var lastIndex = 0;

    match.indices.forEach(function (pair) {
      result += escapeHtml(text.slice(lastIndex, pair[0]));
      result += "<mark>" + escapeHtml(text.slice(pair[0], pair[1] + 1)) + "</mark>";
      lastIndex = pair[1] + 1;
    });

    result += escapeHtml(text.slice(lastIndex));
    return result;
  }
})();
