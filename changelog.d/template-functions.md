### Fixed
- Shortcode positional arguments retain explicitly empty values in their parameter slots.
- Runtime errors in shortcode templates leave a visible marker and preserve the page render.
- `get_section()` resolves translated section names against the current page language.
- Raw shortcode blocks remain protected when they contain fenced code.
- Identical shortcode templates report errors against their own source files.
