# Template processor for conditional statements in Hwaro templates
#
# This processor handles ECR-style control flow syntax:
# - <% if condition %>...<% end %>
# - <% if condition %>...<% else %>...<% end %>
# - <% if condition %>...<% elsif condition %>...<% else %>...<% end %>
# - <% unless condition %>...<% end %>
# - <% unless condition %>...<% else %>...<% end %>
#
# Supported conditions:
# - Equality: page_url == "/about/"
# - Inequality: page_section != "blog"
# - String methods: page_url.starts_with?("/blog/"), page_title.ends_with?("!")
# - String methods: page_url.includes?("blog"), page_url.empty?
# - Boolean checks: page.draft, page.toc (truthy/falsy)
# - Negation: !page.draft
# - Logical AND: page_section == "blog" && !page.draft
# - Logical OR: page_section == "blog" || page_section == "news"
#
# Example usage in templates:
#   <% if page_section == "blog" %>
#     <p>This is a blog post</p>
#   <% elsif page_section == "docs" %>
#     <p>This is documentation</p>
#   <% else %>
#     <p>Other content</p>
#   <% end %>

module Hwaro
  module Content
    module Processors
      # Context for template variable resolution
      class TemplateContext
        getter page : Models::Page
        getter config : Models::Config
        getter variables : Hash(String, String)

        def initialize(@page : Models::Page, @config : Models::Config)
          @variables = build_variables
        end

        private def build_variables : Hash(String, String)
          {
            "page_title"       => @page.title,
            "page_description" => @page.description || @config.description || "",
            "page_url"         => @page.url,
            "page_section"     => @page.section,
            "page_date"        => @page.date.try(&.to_s("%Y-%m-%d")) || "",
            "page_image"       => @page.image || @config.og.default_image || "",
            "taxonomy_name"    => @page.taxonomy_name || "",
            "taxonomy_term"    => @page.taxonomy_term || "",
            "site_title"       => @config.title,
            "site_description" => @config.description || "",
            "base_url"         => @config.base_url,
          }
        end

        # Get a string variable value
        def get_string(name : String) : String?
          @variables[name]?
        end

        # Get a boolean variable value
        def get_bool(name : String) : Bool
          case name
          when "page.draft", "page_draft"
            @page.draft
          when "page.toc", "page_toc"
            @page.toc
          when "page.render", "page_render"
            @page.render
          when "page.is_index", "page_is_index"
            @page.is_index
          when "page.generated", "page_generated"
            @page.generated
          when "page.in_sitemap", "page_in_sitemap"
            @page.in_sitemap
          else
            false
          end
        end

        # Check if a variable exists and has a non-empty value
        def truthy?(name : String) : Bool
          # Check boolean properties first
          if name.starts_with?("page.")
            prop = name.sub("page.", "")
            case prop
            when "draft"      then return @page.draft
            when "toc"        then return @page.toc
            when "render"     then return @page.render
            when "is_index"   then return @page.is_index
            when "generated"  then return @page.generated
            when "in_sitemap" then return @page.in_sitemap
            end
          end

          # Check string variables
          if value = @variables[name]?
            return !value.empty?
          end

          false
        end
      end

      # Template processor for conditional logic
      class Template
        # Process template with conditional statements
        def self.process(content : String, context : TemplateContext) : String
          result = content

          # Process nested conditionals from innermost to outermost
          # Keep processing until no more conditionals are found
          loop do
            new_result = process_conditionals(result, context)
            break if new_result == result
            result = new_result
          end

          result
        end

        # Process if/unless conditionals
        private def self.process_conditionals(content : String, context : TemplateContext) : String
          result = content

          # Match if/unless blocks (non-greedy, innermost first)
          # Pattern explanation:
          # <%\s*(if|unless)\s+(.+?)\s*%> - opening tag with condition
          # (.*?) - content (non-greedy)
          # <%\s*end\s*%> - closing end tag
          pattern = /<%\s*(if|unless)\s+(.+?)\s*%>(.*?)<%\s*end\s*%>/m

          result = result.gsub(pattern) do |match|
            keyword = $1
            condition = $2
            body = $3

            process_conditional_block(keyword, condition, body, context)
          end

          result
        end

        # Process a single conditional block (if or unless)
        private def self.process_conditional_block(
          keyword : String,
          condition : String,
          body : String,
          context : TemplateContext
        ) : String
          # Parse elsif and else branches
          branches = parse_branches(body)

          # Evaluate conditions in order
          if keyword == "if"
            if evaluate_condition(condition, context)
              return branches[:if_body]
            end
          else # unless
            unless evaluate_condition(condition, context)
              return branches[:if_body]
            end
          end

          # Check elsif branches
          branches[:elsif_branches].each do |elsif_branch|
            if evaluate_condition(elsif_branch[:condition], context)
              return elsif_branch[:body]
            end
          end

          # Return else body if present
          branches[:else_body] || ""
        end

        # Parse if body into branches (if, elsif*, else?)
        private def self.parse_branches(body : String) : NamedTuple(
          if_body: String,
          elsif_branches: Array(NamedTuple(condition: String, body: String)),
          else_body: String?
        )
          elsif_branches = [] of NamedTuple(condition: String, body: String)
          else_body : String? = nil

          remaining = body

          # First, check for else (must be done before elsif since elsif contains "else")
          # Pattern: <% else %> followed by content
          else_pattern = /<%\s*else\s*%>/m

          if else_match = remaining.match(else_pattern)
            else_pos = else_match.begin || remaining.size
            before_else = remaining[0...else_pos]
            after_else = remaining[(else_pos + else_match[0].size)..]
            else_body = after_else
            remaining = before_else
          end

          # Now check for elsif branches in the remaining content
          # We need to find all elsif tags and split accordingly
          elsif_pattern = /<%\s*elsif\s+(.+?)\s*%>/m

          # Find all elsif positions
          elsif_positions = [] of Tuple(Int32, Int32, String) # start, end, condition
          remaining.scan(elsif_pattern) do |match|
            if match_begin = match.begin
              elsif_positions << {match_begin, match_begin + match[0].size, match[1]}
            end
          end

          if elsif_positions.empty?
            # No elsif, the remaining content is the if body
            return {
              if_body:         remaining,
              elsif_branches:  elsif_branches,
              else_body:       else_body,
            }
          end

          # Extract if body (before first elsif)
          if_body = remaining[0...elsif_positions[0][0]]

          # Extract elsif branches
          elsif_positions.each_with_index do |pos, i|
            condition = pos[2]
            start_pos = pos[1] # after the elsif tag

            # Find the end position (either next elsif or end of remaining)
            end_pos = if i + 1 < elsif_positions.size
                        elsif_positions[i + 1][0]
                      else
                        remaining.size
                      end

            branch_body = remaining[start_pos...end_pos]
            elsif_branches << {condition: condition, body: branch_body}
          end

          {
            if_body:         if_body,
            elsif_branches:  elsif_branches,
            else_body:       else_body,
          }
        end

        # Evaluate a condition expression
        private def self.evaluate_condition(condition : String, context : TemplateContext) : Bool
          condition = condition.strip

          # Handle logical AND (&&) - split and evaluate both parts
          # Use a simple split approach (doesn't handle nested parentheses)
          if condition.includes?("&&")
            parts = condition.split(/\s*&&\s*/, 2)
            if parts.size == 2
              return evaluate_condition(parts[0], context) && evaluate_condition(parts[1], context)
            end
          end

          # Handle logical OR (||) - split and evaluate both parts
          if condition.includes?("||")
            parts = condition.split(/\s*\|\|\s*/, 2)
            if parts.size == 2
              return evaluate_condition(parts[0], context) || evaluate_condition(parts[1], context)
            end
          end

          # Handle negation
          if condition.starts_with?("!")
            return !evaluate_condition(condition[1..].strip, context)
          end

          # Handle equality: variable == "value"
          if match = condition.match(/^(\w+)\s*==\s*"([^"]*)"$/)
            var_name = match[1]
            expected = match[2]
            actual = context.get_string(var_name)
            return actual == expected
          end

          # Handle inequality: variable != "value"
          if match = condition.match(/^(\w+)\s*!=\s*"([^"]*)"$/)
            var_name = match[1]
            expected = match[2]
            actual = context.get_string(var_name)
            return actual != expected
          end

          # Handle starts_with?: variable.starts_with?("value")
          if match = condition.match(/^(\w+)\.starts_with\?\("([^"]*)"\)$/)
            var_name = match[1]
            prefix = match[2]
            actual = context.get_string(var_name) || ""
            return actual.starts_with?(prefix)
          end

          # Handle ends_with?: variable.ends_with?("value")
          if match = condition.match(/^(\w+)\.ends_with\?\("([^"]*)"\)$/)
            var_name = match[1]
            suffix = match[2]
            actual = context.get_string(var_name) || ""
            return actual.ends_with?(suffix)
          end

          # Handle includes?: variable.includes?("value")
          if match = condition.match(/^(\w+)\.includes\?\("([^"]*)"\)$/)
            var_name = match[1]
            substring = match[2]
            actual = context.get_string(var_name) || ""
            return actual.includes?(substring)
          end

          # Handle empty?: variable.empty?
          if match = condition.match(/^(\w+)\.empty\?$/)
            var_name = match[1]
            actual = context.get_string(var_name)
            return actual.nil? || actual.empty?
          end

          # Handle present?: variable.present? (non-empty)
          if match = condition.match(/^(\w+)\.present\?$/)
            var_name = match[1]
            actual = context.get_string(var_name)
            return !actual.nil? && !actual.empty?
          end

          # Handle boolean property: page.draft, page.toc, etc.
          if match = condition.match(/^(page\.\w+)$/)
            return context.truthy?(match[1])
          end

          # Handle simple variable truthy check
          if condition =~ /^\w+$/
            return context.truthy?(condition)
          end

          # Default to false for unrecognized conditions
          false
        end
      end
    end
  end
end
