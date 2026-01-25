// Load Fuse.js from CDN if not already loaded
if (typeof Fuse === "undefined") {
  const script = document.createElement("script");
  script.src = "https://cdn.jsdelivr.net/npm/fuse.js@6.6.2/dist/fuse.min.js";
  script.onload = initSearch;
  document.head.appendChild(script);
} else {
  initSearch();
}

let fuse;
let searchData = [];

function initSearch() {
  // Fetch search data
  fetch("/search.json")
    .then((response) => response.json())
    .then((data) => {
      searchData = data;
      fuse = new Fuse(data, {
        keys: ["title", "content", "description"],
        threshold: 0.3,
        includeMatches: true,
        includeScore: true,
      });
    })
    .catch((error) => console.error("Error loading search data:", error));
}

// Create search modal
const searchModal = document.createElement("div");
searchModal.id = "search-modal";
searchModal.innerHTML = `
  <div class="search-overlay" id="search-overlay"></div>
  <div class="search-dialog">
    <input type="text" id="search-input" placeholder="Search documentation..." autocomplete="off">
    <div id="search-results"></div>
    <button id="search-close">×</button>
  </div>
`;
searchModal.style.display = "none";
document.body.appendChild(searchModal);

// Add styles
const style = document.createElement("style");
style.textContent = `
  #search-modal {
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    z-index: 1000;
    font-family: var(--font-sans);
  }
  .search-overlay {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: rgba(10, 10, 12, 0.8);
    backdrop-filter: blur(4px);
  }
  .search-dialog {
    position: absolute;
    top: 20%;
    left: 50%;
    transform: translateX(-50%);
    width: 90%;
    max-width: 600px;
    background: var(--bg-elevated);
    border: var(--pixel-border) solid var(--primary);
    border-radius: 0;
    box-shadow: 0 0 20px var(--primary-glow);
    padding: 20px;
    max-height: 60vh;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }
  #search-input {
    width: 100%;
    padding: 12px 16px;
    font-size: 16px;
    font-family: var(--font-mono);
    background: var(--bg-subtle);
    color: var(--text);
    border: 1px solid var(--border);
    outline: none;
    margin-bottom: 16px;
  }
  #search-input:focus {
    border-color: var(--primary);
    box-shadow: 0 0 8px var(--primary-dim);
  }
  #search-input::placeholder {
    color: var(--text-muted);
  }
  #search-results {
    flex: 1;
    overflow-y: auto;
    max-height: calc(60vh - 120px);
  }
  .search-result {
    padding: 12px 0;
    border-bottom: 1px solid var(--border);
    cursor: pointer;
    transition: background 0.2s;
  }
  .search-result:hover {
    background: var(--bg-hover);
  }
  .search-result-title {
    font-weight: 600;
    color: var(--accent);
    margin-bottom: 4px;
    font-family: var(--font-mono);
  }
  .search-result-description {
    font-size: 14px;
    color: var(--text-muted);
  }
  #search-close {
    position: absolute;
    top: 10px;
    right: 10px;
    background: none;
    border: none;
    font-size: 24px;
    cursor: pointer;
    color: var(--text-muted);
    font-family: var(--font-mono);
  }
  #search-close:hover {
    color: var(--primary);
  }
`;
document.head.appendChild(style);

// Event listeners
document.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === "k") {
    e.preventDefault();
    showSearch();
  }
  if (e.key === "Escape" && searchModal.style.display !== "none") {
    hideSearch();
  }
});

document.getElementById("search-overlay").addEventListener("click", hideSearch);
document.getElementById("search-close").addEventListener("click", hideSearch);

const searchInput = document.getElementById("search-input");
searchInput.addEventListener("input", performSearch);
searchInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") {
    const results = document.querySelectorAll(".search-result");
    if (results.length > 0) {
      results[0].click();
    }
  }
});

function showSearch() {
  searchModal.style.display = "block";
  searchInput.focus();
  searchInput.value = "";
  document.getElementById("search-results").innerHTML = "";
}

function hideSearch() {
  searchModal.style.display = "none";
}

function performSearch() {
  const query = searchInput.value.trim();
  const resultsDiv = document.getElementById("search-results");

  if (!query) {
    resultsDiv.innerHTML = "";
    return;
  }

  if (!fuse) {
    resultsDiv.innerHTML =
      '<div class="search-result">Loading search index...</div>';
    return;
  }

  const results = fuse.search(query).slice(0, 10);

  if (results.length === 0) {
    resultsDiv.innerHTML = '<div class="search-result">No results found</div>';
    return;
  }

  resultsDiv.innerHTML = results
    .map((result) => {
      const item = result.item;
      return `
      <div class="search-result" onclick="window.location.href='${item.url}'">
        <div class="search-result-title">${highlightMatches(
          item.title,
          result.matches.find((m) => m.key === "title"),
        )}</div>
        ${
          item.description
            ? `<div class="search-result-description">${highlightMatches(
                item.description,
                result.matches.find((m) => m.key === "description"),
              )}</div>`
            : ""
        }
      </div>
    `;
    })
    .join("");
}

function highlightMatches(text, match) {
  if (!match || !match.indices) return text;

  let result = "";
  let lastIndex = 0;

  match.indices.forEach(([start, end]) => {
    result += text.slice(lastIndex, start);
    result += "<mark>" + text.slice(start, end + 1) + "</mark>";
    lastIndex = end + 1;
  });

  result += text.slice(lastIndex);
  return result;
}
