// Initialize Mermaid with dark theme for better visibility on dark backgrounds
// No DOMContentLoaded wait - script is loaded at end of body so content is already available
mermaid.initialize({
  startOnLoad: false, // We'll manually trigger rendering for immediate execution
  theme: "dark",
  themeVariables: {
    darkMode: true,
    background: "#1a1a1a",
    primaryColor: "#3b82f6",
    primaryTextColor: "#e5e5e5",
    primaryBorderColor: "#60a5fa",
    lineColor: "#94a3b8",
    secondaryColor: "#8b5cf6",
    tertiaryColor: "#10b981",
    mainBkg: "#1e1e1e",
    secondBkg: "#262626",
    border1: "#404040",
    border2: "#525252",
    note: "#fbbf24",
    noteBkgColor: "#451a03",
    noteBorderColor: "#f59e0b",
    noteTextColor: "#fef3c7",
    textColor: "#e5e5e5",
    labelTextColor: "#e5e5e5",
    loopTextColor: "#e5e5e5",
    activationBorderColor: "#60a5fa",
    activationBkgColor: "#1e3a8a",
    sequenceNumberColor: "#e5e5e5",
  },
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

// Immediately render all mermaid charts
mermaid.run();
