# Blog scaffold - blog-focused structure
#
# This scaffold creates a blog-oriented site with posts section,
# archives, tags, categories, and blog-specific templates.

require "./base"

module Hwaro
  module Services
    module Scaffolds
      class Blog < Base
        def type : Config::Options::ScaffoldType
          Config::Options::ScaffoldType::Blog
        end

        def description : String
          "Blog-focused structure with posts, archives, and taxonomies"
        end

        def content_files(skip_taxonomies : Bool = false) : Hash(String, String)
          files = {} of String => String

          # Homepage (blog listing)
          files["index.md"] = index_content(skip_taxonomies)

          # About page
          files["about.md"] = about_content(skip_taxonomies)

          # Blog section
          files["posts/_index.md"] = posts_index_content

          # Sample posts
          files["posts/hello-world.md"] = sample_post_1(skip_taxonomies)
          files["posts/getting-started-with-hwaro.md"] = sample_post_2(skip_taxonomies)
          files["posts/markdown-tips.md"] = sample_post_3(skip_taxonomies)

          # Archives page
          files["archives.md"] = archives_content

          files
        end

        def template_files(skip_taxonomies : Bool = false) : Hash(String, String)
          files = {
            "header.ecr"  => header_template,
            "footer.ecr"  => footer_template,
            "page.ecr"    => page_template,
            "section.ecr" => section_template,
            "post.ecr"    => post_template,
            "404.ecr"     => not_found_template,
          }

          unless skip_taxonomies
            files["taxonomy.ecr"] = taxonomy_template
            files["taxonomy_term.ecr"] = taxonomy_term_template
          end

          files
        end

        def config_content(skip_taxonomies : Bool = false) : String
          config = String.build do |str|
            str << base_config("My Blog", "Welcome to my personal blog powered by Hwaro.")
            str << search_config
            str << sitemap_config
            str << robots_config
            str << llms_config
            str << feeds_config(["posts"])
            str << plugins_config
            str << highlight_config
            str << taxonomies_config unless skip_taxonomies
          end
          config
        end

        # Override navigation for blog
        protected def navigation : String
          <<-NAV
              <nav>
                <a href="<%= base_url %>/">Home</a>
                <a href="<%= base_url %>/posts/">Posts</a>
                <a href="<%= base_url %>/archives/">Archives</a>
                <a href="<%= base_url %>/about/">About</a>
              </nav>
          NAV
        end

        # Override styles for blog
        protected def styles : String
          <<-CSS
            <style>
              :root {
                --primary-color: #0070f3;
                --text-color: #333;
                --text-muted: #666;
                --border-color: #eaeaea;
                --bg-code: #f4f4f4;
              }
              body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; line-height: 1.7; max-width: 800px; margin: 0 auto; padding: 2rem; color: var(--text-color); }
              header { margin-bottom: 2rem; border-bottom: 1px solid var(--border-color); padding-bottom: 1rem; }
              h1, h2, h3 { line-height: 1.2; }
              nav a { margin-right: 1rem; text-decoration: none; color: var(--primary-color); }
              nav a:hover { text-decoration: underline; }
              footer { margin-top: 3rem; border-top: 1px solid var(--border-color); padding-top: 1rem; color: var(--text-muted); font-size: 0.9rem; text-align: center; }
              code { background: var(--bg-code); padding: 0.2rem 0.4rem; border-radius: 3px; font-size: 0.9em; }
              pre { background: var(--bg-code); padding: 1rem; border-radius: 5px; overflow-x: auto; }
              pre code { background: none; padding: 0; }
              a { color: var(--primary-color); }
              a:hover { text-decoration: underline; }
              /* Blog specific styles */
              .post-list { list-style: none; padding: 0; }
              .post-item { margin-bottom: 2rem; padding-bottom: 1.5rem; border-bottom: 1px solid var(--border-color); }
              .post-item:last-child { border-bottom: none; }
              .post-title { margin: 0 0 0.5rem 0; }
              .post-title a { text-decoration: none; color: var(--text-color); }
              .post-title a:hover { color: var(--primary-color); }
              .post-meta { color: var(--text-muted); font-size: 0.9rem; margin-bottom: 0.5rem; }
              .post-excerpt { color: var(--text-color); }
              .tag { display: inline-block; background: var(--bg-code); padding: 0.2rem 0.5rem; border-radius: 3px; font-size: 0.8rem; margin-right: 0.3rem; text-decoration: none; color: var(--text-muted); }
              .tag:hover { background: var(--primary-color); color: white; text-decoration: none; }
              ul.section-list { list-style: none; padding: 0; }
              ul.section-list li { margin-bottom: 0.5rem; }
            </style>
          CSS
        end

        # Blog-specific post template
        private def post_template : String
          <<-HTML
          <%= render "header" %>
          <main>
            <article class="post">
              <header class="post-header">
                <h1><%= page_title %></h1>
                <div class="post-meta">
                  <time><%= page_date %></time>
                </div>
              </header>
              <div class="post-content">
                <%= content %>
              </div>
            </article>
          </main>
          <%= render "footer" %>
          HTML
        end

        # Content files
        private def index_content(skip_taxonomies : Bool) : String
          if skip_taxonomies
            <<-CONTENT
+++
title = "Home"
+++

# Welcome to My Blog

This is a blog powered by [Hwaro](https://github.com/hahwul/hwaro), a fast and lightweight static site generator.

Check out the latest posts in the [Posts](/posts/) section.
CONTENT
          else
            <<-CONTENT
+++
title = "Home"
tags = ["home"]
+++

# Welcome to My Blog

This is a blog powered by [Hwaro](https://github.com/hahwul/hwaro), a fast and lightweight static site generator.

Check out the latest posts in the [Posts](/posts/) section, or browse by:

- [Tags](/tags/)
- [Categories](/categories/)
- [Authors](/authors/)
CONTENT
          end
        end

        private def about_content(skip_taxonomies : Bool) : String
          if skip_taxonomies
            <<-CONTENT
+++
title = "About"
+++

# About Me

Welcome to my blog! I write about technology, programming, and other interesting topics.

## Contact

Feel free to reach out through social media or email.
CONTENT
          else
            <<-CONTENT
+++
title = "About"
tags = ["about"]
categories = ["pages"]
+++

# About Me

Welcome to my blog! I write about technology, programming, and other interesting topics.

## Contact

Feel free to reach out through social media or email.
CONTENT
          end
        end

        private def posts_index_content : String
          <<-CONTENT
+++
title = "Posts"
+++

# All Posts

Browse all blog posts below.
CONTENT
        end

        private def sample_post_1(skip_taxonomies : Bool) : String
          if skip_taxonomies
            <<-CONTENT
+++
title = "Hello World"
date = "2024-01-15"
description = "My first blog post using Hwaro static site generator."
+++

# Hello World

Welcome to my first blog post! This blog is powered by Hwaro, a fast and lightweight static site generator written in Crystal.

## Why Hwaro?

Hwaro offers a simple yet powerful way to create static websites:

- **Fast**: Built with Crystal for blazing fast build times
- **Simple**: Easy to understand directory structure
- **Flexible**: Supports custom templates and shortcodes

Stay tuned for more posts!
CONTENT
          else
            <<-CONTENT
+++
title = "Hello World"
date = "2024-01-15"
tags = ["introduction", "hello"]
categories = ["general"]
authors = ["admin"]
description = "My first blog post using Hwaro static site generator."
+++

# Hello World

Welcome to my first blog post! This blog is powered by Hwaro, a fast and lightweight static site generator written in Crystal.

## Why Hwaro?

Hwaro offers a simple yet powerful way to create static websites:

- **Fast**: Built with Crystal for blazing fast build times
- **Simple**: Easy to understand directory structure
- **Flexible**: Supports custom templates and shortcodes

Stay tuned for more posts!
CONTENT
          end
        end

        private def sample_post_2(skip_taxonomies : Bool) : String
          if skip_taxonomies
            <<-CONTENT
+++
title = "Getting Started with Hwaro"
date = "2024-01-20"
description = "A beginner's guide to building websites with Hwaro."
+++

# Getting Started with Hwaro

In this post, I'll walk you through the basics of setting up and using Hwaro.

## Installation

First, make sure you have Crystal installed. Then:

```bash
git clone https://github.com/hahwul/hwaro
cd hwaro
shards build
```

## Creating Your First Site

```bash
hwaro init my-blog --scaffold blog
cd my-blog
hwaro serve
```

That's it! Your blog is now running at `http://localhost:3000`.

## Next Steps

- Customize your templates in the `templates/` directory
- Add new posts in `content/posts/`
- Configure your site in `config.toml`
CONTENT
          else
            <<-CONTENT
+++
title = "Getting Started with Hwaro"
date = "2024-01-20"
tags = ["tutorial", "getting-started", "hwaro"]
categories = ["tutorials"]
authors = ["admin"]
description = "A beginner's guide to building websites with Hwaro."
+++

# Getting Started with Hwaro

In this post, I'll walk you through the basics of setting up and using Hwaro.

## Installation

First, make sure you have Crystal installed. Then:

```bash
git clone https://github.com/hahwul/hwaro
cd hwaro
shards build
```

## Creating Your First Site

```bash
hwaro init my-blog --scaffold blog
cd my-blog
hwaro serve
```

That's it! Your blog is now running at `http://localhost:3000`.

## Next Steps

- Customize your templates in the `templates/` directory
- Add new posts in `content/posts/`
- Configure your site in `config.toml`
CONTENT
          end
        end

        private def sample_post_3(skip_taxonomies : Bool) : String
          if skip_taxonomies
            <<-CONTENT
+++
title = "Markdown Tips and Tricks"
date = "2024-01-25"
description = "Learn useful Markdown formatting techniques for your blog posts."
+++

# Markdown Tips and Tricks

Hwaro uses Markdown for content. Here are some useful formatting tips.

## Text Formatting

- **Bold text** using `**bold**`
- *Italic text* using `*italic*`
- `Inline code` using backticks

## Code Blocks

Use triple backticks for code blocks:

```crystal
puts "Hello from Crystal!"
```

## Lists

Ordered lists:
1. First item
2. Second item
3. Third item

Unordered lists:
- Item one
- Item two
- Item three

## Links and Images

- [Link text](https://example.com)
- ![Alt text](/path/to/image.jpg)

## Blockquotes

> This is a blockquote.
> It can span multiple lines.

Happy writing!
CONTENT
          else
            <<-CONTENT
+++
title = "Markdown Tips and Tricks"
date = "2024-01-25"
tags = ["markdown", "writing", "tips"]
categories = ["tutorials"]
authors = ["admin"]
description = "Learn useful Markdown formatting techniques for your blog posts."
+++

# Markdown Tips and Tricks

Hwaro uses Markdown for content. Here are some useful formatting tips.

## Text Formatting

- **Bold text** using `**bold**`
- *Italic text* using `*italic*`
- `Inline code` using backticks

## Code Blocks

Use triple backticks for code blocks:

```crystal
puts "Hello from Crystal!"
```

## Lists

Ordered lists:
1. First item
2. Second item
3. Third item

Unordered lists:
- Item one
- Item two
- Item three

## Links and Images

- [Link text](https://example.com)
- ![Alt text](/path/to/image.jpg)

## Blockquotes

> This is a blockquote.
> It can span multiple lines.

Happy writing!
CONTENT
          end
        end

        private def archives_content : String
          <<-CONTENT
+++
title = "Archives"
+++

# Archives

Browse all posts by date. Check the [Posts](/posts/) section for the complete list.
CONTENT
        end
      end
    end
  end
end
