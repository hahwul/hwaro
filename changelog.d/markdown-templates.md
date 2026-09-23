### Fixed
- Markdown task lists, custom heading IDs, and heading attributes now work inside blockquotes.
- Markdown extension delimiters no longer rewrite link destinations, and raw HTML code blocks and list-indented code remain literal.
- External link policies now handle case-insensitive and single-quoted raw HTML attributes without duplicating `rel`.
- Template `unique` preserves distinct values with different types, and `default` preserves the fallback value's type.
