# Built-in shortcode templates that ship with Hwaro.
#
# These are used as fallbacks when the user has not provided a custom
# template in templates/shortcodes/.  Users can override any built-in
# shortcode by creating a file with the same name in their project.

module Hwaro
  module Core
    module Build
      module BuiltinShortcodes
        @@templates : Hash(String, String)? = nil

        # Returns the full set of built-in shortcode templates keyed by
        # their template path (e.g. "shortcodes/youtube").
        def self.templates : Hash(String, String)
          @@templates ||= build_templates
        end

        private def self.build_templates : Hash(String, String)
          t = {} of String => String

          # ── YouTube ──────────────────────────────────────────────
          # Usage: {{ youtube(id="dQw4w9WgXcQ") }}
          #        {{ youtube(id="dQw4w9WgXcQ", width="560", height="315") }}
          t["shortcodes/youtube"] = <<-HTML
          <div class="sc-video sc-video--youtube">
            <iframe
              src="https://www.youtube.com/embed/{{ id | e }}"
              width="{{ width | default(value='560') | e }}"
              height="{{ height | default(value='315') | e }}"
              frameborder="0"
              allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
              allowfullscreen
              title="{{ title | default(value='YouTube Video') | e }}"
              loading="lazy"
            ></iframe>
          </div>
          HTML

          # ── Vimeo ────────────────────────────────────────────────
          # Usage: {{ vimeo(id="123456789") }}
          t["shortcodes/vimeo"] = <<-HTML
          <div class="sc-video sc-video--vimeo">
            <iframe
              src="https://player.vimeo.com/video/{{ id | e }}"
              width="{{ width | default(value='560') | e }}"
              height="{{ height | default(value='315') | e }}"
              frameborder="0"
              allow="autoplay; fullscreen; picture-in-picture"
              allowfullscreen
              title="{{ title | default(value='Vimeo Video') | e }}"
              loading="lazy"
            ></iframe>
          </div>
          HTML

          # ── GitHub Gist ──────────────────────────────────────────
          # Usage: {{ gist(user="username", id="gist_id") }}
          #        {{ gist(user="username", id="gist_id", file="file.rb") }}
          t["shortcodes/gist"] = <<-HTML
          <div class="sc-gist">
            <script src="https://gist.github.com/{{ user | e }}/{{ id | e }}.js{% if file %}?file={{ file | e }}{% endif %}"></script>
          </div>
          HTML

          # ── Alert / Callout ──────────────────────────────────────
          # Usage: {% alert(type="warning") %}Watch out!{% end %}
          #        {% alert(type="info", title="Note") %}Some info{% end %}
          # Types: info, warning, danger, tip, success
          t["shortcodes/alert"] = <<-HTML
          {% set tone = type | default(value="info") | lower %}
          <div class="sc-alert sc-alert--{{ tone | e }}" role="alert">
            {% if title %}<div class="sc-alert__title">{{ title | e }}</div>{% endif %}
            <div class="sc-alert__body">{{ body }}</div>
          </div>
          HTML

          # ── Callout (alias for alert) ────────────────────────────
          t["shortcodes/callout"] = t["shortcodes/alert"]

          # ── Figure ───────────────────────────────────────────────
          # Usage: {{ figure(src="/img/photo.jpg", alt="A photo", caption="My photo") }}
          t["shortcodes/figure"] = <<-HTML
          <figure class="sc-figure">
            <img src="{{ src | e }}" alt="{{ alt | default(value='') | e }}"{% if width %} width="{{ width | e }}"{% endif %}{% if height %} height="{{ height | e }}"{% endif %} loading="lazy">
            {% if caption %}<figcaption>{{ caption | e }}</figcaption>{% endif %}
          </figure>
          HTML

          # ── Tweet ────────────────────────────────────────────────
          # Usage: {{ tweet(user="username", id="1234567890") }}
          t["shortcodes/tweet"] = <<-HTML
          <div class="sc-tweet">
            <blockquote class="twitter-tweet">
              <a href="https://twitter.com/{{ user | e }}/status/{{ id | e }}">Tweet by @{{ user | e }}</a>
            </blockquote>
            <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>
          </div>
          HTML

          # ── CodePen ──────────────────────────────────────────────
          # Usage: {{ codepen(user="username", id="pen_id") }}
          #        {{ codepen(user="username", id="pen_id", tab="css,result", height="400") }}
          t["shortcodes/codepen"] = <<-HTML
          <div class="sc-codepen">
            <iframe
              height="{{ height | default(value='300') | e }}"
              style="width: 100%;"
              scrolling="no"
              src="https://codepen.io/{{ user | e }}/embed/{{ id | e }}?default-tab={{ tab | default(value='result') | e }}&amp;editable=true"
              frameborder="no"
              loading="lazy"
              allowtransparency="true"
              allowfullscreen="true"
              title="{{ title | default(value='CodePen Embed') | e }}"
            ></iframe>
          </div>
          HTML

          t
        end
      end
    end
  end
end
