/* =============================================================================
   Hwaro Documentation - Interactive Features
   ============================================================================= */

(function() {
  // SVG icons
  var linkIcon = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M4.715 6.542 3.343 7.914a3 3 0 1 0 4.243 4.243l1.828-1.829A3 3 0 0 0 8.586 5.5L8 6.086a1.002 1.002 0 0 0-.154.199 2 2 0 0 1 .861 3.337L6.88 11.45a2 2 0 1 1-2.83-2.83l.793-.792a4.018 4.018 0 0 1-.128-1.287z"/><path d="M6.586 4.672A3 3 0 0 0 7.414 9.5l.775-.776a2 2 0 0 1-.896-3.346L9.12 3.55a2 2 0 1 1 2.83 2.83l-.793.792c.112.42.155.855.128 1.287l1.372-1.372a3 3 0 1 0-4.243-4.243L6.586 4.672z"/></svg>';
  var checkIcon = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M13.854 3.646a.5.5 0 0 1 0 .708l-7 7a.5.5 0 0 1-.708 0l-3.5-3.5a.5.5 0 1 1 .708-.708L6.5 10.293l6.646-6.647a.5.5 0 0 1 .708 0z"/></svg>';
  var copyIcon = '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V2zm2-1a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V2a1 1 0 0 0-1-1H6zM2 5a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1v-1h1v1a2 2 0 0 1-2 2H2a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h1v1H2z"/></svg>';

  // Theme switcher: dark is the default scheme; "light" pins the light side
  // of every light-dark() token via data-theme on <html>. The pre-paint
  // script in header.html applies the stored choice before first render.
  function initThemeToggle() {
    var btn = document.querySelector('.theme-toggle');
    if (!btn) return;
    var html = document.documentElement;

    function apply(mode) {
      if (mode === 'light') {
        html.setAttribute('data-theme', 'light');
      } else {
        html.removeAttribute('data-theme');
      }
      btn.setAttribute('data-mode', mode);
      btn.setAttribute('aria-label', mode === 'light' ? 'Switch to dark theme' : 'Switch to light theme');
    }

    apply(html.getAttribute('data-theme') === 'light' ? 'light' : 'dark');

    btn.addEventListener('click', function() {
      var mode = btn.getAttribute('data-mode') === 'light' ? 'dark' : 'light';
      apply(mode);
      try { localStorage.setItem('hwaro-docs-theme', mode); } catch (e) {}
    });
  }

  // Add anchor links to headings
  function addHeadingAnchors() {
    var headings = document.querySelectorAll('.docs-main h1[id], .docs-main h2[id], .docs-main h3[id], .docs-main h4[id], .docs-main h5[id], .docs-main h6[id]');

    headings.forEach(function(heading) {
      var anchor = document.createElement('a');
      anchor.className = 'heading-anchor';
      anchor.href = '#' + heading.id;
      anchor.innerHTML = linkIcon;
      anchor.setAttribute('aria-label', 'Copy link to this section');
      anchor.setAttribute('title', 'Copy link to section');

      anchor.addEventListener('click', function(e) {
        e.preventDefault();
        var url = window.location.origin + window.location.pathname + '#' + heading.id;

        navigator.clipboard.writeText(url).then(function() {
          anchor.classList.add('copied');
          anchor.innerHTML = checkIcon;

          setTimeout(function() {
            anchor.classList.remove('copied');
            anchor.innerHTML = linkIcon;
          }, 2000);
        }).catch(function() {
          // Fallback: just navigate to the anchor
          window.location.hash = heading.id;
        });
      });

      heading.appendChild(anchor);
    });
  }

  // Wrap code blocks and add copy buttons
  function addCodeCopyButtons() {
    var codeBlocks = document.querySelectorAll('.docs-main pre');

    codeBlocks.forEach(function(pre) {
      // Skip if already wrapped, and skip mermaid sources
      if (pre.parentNode.classList.contains('code-wrapper')) return;
      if (pre.classList.contains('mermaid')) return;

      // Create wrapper
      var wrapper = document.createElement('div');
      wrapper.className = 'code-wrapper';
      pre.parentNode.insertBefore(wrapper, pre);
      wrapper.appendChild(pre);

      // Create copy button
      var btn = document.createElement('button');
      btn.className = 'code-copy-btn';
      btn.innerHTML = copyIcon + '<span>Copy</span>';
      btn.setAttribute('aria-label', 'Copy code');
      btn.setAttribute('title', 'Copy code');

      btn.addEventListener('click', function() {
        var code = pre.querySelector('code');
        var text = code ? code.textContent : pre.textContent;

        navigator.clipboard.writeText(text).then(function() {
          btn.classList.add('copied');
          btn.innerHTML = checkIcon + '<span>Copied!</span>';

          setTimeout(function() {
            btn.classList.remove('copied');
            btn.innerHTML = copyIcon + '<span>Copy</span>';
          }, 2000);
        }).catch(function(err) {
          console.error('Failed to copy:', err);
        });
      });

      wrapper.appendChild(btn);
    });
  }

  // TOC scroll spy - IntersectionObserver drives updates (no scroll listener);
  // each crossing recomputes the heading nearest above the reading line.
  function initTocScrollSpy() {
    var tocContainer = document.querySelector('.docs-toc');
    if (!tocContainer) return;

    var tocLinks = tocContainer.querySelectorAll('a');
    if (tocLinks.length === 0) return;

    var headings = [];
    tocLinks.forEach(function(link) {
      var href = link.getAttribute('href');
      if (href && href.startsWith('#')) {
        var heading = document.getElementById(href.slice(1));
        if (heading) {
          headings.push({ el: heading, link: link });
        }
      }
    });

    if (headings.length === 0) return;

    var lastActive = null;

    function updateActiveLink() {
      var current = null;

      for (var i = 0; i < headings.length; i++) {
        if (headings[i].el.getBoundingClientRect().top <= 120) {
          current = headings[i];
        } else {
          break;
        }
      }

      if (!current) current = headings[0];
      if (current === lastActive) return;

      if (lastActive) lastActive.link.classList.remove('active');
      current.link.classList.add('active');
      lastActive = current;
    }

    var observer = new IntersectionObserver(updateActiveLink, {
      rootMargin: '-120px 0px -55% 0px',
      threshold: [0, 1]
    });

    headings.forEach(function(h) {
      observer.observe(h.el);
    });

    updateActiveLink();
  }

  // Mobile sidebar drawer
  function initMobileMenu() {
    var btn = document.querySelector('.mobile-menu-btn');
    var sidebar = document.querySelector('.docs-sidebar');
    var overlay = document.querySelector('.sidebar-overlay');
    if (!btn || !sidebar || !overlay) return;

    function setOpen(open) {
      sidebar.classList.toggle('is-open', open);
      overlay.classList.toggle('is-visible', open);
      btn.setAttribute('aria-expanded', open ? 'true' : 'false');
    }

    btn.addEventListener('click', function() {
      setOpen(!sidebar.classList.contains('is-open'));
    });
    overlay.addEventListener('click', function() {
      setOpen(false);
    });
    sidebar.addEventListener('click', function(e) {
      if (e.target.closest('a')) setOpen(false);
    });
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') setOpen(false);
    });
  }

  // Language switcher: close the <details> dropdown on outside click / Escape
  function initLangSwitch() {
    var switches = document.querySelectorAll('.lang-switch');
    if (switches.length === 0) return;

    function closeAll(except) {
      switches.forEach(function(el) {
        if (el !== except) el.removeAttribute('open');
      });
    }

    document.addEventListener('click', function(e) {
      closeAll(e.target.closest('.lang-switch'));
    });
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') closeAll(null);
    });
  }

  function init() {
    initThemeToggle();
    addHeadingAnchors();
    addCodeCopyButtons();
    initTocScrollSpy();
    initMobileMenu();
    initLangSwitch();
  }

  // Initialize on DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
