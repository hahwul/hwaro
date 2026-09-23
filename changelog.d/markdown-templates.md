### Fixed
- Markdown task lists, custom heading IDs, and heading attributes now work inside blockquotes.
- Markdown extension delimiters no longer rewrite link destinations, and raw HTML code blocks and list-indented code remain literal.
- External link policies now handle case-insensitive and single-quoted raw HTML attributes without duplicating `rel`.
- Template `unique` preserves distinct values with different types.
- Template `default` returns its fallback with the fallback's own type (`default(value=0) + 1` is arithmetic; a `none` fallback still renders as an empty string), and passes a non-empty array, map, or object through instead of printing its internal representation. Other non-empty values are still returned as strings.
