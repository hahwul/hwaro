# Initializer module for creating new Hwaro projects
#
# Creates the initial project structure with sample content,
# templates, and configuration based on the selected scaffold.

require "../config/options/init_options"
require "../utils/logger"
require "../services/scaffolds/registry"
require "./defaults/agents_md"

module Hwaro
  module Services
    class Initializer
      def run(options : Config::Options::InitOptions)
        run(
          options.path,
          options.force,
          options.skip_agents_md,
          options.skip_sample_content,
          options.skip_taxonomies,
          options.multilingual_languages,
          options.scaffold
        )
      end

      def run(
        target_path : String,
        force : Bool = false,
        skip_agents_md : Bool = false,
        skip_sample_content : Bool = false,
        skip_taxonomies : Bool = false,
        multilingual_languages : Array(String) = [] of String,
        scaffold_type : Config::Options::ScaffoldType = Config::Options::ScaffoldType::Simple,
      )
        unless Dir.exists?(target_path)
          Dir.mkdir_p(target_path)
        end

        unless force || Dir.empty?(target_path)
          Logger.error "Directory '#{target_path}' is not empty."
          Logger.error "Use --force to overwrite."
          exit(1)
        end

        scaffold = Scaffolds::Registry.get(scaffold_type)
        Logger.info "Initializing new Hwaro project in #{target_path}..."
        Logger.info "Using scaffold: #{scaffold_type} - #{scaffold.description}"

        is_multilingual = multilingual_languages.size > 1

        # Create content structure
        create_directory(File.join(target_path, "content"))

        unless skip_sample_content
          if is_multilingual
            create_multilingual_content(target_path, multilingual_languages, skip_taxonomies, scaffold)
          else
            create_scaffold_content(target_path, scaffold, skip_taxonomies)
          end
        end

        # Create templates
        create_scaffold_templates(target_path, scaffold, skip_taxonomies)

        # Create static directory
        create_directory(File.join(target_path, "static"))

        # Create config.toml
        config_content = if is_multilingual
                           create_multilingual_config(multilingual_languages, skip_taxonomies, scaffold)
                         else
                           scaffold.config_content(skip_taxonomies)
                         end
        create_file(File.join(target_path, "config.toml"), config_content)

        # Create AGENTS.md unless skipped
        unless skip_agents_md
          create_file(File.join(target_path, "AGENTS.md"), Defaults::AgentsMd.content)
        end

        Logger.success "Done! Run `hwaro build` to generate the site."
      end

      private def create_scaffold_content(target_path : String, scaffold : Scaffolds::Base, skip_taxonomies : Bool)
        content_files = scaffold.content_files(skip_taxonomies)

        content_files.each do |relative_path, content|
          full_path = File.join(target_path, "content", relative_path)
          dir_path = File.dirname(full_path)

          # Create directory if it doesn't exist
          unless Dir.exists?(dir_path)
            create_directory(dir_path)
          end

          create_file(full_path, content)
        end
      end

      private def create_scaffold_templates(target_path : String, scaffold : Scaffolds::Base, skip_taxonomies : Bool)
        templates_dir = File.join(target_path, "templates")
        create_directory(templates_dir)

        # Create template files
        template_files = scaffold.template_files(skip_taxonomies)
        template_files.each do |relative_path, content|
          create_file(File.join(templates_dir, relative_path), content)
        end

        # Create shortcodes directory and files
        shortcodes_dir = File.join(templates_dir, "shortcodes")
        create_directory(shortcodes_dir)

        shortcode_files = scaffold.shortcode_files
        shortcode_files.each do |relative_path, content|
          full_path = File.join(templates_dir, relative_path)
          create_file(full_path, content)
        end
      end

      private def create_multilingual_content(
        target_path : String,
        languages : Array(String),
        skip_taxonomies : Bool,
        scaffold : Scaffolds::Base,
      )
        # For multilingual, we use the simple scaffold content with language variations
        # This is a simplified approach - in a full implementation, each scaffold
        # could provide its own multilingual content
        content_dir = File.join(target_path, "content")

        languages.each_with_index do |lang, index|
          is_default = index == 0

          if is_default
            # Default language content
            create_file(
              File.join(content_dir, "index.md"),
              multilingual_index_content(lang, true, skip_taxonomies)
            )
            create_file(
              File.join(content_dir, "about.md"),
              multilingual_about_content(lang, skip_taxonomies)
            )

            unless skip_taxonomies
              create_directory(File.join(content_dir, "blog"))
              create_file(
                File.join(content_dir, "blog", "_index.md"),
                multilingual_blog_index_content(lang)
              )
              create_file(
                File.join(content_dir, "blog", "hello-world.md"),
                multilingual_blog_post_content(lang, skip_taxonomies)
              )
            end
          else
            # Non-default languages
            create_file(
              File.join(content_dir, "index.#{lang}.md"),
              multilingual_index_content(lang, false, skip_taxonomies)
            )
            create_file(
              File.join(content_dir, "about.#{lang}.md"),
              multilingual_about_content(lang, skip_taxonomies)
            )

            unless skip_taxonomies
              create_file(
                File.join(content_dir, "blog", "_index.#{lang}.md"),
                multilingual_blog_index_content(lang)
              )
              create_file(
                File.join(content_dir, "blog", "hello-world.#{lang}.md"),
                multilingual_blog_post_content(lang, skip_taxonomies)
              )
            end
          end
        end
      end

      private def create_multilingual_config(
        languages : Array(String),
        skip_taxonomies : Bool,
        scaffold : Scaffolds::Base,
      ) : String
        default_lang = languages.first? || "en"

        lang_configs = languages.map_with_index do |lang, index|
          lang_name = language_display_name(lang)
          taxonomies_line = skip_taxonomies ? "" : "\n  taxonomies = [\"tags\", \"categories\"]"
          "  [languages.#{lang}]\n" \
          "  language_name = \"#{lang_name}\"\n" \
          "  weight = #{index + 1}\n" \
          "  generate_feed = true\n" \
          "  build_search_index = true#{taxonomies_line}"
        end.join("\n\n")

        taxonomies_config = if skip_taxonomies
                              ""
                            else
                              "# =============================================================================\n" \
                              "# Taxonomies\n" \
                              "# =============================================================================\n" \
                              "# Define content classification systems (tags, categories, etc.)\n\n" \
                              "[[taxonomies]]\n" \
                              "name = \"tags\"\n" \
                              "feed = true\n" \
                              "sitemap = false\n\n" \
                              "[[taxonomies]]\n" \
                              "name = \"categories\"\n" \
                              "paginate_by = 5\n\n" \
                              "[[taxonomies]]\n" \
                              "name = \"authors\"\n\n"
                            end

        String.build do |str|
          # Site basics
          str << "# =============================================================================\n"
          str << "# Site Configuration\n"
          str << "# =============================================================================\n\n"
          str << "title = \"My Hwaro Site\"\n"
          str << "description = \"Welcome to my new Hwaro site.\"\n"
          str << "base_url = \"http://localhost:3000\"\n\n"

          # Multilingual
          str << "# =============================================================================\n"
          str << "# Multilingual Configuration\n"
          str << "# =============================================================================\n\n"
          str << "default_language = \"#{default_lang}\"\n\n"
          str << "[languages]\n"
          str << lang_configs
          str << "\n\n"

          # Content & Processing
          str << "# =============================================================================\n"
          str << "# Plugins\n"
          str << "# =============================================================================\n"
          str << "# Configure content processors and extensions\n\n"
          str << "[plugins]\n"
          str << "processors = [\"markdown\"]\n\n"

          str << "# =============================================================================\n"
          str << "# Markdown Configuration\n"
          str << "# =============================================================================\n"
          str << "# Configure markdown parser behavior\n\n"
          str << "[markdown]\n"
          str << "safe = false          # If true, raw HTML in markdown will be stripped\n"
          str << "lazy_loading = false  # If true, automatically add loading=\"lazy\" to img tags\n\n"

          str << "# =============================================================================\n"
          str << "# Content Files\n"
          str << "# =============================================================================\n"
          str << "# Publish non-Markdown files from `content/` into the output directory.\n"
          str << "# Example: content/about/profile.jpg -> /about/profile.jpg\n\n"
          str << "[content.files]\n"
          str << "allow_extensions = [\"jpg\", \"jpeg\", \"png\", \"gif\", \"svg\", \"webp\"]\n"
          str << "# disallow_extensions = [\"psd\"]\n"
          str << "# disallow_paths = [\"private/**\", \"**/_*\"]\n\n"

          str << "# =============================================================================\n"
          str << "# Syntax Highlighting\n"
          str << "# =============================================================================\n"
          str << "# Code block syntax highlighting using Highlight.js\n\n"
          str << "[highlight]\n"
          str << "enabled = true\n"
          str << "theme = \"github\"          # Available: github, monokai, atom-one-dark, vs2015, etc.\n"
          str << "use_cdn = true            # Set to false to use local assets\n\n"

          str << "# =============================================================================\n"
          str << "# OpenGraph & Twitter Cards\n"
          str << "# =============================================================================\n"
          str << "# Default meta tags for social sharing\n"
          str << "# Page-level settings (front matter) override these defaults\n\n"
          str << "[og]\n"
          str << "default_image = \"/images/og-default.png\"   # Default image for social sharing\n"
          str << "type = \"article\"                           # OpenGraph type (website, article, etc.)\n"
          str << "twitter_card = \"summary_large_image\"       # Twitter card type (summary, summary_large_image)\n"
          str << "# twitter_site = \"@yourusername\"           # Twitter @username for the site\n"
          str << "# twitter_creator = \"@authorusername\"      # Twitter @username for content creator\n"
          str << "# fb_app_id = \"your_fb_app_id\"             # Facebook App ID (optional)\n\n"

          str << "# =============================================================================\n"
          str << "# Search Configuration\n"
          str << "# =============================================================================\n"
          str << "# Generates a search index for client-side search (e.g., Fuse.js)\n\n"
          str << "[search]\n"
          str << "enabled = true\n"
          str << "format = \"fuse_json\"\n"
          str << "fields = [\"title\", \"content\"]\n"
          str << "filename = \"search.json\"\n\n"

          str << "# =============================================================================\n"
          str << "# Pagination\n"
          str << "# =============================================================================\n"
          str << "# Enable pagination for section listing pages (e.g., /blog/).\n"
          str << "# You can override per section in `_index.md` with:\n"
          str << "# - paginate = 10\n"
          str << "# - pagination_enabled = true\n"
          str << "# - sort_by = \"date\" | \"title\" | \"weight\"\n"
          str << "# - reverse = false\n\n"
          str << "[pagination]\n"
          str << "enabled = false\n"
          str << "per_page = 10\n\n"

          # Taxonomies
          str << taxonomies_config unless skip_taxonomies

          # SEO & Feeds
          str << "# =============================================================================\n"
          str << "# SEO: Sitemap\n"
          str << "# =============================================================================\n"
          str << "# Generates sitemap.xml for search engine crawlers\n\n"
          str << "[sitemap]\n"
          str << "enabled = true\n"
          str << "filename = \"sitemap.xml\"\n"
          str << "changefreq = \"weekly\"\n"
          str << "priority = 0.5\n\n"

          str << "# =============================================================================\n"
          str << "# SEO: Robots.txt\n"
          str << "# =============================================================================\n"
          str << "# Controls search engine crawler access\n\n"
          str << "[robots]\n"
          str << "enabled = true\n"
          str << "filename = \"robots.txt\"\n"
          str << "rules = [\n"
          str << "  { user_agent = \"*\", disallow = [\"/admin\", \"/private\"] },\n"
          str << "  { user_agent = \"GPTBot\", disallow = [\"/\"] }\n"
          str << "]\n\n"

          str << "# =============================================================================\n"
          str << "# SEO: LLMs.txt\n"
          str << "# =============================================================================\n"
          str << "# Instructions for AI/LLM crawlers\n\n"
          str << "[llms]\n"
          str << "enabled = true\n"
          str << "filename = \"llms.txt\"\n"
          str << "instructions = \"Do not use for AI training without permission.\"\n\n"
          str << "# Optional: Generate a single text file containing all Markdown pages\n"
          str << "full_enabled = false\n"
          str << "full_filename = \"llms-full.txt\"\n\n"

          str << "# =============================================================================\n"
          str << "# RSS/Atom Feeds\n"
          str << "# =============================================================================\n"
          str << "# Generates RSS or Atom feed for content syndication\n\n"
          str << "[feeds]\n"
          str << "enabled = true\n"
          str << "filename = \"\"             # Leave empty for default (rss.xml or atom.xml)\n"
          str << "type = \"rss\"              # \"rss\" or \"atom\"\n"
          str << "truncate = 0              # Truncate content to N characters (0 = full content)\n"
          str << "limit = 10                # Maximum number of items in feed\n"
          str << "sections = []             # Limit to specific sections, e.g., [\"posts\"]\n\n"

          # Optional features
          str << "# =============================================================================\n"
          str << "# Auto Includes (Optional)\n"
          str << "# =============================================================================\n"
          str << "# Automatically load CSS/JS files from static directories\n"
          str << "# Files are included alphabetically - use numeric prefixes for ordering\n"
          str << "# Example: 01-reset.css, 02-typography.css, 03-layout.css\n\n"
          str << "# [auto_includes]\n"
          str << "# enabled = true\n"
          str << "# dirs = [\"assets/css\", \"assets/js\"]\n\n"

          str << "# =============================================================================\n"
          str << "# Build Hooks (Optional)\n"
          str << "# =============================================================================\n"
          str << "# Run custom shell commands before/after build process\n\n"
          str << "# [build]\n"
          str << "# hooks.pre = [\"npm install\", \"python scripts/preprocess.py\"]\n"
          str << "# hooks.post = [\"npm run minify\", \"./scripts/deploy.sh\"]\n"

          str << "\n"
          str << "# =============================================================================\n"
          str << "# Deployment (Optional)\n"
          str << "# =============================================================================\n"
          str << "# Configure deploy targets for `hwaro deploy`\n"
          str << "#\n"
          str << "# [deployment]\n"
          str << "# target = \"prod\"\n"
          str << "# source_dir = \"public\"\n"
          str << "# confirm = false\n"
          str << "# dryRun = false\n"
          str << "# maxDeletes = 256      # safety limit (-1 disables)\n"
          str << "#\n"
          str << "# [[deployment.targets]]\n"
          str << "# name = \"prod\"\n"
          str << "# url = \"file://./out\"\n"
          str << "#\n"
          str << "# [[deployment.targets]]\n"
          str << "# name = \"s3\"\n"
          str << "# url = \"s3://my-bucket\"\n"
          str << "# command = \"aws s3 sync {source}/ {url} --delete\"\n"
        end
      end

      # Multilingual content helpers
      private def multilingual_index_content(lang : String, is_default : Bool, skip_taxonomies : Bool) : String
        title = index_title(lang)
        greeting = index_greeting(lang)
        description = index_description(lang)
        getting_started = getting_started_title(lang)
        steps = getting_started_steps(lang, is_default)
        taxonomies_section = skip_taxonomies ? "" : taxonomies_intro(lang)

        String.build do |str|
          str << "+++\n"
          str << "title = \"#{title}\"\n"
          str << "tags = [\"welcome\", \"getting-started\"]\n" unless skip_taxonomies
          str << "+++\n\n"
          str << "# #{greeting}\n\n"
          str << "#{description}\n\n"
          str << "## #{getting_started}\n\n"
          str << "#{steps}\n"
          str << "#{taxonomies_section}\n" unless taxonomies_section.empty?
        end
      end

      private def multilingual_about_content(lang : String, skip_taxonomies : Bool) : String
        title = about_title(lang)
        heading = about_heading(lang)
        body = about_body(lang)

        if skip_taxonomies
          String.build do |str|
            str << "+++\n"
            str << "title = \"#{title}\"\n"
            str << "+++\n\n"
            str << "# #{heading}\n\n"
            str << "#{body}\n"
          end
        else
          String.build do |str|
            str << "+++\n"
            str << "title = \"#{title}\"\n"
            str << "tags = [\"about\", \"info\"]\n"
            str << "categories = [\"pages\"]\n"
            str << "+++\n\n"
            str << "# #{heading}\n\n"
            str << "#{body}\n"
          end
        end
      end

      private def multilingual_blog_index_content(lang : String) : String
        title = blog_title(lang)
        intro = blog_intro(lang)

        <<-CONTENT
+++
title = "#{title}"
paginate = 10
pagination_enabled = true
+++

# #{title}

#{intro}
CONTENT
      end

      private def multilingual_blog_post_content(lang : String, skip_taxonomies : Bool) : String
        title = hello_world_title(lang)
        body = hello_world_body(lang)

        if skip_taxonomies
          String.build do |str|
            str << "+++\n"
            str << "title = \"#{title}\"\n"
            str << "date = \"2024-01-01\"\n"
            str << "+++\n\n"
            str << "# #{title}\n\n"
            str << "#{body}\n"
          end
        else
          String.build do |str|
            str << "+++\n"
            str << "title = \"#{title}\"\n"
            str << "date = \"2024-01-01\"\n"
            str << "tags = [\"hello\", \"getting-started\"]\n"
            str << "categories = [\"blog\"]\n"
            str << "authors = [\"hwaro\"]\n"
            str << "+++\n\n"
            str << "# #{title}\n\n"
            str << "#{body}\n"
          end
        end
      end

      # Language-specific strings
      private def index_title(lang : String) : String
        case lang
        when "ko" then "Hwaro에 오신 것을 환영합니다"
        when "ja" then "Hwaroへようこそ"
        when "zh" then "欢迎使用Hwaro"
        when "es" then "Bienvenido a Hwaro"
        when "fr" then "Bienvenue sur Hwaro"
        when "de" then "Willkommen bei Hwaro"
        else           "Welcome to Hwaro"
        end
      end

      private def index_greeting(lang : String) : String
        case lang
        when "ko" then "안녕하세요, Hwaro!"
        when "ja" then "こんにちは、Hwaro！"
        when "zh" then "你好，Hwaro！"
        when "es" then "¡Hola, Hwaro!"
        when "fr" then "Bonjour, Hwaro !"
        when "de" then "Hallo, Hwaro!"
        else           "Hello, Hwaro!"
        end
      end

      private def index_description(lang : String) : String
        case lang
        when "ko" then "[Hwaro](https://github.com/hahwul/hwaro)로 생성된 정적 사이트입니다."
        when "ja" then "[Hwaro](https://github.com/hahwul/hwaro)で生成された静的サイトです。"
        when "zh" then "这是一个由[Hwaro](https://github.com/hahwul/hwaro)生成的静态网站。"
        when "es" then "Este es un sitio estático generado por [Hwaro](https://github.com/hahwul/hwaro)."
        when "fr" then "Ceci est un site statique généré par [Hwaro](https://github.com/hahwul/hwaro)."
        when "de" then "Dies ist eine statische Website, die mit [Hwaro](https://github.com/hahwul/hwaro) erstellt wurde."
        else           "This is a fresh static site generated by [Hwaro](https://github.com/hahwul/hwaro)."
        end
      end

      private def getting_started_title(lang : String) : String
        case lang
        when "ko" then "시작하기"
        when "ja" then "はじめに"
        when "zh" then "开始使用"
        when "es" then "Primeros pasos"
        when "fr" then "Pour commencer"
        when "de" then "Erste Schritte"
        else           "Getting Started"
        end
      end

      private def getting_started_steps(lang : String, is_default : Bool) : String
        content_path = is_default ? "content" : "content/#{lang}"
        case lang
        when "ko"
          "1. `#{content_path}/index.md`를 편집하여 이 페이지를 수정하세요.\n" \
          "2. `#{content_path}/`에 새 `.md` 파일을 추가하여 새 페이지를 만드세요.\n" \
          "3. `hwaro build`를 실행하여 사이트를 다시 생성하세요.\n" \
          "4. `hwaro serve`를 실행하여 로컬에서 미리보기 하세요."
        when "ja"
          "1. `#{content_path}/index.md`を編集してこのページを変更します。\n" \
          "2. `#{content_path}/`に新しい`.md`ファイルを追加して新しいページを作成します。\n" \
          "3. `hwaro build`を実行してサイトを再生成します。\n" \
          "4. `hwaro serve`を実行してローカルでプレビューします。"
        else
          "1. Edit `#{content_path}/index.md` to change this page.\n" \
          "2. Add new `.md` files in `#{content_path}/` to create new pages.\n" \
          "3. Run `hwaro build` to regenerate the site.\n" \
          "4. Run `hwaro serve` to preview changes locally."
        end
      end

      private def taxonomies_intro(lang : String) : String
        case lang
        when "ko"
          "\n## 분류 체계\n\n" \
          "Hwaro는 태그와 카테고리 같은 분류 체계를 지원합니다:\n\n" \
          "- [모든 태그](/ko/tags/)\n" \
          "- [모든 카테고리](/ko/categories/)"
        when "ja"
          "\n## タクソノミー\n\n" \
          "Hwaroはタグやカテゴリなどのタクソノミーをサポートしています：\n\n" \
          "- [すべてのタグ](/ja/tags/)\n" \
          "- [すべてのカテゴリ](/ja/categories/)"
        else
          "\n## Taxonomies\n\n" \
          "Hwaro supports taxonomies like tags and categories. Check out:\n\n" \
          "- [All Tags](/tags/)\n" \
          "- [All Categories](/categories/)"
        end
      end

      private def about_title(lang : String) : String
        case lang
        when "ko" then "소개"
        when "ja" then "について"
        when "zh" then "关于"
        when "es" then "Acerca de"
        when "fr" then "À propos"
        when "de" then "Über uns"
        else           "About"
        end
      end

      private def about_heading(lang : String) : String
        case lang
        when "ko" then "소개"
        when "ja" then "私たちについて"
        when "zh" then "关于我们"
        when "es" then "Sobre nosotros"
        when "fr" then "À propos de nous"
        when "de" then "Über uns"
        else           "About Us"
        end
      end

      private def about_body(lang : String) : String
        case lang
        when "ko" then "여러 페이지를 보여주기 위한 소개 페이지입니다."
        when "ja" then "複数のページを示すための紹介ページです。"
        when "zh" then "这是一个展示多页面的关于页面。"
        when "es" then "Esta es una página de presentación para demostrar múltiples páginas."
        when "fr" then "Ceci est une page de présentation pour démontrer plusieurs pages."
        when "de" then "Dies ist eine Über-uns-Seite, um mehrere Seiten zu demonstrieren."
        else           "This is an about page to demonstrate multiple pages."
        end
      end

      private def blog_title(lang : String) : String
        case lang
        when "ko" then "블로그"
        when "ja" then "ブログ"
        when "zh" then "博客"
        when "es" then "Blog"
        when "fr" then "Blog"
        when "de" then "Blog"
        else           "Blog"
        end
      end

      private def blog_intro(lang : String) : String
        case lang
        when "ko" then "블로그 섹션에 오신 것을 환영합니다. 여기서 모든 게시물을 확인하실 수 있습니다."
        when "ja" then "ブログセクションへようこそ。ここですべての投稿をご覧いただけます。"
        when "zh" then "欢迎来到博客区。在这里您可以找到所有的文章。"
        when "es" then "Bienvenido a la sección del blog. Aquí encontrarás todas nuestras publicaciones."
        when "fr" then "Bienvenue dans la section blog. Vous trouverez ici tous nos articles."
        when "de" then "Willkommen im Blog-Bereich. Hier finden Sie alle unsere Beiträge."
        else           "Welcome to the blog section. Here you'll find all our posts."
        end
      end

      private def hello_world_title(lang : String) : String
        case lang
        when "ko" then "안녕 세상"
        when "ja" then "ハローワールド"
        when "zh" then "你好世界"
        when "es" then "Hola Mundo"
        when "fr" then "Bonjour le monde"
        when "de" then "Hallo Welt"
        else           "Hello World"
        end
      end

      private def hello_world_body(lang : String) : String
        case lang
        when "ko" then "Hwaro의 분류 체계를 보여주는 샘플 블로그 포스트입니다."
        when "ja" then "Hwaroのタクソノミーを示すサンプルブログ記事です。"
        when "zh" then "这是一个展示Hwaro分类功能的示例博客文章。"
        when "es" then "Esta es una publicación de blog de ejemplo que demuestra las taxonomías en Hwaro."
        when "fr" then "Ceci est un exemple d'article de blog démontrant les taxonomies dans Hwaro."
        when "de" then "Dies ist ein Beispiel-Blogbeitrag, der Taxonomien in Hwaro demonstriert."
        else           "This is a sample blog post demonstrating taxonomies in Hwaro."
        end
      end

      private def language_display_name(code : String) : String
        case code.downcase
        when "en" then "English"
        when "ko" then "한국어"
        when "ja" then "日本語"
        when "zh" then "中文"
        when "es" then "Español"
        when "fr" then "Français"
        when "de" then "Deutsch"
        when "pt" then "Português"
        when "ru" then "Русский"
        when "it" then "Italiano"
        when "nl" then "Nederlands"
        when "pl" then "Polski"
        when "vi" then "Tiếng Việt"
        when "th" then "ไทย"
        when "ar" then "العربية"
        when "hi" then "हिन्दी"
        else           code.upcase
        end
      end

      private def create_directory(path : String)
        unless Dir.exists?(path)
          Dir.mkdir_p(path)
          Logger.action :create, path
        else
          Logger.action :exist, path, :blue
        end
      end

      private def create_file(path : String, content : String)
        unless File.exists?(path)
          File.write(path, content)
          Logger.action :create, path
        else
          Logger.action :exist, path, :blue
        end
      end
    end
  end
end
