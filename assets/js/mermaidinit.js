// Lazy Mermaid loader. The 2.8 MB library lives in /vendor/ (outside the
// auto-include dirs) and is injected only on pages that actually contain a
// rendered diagram (`.mermaid`, emitted by the mermaid shortcode). Plain
// ```mermaid code fences in the docs stay as code samples.
(function () {
  function boot() {
    if (!document.querySelector(".mermaid")) return;

    var script = document.createElement("script");
    script.src = "/vendor/mermaid.min.js";
    script.onload = function () {
      var light =
        document.documentElement.getAttribute("data-theme") === "light";
      mermaid.initialize({
        startOnLoad: false,
        theme: light ? "neutral" : "dark",
        flowchart: {
          useMaxWidth: true,
          htmlLabels: true,
          curve: "basis",
        },
        sequence: {
          useMaxWidth: true,
          wrap: true,
          wrapPadding: 10,
        },
        gantt: {
          useMaxWidth: true,
        },
      });
      mermaid.run();
    };
    document.head.appendChild(script);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
