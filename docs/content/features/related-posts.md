+++
title = "Related Posts"
description = "Recommend related content based on shared taxonomy terms"
weight = 23
+++

Automatically recommend related content based on shared taxonomy terms (tags, categories, etc.).

## Configuration

Enable in `config.toml`:

```toml
[related]
enabled = true
limit = 5
taxonomies = ["tags"]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Enable related posts computation |
| limit | int | 5 | Maximum number of related posts per page |
| taxonomies | array | ["tags"] | Taxonomy names used to compute similarity |

## How It Works

1. Hwaro builds an inverted index of taxonomy terms to pages
2. For each page, it counts how many taxonomy terms are shared with other pages
3. Pages with more shared terms rank higher
4. Results are filtered by language (multilingual sites only show same-language posts)
5. The top N results (up to `limit`) are assigned as related posts

Draft pages, index pages, and generated pages are excluded from related post computation.

## Template Variable

Each page has a `related_posts` array containing the related pages sorted by relevance:

| Variable | Type | Description |
|----------|------|-------------|
| related_posts | array | Pages related to the current page, sorted by shared term count |

Each item in `related_posts` is a full page object with access to all page variables (`title`, `url`, `description`, `date`, `tags`, etc.).

## Usage in Templates

### Basic Related Posts

```jinja
{% if related_posts | length > 0 %}
<section class="related-posts">
  <h2>Related Posts</h2>
  <ul>
    {% for post in related_posts %}
    <li>
      <a href="{{ post.url }}">{{ post.title }}</a>
      {% if post.description %}
        <p>{{ post.description }}</p>
      {% endif %}
    </li>
    {% endfor %}
  </ul>
</section>
{% endif %}
```

### With Tags Display

```jinja
{% if related_posts | length > 0 %}
<aside class="related">
  <h3>You might also like</h3>
  {% for post in related_posts %}
  <article>
    <a href="{{ post.url }}">{{ post.title }}</a>
    <div class="tags">
      {% for tag in post.tags %}
        <span class="tag">{{ tag }}</span>
      {% endfor %}
    </div>
  </article>
  {% endfor %}
</aside>
{% endif %}
```

## Using Multiple Taxonomies

You can base related posts on multiple taxonomies for better relevance:

```toml
[related]
enabled = true
limit = 5
taxonomies = ["tags", "categories"]
```

Posts sharing terms in multiple taxonomies will rank higher. For example, a post sharing 2 tags and 1 category with another post scores 3, while a post sharing only 1 tag scores 1.
