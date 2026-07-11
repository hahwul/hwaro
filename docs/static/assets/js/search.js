// Hwaro docs search — ⌘K command palette. Styles live in css/05-components.css.
(function () {
  var SECTION_NAMES = {
    start: "Start",
    writing: "Writing",
    templates: "Templates",
    features: "Features",
    deploy: "Deploy",
  };

  var QUICK_LINKS = [
    { title: "Start", description: "Install Hwaro and build your first site", url: "/start/" },
    { title: "Writing", description: "Pages, sections, taxonomies, and shortcodes", url: "/writing/" },
    { title: "Templates", description: "Template syntax, data model, and functions", url: "/templates/" },
    { title: "Features", description: "Search, SEO, builds, and platform features", url: "/features/" },
    { title: "Deploy", description: "Ship your site to GitHub Pages, Netlify, and more", url: "/deploy/" },
  ];

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
    '<div class="search-dialog" role="dialog" aria-modal="true" aria-label="Search documentation">' +
    '<div class="search-head">' +
    ICONS.search +
    '<input type="text" id="search-input" placeholder="Search documentation…" autocomplete="off" spellcheck="false" aria-label="Search documentation">' +
    '<button class="search-esc" type="button" aria-label="Close search">esc</button>' +
    "</div>" +
    '<div id="search-results" class="search-body"></div>' +
    '<div class="search-foot">' +
    '<span class="search-foot-hint"><kbd>↑</kbd><kbd>↓</kbd>navigate</span>' +
    '<span class="search-foot-hint"><kbd>↵</kbd>open</span>' +
    '<span class="search-foot-hint"><kbd>esc</kbd>close</span>' +
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
      "Search documentation (" + (isMac ? "⌘K" : "Ctrl+K") + ")"
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
      '<div class="search-group-label">Jump to</div>' +
      QUICK_LINKS.map(function (link) {
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
      resultsEl.innerHTML = '<div class="search-empty">Loading search index…</div>';
      countEl.textContent = "";
      return;
    }

    var results = fuse.search(query).slice(0, 12);

    if (results.length === 0) {
      resultsEl.innerHTML =
        '<div class="search-empty">No results for <span class="search-empty-query">&ldquo;' +
        escapeHtml(query) +
        '&rdquo;</span></div>';
      countEl.textContent = "0 results";
      return;
    }

    // Group by top-level section, preserving rank order
    var groups = [];
    var byName = {};
    results.forEach(function (result) {
      var key = (result.item.url.split("/")[1] || "").toLowerCase();
      var name = SECTION_NAMES[key] || "Docs";
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
    countEl.textContent = results.length === 1 ? "1 result" : results.length + " results";
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
