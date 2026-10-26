# Can a template set print a page's automatic excerpt?
#
# The excerpt is a second markdown render of every page, so ParseContent
# only builds it when something can print it (`auto_summary_read?`). A
# template prints it by naming `summary` (`page.summary`, `p.summary`,
# `page_summary`, `summary_truncated`) — or by printing a whole page object,
# whose `summary` key then comes along unnamed: `{{ p }}`, `{{ p | tojson }}`,
# `{{ section.pages }}`, `{% for k, v in page %}`, `p[field]`, or a page
# handed to a macro that does any of that.
#
# This is a static, text-level over-approximation, like TemplateVarFeatures:
# anything it cannot classify counts as a reader. A false "reader" only costs
# the excerpt render; a false "no reader" would blank `summary` in the
# output, so every rule below errs toward reading.
module Hwaro::Core::Build::SummaryReaders
  extend self

  # Serialization, dict iteration and field names held in variables print
  # fields nobody named.
  GENERIC_READ_RE = /tojson|jsonify|pprint|inspect|dictsort|xmlattr|\|\s*string\b|\battr\s*\(|\battribute\s*=\s*[^"'\s]|[\w)\]]\[\s*[A-Za-z_]|\bfor\s+\w+\s*,\s*\w+\s+in\b/

  # Top-level template variables that are, or contain, page objects (the
  # HTML strings `pagination` / `section_list` and the term name
  # `taxonomy_term` are not).
  PAGE_NAMES = %w[page section pages site paginator pagination_obj page_translations
    __all_pages__ __all_sections__ __pages_by_path__ __sections_by_key__
    __sections_by_key_by_lang__ __taxonomies__]
  # Attributes whose value is a page, a section, a term, an author or a list
  # of them.
  PAGE_VALUED_ATTRS = %w[page pages items sections subsections lower higher parent ancestors
    translations series series_pages related_posts backlinks terms taxonomies authors children]
  # Functions returning page-carrying objects.
  PAGE_CALLS    = %w[get_page get_section get_taxonomy get_taxonomy_term]
  PAGE_CALLS_RE = /\b(?:#{PAGE_CALLS.join('|')})\s*\(/

  FOR_RE       = /\{%-?\s*for\s+([\w\s,]+?)\s+in\s+(.+?)-?%\}/m
  ASSIGN_RE    = /\{%-?\s*(?:set|with)\s+(\w+)\s*=\s*(.+?)-?%\}/m
  PRINT_RE     = /\{\{-?(.*?)-?\}\}/m
  TAG_RE       = /\{%-?(.*?)-?%\}/m
  STRING_RE    = /"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/
  REFERENCE_RE = /(?<![\w.])(\w+)((?:\s*\.\s*\w+)*)/
  CALL_REF_RE  = /(?<![\w.])(?:#{PAGE_CALLS.join('|')})\s*\([^()]*\)((?:\s*\.\s*\w+)*)/
  # What may follow a page value without printing it: a field access, a
  # literal-key subscript, a count, a test or a boolean/comparison operator.
  # The end of the expression is NOT harmless: `{{ p }}` prints the page.
  HARMLESS_NEXT_RE = /\A\s*(?:\.|\[\s*["']|\|\s*(?:length|count)\b|is\b|==|!=|and\b|or\b|else\b|in\b)/

  def read?(templates : Hash(String, String)) : Bool
    sources = templates.values
    return true if sources.any? { |src| src.includes?("summary") || src.matches?(GENERIC_READ_RE) }

    names = page_names(sources)
    sources.any? { |src| prints_page?(src, names) }
  end

  # PAGE_NAMES plus every loop / set / with variable any template binds to a
  # page value. One set for all templates: an `{% include %}` sees its
  # includer's loop variables.
  private def page_names(sources : Array(String)) : Set(String)
    names = PAGE_NAMES.to_set
    # Aliases chain (`set s = get_section(...)`, `for p in s.pages`), so
    # repeat until nothing new is bound.
    loop do
      size = names.size
      sources.each do |src|
        src.scan(FOR_RE) do |m|
          next unless page_valued?(m[2], names)
          m[1].split(',').each { |var| names << var.strip unless var.strip.empty? }
        end
        src.scan(ASSIGN_RE) { |m| names << m[1] if page_valued?(m[2], names) }
      end
      break if names.size == size
    end
    names
  end

  # Is the expression (a for collection or an assigned value) a page-carrying
  # object? Its head before any filter decides: `pages | sort(...)` is pages,
  # `page.tags | sort` is not.
  private def page_valued?(expression : String, names : Set(String)) : Bool
    head = expression.gsub(STRING_RE, %("")).split('|').first.split(/\s+if\s+/).first.strip
    head = head.sub(/(?:\s*\[[^\[\]]*\])+\z/, "") # pages[:5] is still pages
    if m = head.match(/\A(\w+)((?:\s*\.\s*\w+)*)\z/)
      chain = m[2].split('.').map(&.strip).reject(&.empty?)
      return chain.empty? ? names.includes?(m[1]) : PAGE_VALUED_ATTRS.includes?(chain.last)
    end
    if m = head.match(/\A\w+\s*\(.*\)((?:\s*\.\s*\w+)*)\z/m)
      chain = m[1].split('.').map(&.strip).reject(&.empty?)
      return head.matches?(PAGE_CALLS_RE) && (chain.empty? || PAGE_VALUED_ATTRS.includes?(chain.last))
    end
    # Anything more complex: page-carrying if it mentions anything page-like.
    head.matches?(PAGE_CALLS_RE) || head.scan(/\w+/).any? { |w| names.includes?(w[0]) || PAGE_VALUED_ATTRS.includes?(w[0]) }
  end

  private def prints_page?(source : String, names : Set(String)) : Bool
    source.scan(PRINT_RE) { |m| return true if uses_whole_page?(m[1], names, printed: true) }
    source.scan(TAG_RE) { |m| return true if uses_whole_page?(m[1], names, printed: false) }
    false
  end

  # A printed expression prints any page value it leaves whole. A tag only
  # leaks one by passing it on (`card(p)`, `get_url(p)`): the callee may print
  # it, and macro parameters are not tracked.
  private def uses_whole_page?(body : String, names : Set(String), printed : Bool) : Bool
    body = body.gsub(STRING_RE, %(""))
    body.scan(REFERENCE_RE) do |m|
      chain = attribute_chain(m[2])
      page = chain.empty? ? names.includes?(m[1]) : PAGE_VALUED_ATTRS.includes?(chain.last)
      return true if page && leaks?(body[m.end(0)..], printed)
    end
    body.scan(CALL_REF_RE) do |m|
      chain = attribute_chain(m[1])
      page = chain.empty? || PAGE_VALUED_ATTRS.includes?(chain.last)
      return true if page && leaks?(body[m.end(0)..], printed)
    end
    false
  end

  private def leaks?(rest : String, printed : Bool) : Bool
    printed ? !rest.matches?(HARMLESS_NEXT_RE) : rest.matches?(/\A\s*[,)]/)
  end

  private def attribute_chain(text : String) : Array(String)
    text.split('.').map(&.strip).reject(&.empty?)
  end
end
