# Crinja's `striptags` hands its input to libxml's HTML parser, which raises
# "Document is empty" on an empty string: `{{ page.description | striptags }}`
# on a page without a description, or `{{ p.summary | striptags }}` with
# summaries off, failed the whole build. Same filter, registered after the
# original so it replaces it, answering the one input libxml rejects.
Crinja.filter :striptags do
  html = target.to_s
  html.empty? ? "" : XML.parse_html(html).inner_text.gsub(/\s+/, " ").strip
end
