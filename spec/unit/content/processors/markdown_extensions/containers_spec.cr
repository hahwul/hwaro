require "../../../../spec_helper"

private def containers_config(safe : Bool = false) : Hwaro::Models::MarkdownConfig
  config = Hwaro::Models::MarkdownConfig.new
  config.containers = true
  config.safe = safe
  config
end

describe Hwaro::Content::Processors::MarkdownExtensions do
  describe ".preprocess_containers" do
    it "auto-closes a container outside a fence the page left open" do
      # The auto-close `</div>` landed inside the unclosed fence: it showed
      # as code text and the admonition <div> stayed open over the rest of
      # the page template.
      html, _ = Hwaro::Processor::Markdown.render(":::note\nBody\n\n```\ncode\n", markdown_config: containers_config)
      html.should_not contain("&lt;/div&gt;")
      html.should end_with("<pre><code>code\n</code></pre>\n</div>\n")
    end

    it "keeps a container written in a list item inside that item" do
      # The <div> was emitted at column 0, which ended the item and the list:
      # the list split in two around a hoisted container.
      html, _ = Hwaro::Processor::Markdown.render("- item\n\n  :::note\n  inside\n  :::\n- item two\n", markdown_config: containers_config)
      html.should eq(<<-HTML)
        <ul>
        <li>
        <p>item</p>
        <div class="admonition admonition-note">
        <p class="admonition-title">Note</p>
        <p>inside</p>
        </div>
        </li>
        <li>
        <p>item two</p>
        </li>
        </ul>

        HTML
    end

    it "auto-closes a container in safe mode when the page ends with raw HTML and no newline" do
      # The `</div>` joined the raw HTML block on the last line, which safe
      # mode omits whole.
      config = containers_config(safe: true)
      html, _ = Hwaro::Processor::Markdown.render(":::warning\n<table><tr><td>x</td></tr></table>", safe: true, markdown_config: config)
      html.should end_with("</div>\n")
      with_newline, _ = Hwaro::Processor::Markdown.render(":::warning\n<table><tr><td>x</td></tr></table>\n", safe: true, markdown_config: config)
      html.should eq(with_newline)
    end
  end
end
