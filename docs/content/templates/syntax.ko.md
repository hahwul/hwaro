+++
title = "문법"
description = "Jinja2 호환 템플릿 문법 레퍼런스"
weight = 1
toc = true
+++

Hwaro는 Jinja2 호환 템플릿 엔진인 Crinja를 사용합니다. 이 페이지는 핵심 문법을 다룹니다.

## 변수

이중 중괄호로 값을 출력합니다.

```jinja
{{ page.title }}
{{ site.description }}
{{ content }}
```

## 주석

```jinja
{# This is a comment #}
```

## 조건문

```jinja
{% if page.description %}
<meta name="description" content="{{ page.description }}">
{% endif %}
```

else와 함께:

```jinja
{% if page.draft %}
<span class="badge">Draft</span>
{% else %}
<span class="badge">Published</span>
{% endif %}
```

elif와 함께:

```jinja
{% if page.section == "blog" %}
<article class="post">{{ content | safe }}</article>
{% elif page.section == "docs" %}
<div class="documentation">{{ content | safe }}</div>
{% else %}
<main>{{ content | safe }}</main>
{% endif %}
```

## 반복문

```jinja
{% for p in section.pages %}
<li><a href="{{ p.url }}">{{ p.title }}</a></li>
{% endfor %}
```

인덱스와 함께:

```jinja
{% for tag in page.tags %}
{% if not loop.first %}, {% endif %}
{{ tag }}
{% endfor %}
```

반복 변수:

| 변수 | 설명 |
|----------|-------------|
| loop.index | 현재 반복 횟수(1부터 시작) |
| loop.index0 | 현재 반복 횟수(0부터 시작) |
| loop.first | 첫 반복에서 true |
| loop.last | 마지막 반복에서 true |
| loop.length | 전체 항목 수 |

## 템플릿 상속

### 베이스 템플릿

`templates/base.html`:

```jinja
<!DOCTYPE html>
<html>
<head>
  <title>{% block title %}{{ site.title }}{% endblock %}</title>
  {{ highlight_css | safe }}
</head>
<body>
  {% block content %}{% endblock %}
  {{ highlight_js | safe }}
</body>
</html>
```

### 자식 템플릿

`templates/page.html`:

```jinja
{% extends "base.html" %}

{% block title %}{{ page.title }} - {{ site.title }}{% endblock %}

{% block content %}
<article>
  <h1>{{ page.title }}</h1>
  {{ content | safe }}
</article>
{% endblock %}
```

## 인클루드

부분 템플릿을 불러옵니다.

```jinja
{% include "partials/header.html" %}
<main>{{ content | safe }}</main>
{% include "partials/footer.html" %}
```

## 변수

변수를 설정합니다.

```jinja
{% set author = page.authors | first %}
<span>By {{ author }}</span>
```

## 필터

파이프 연산자로 값을 변환합니다.

```jinja
{{ page.title | upper }}
{{ content | safe }}
{{ page.date | date("%B %d, %Y") }}
{{ page.authors | join(", ") }}
```

전체 필터 목록은 [필터](/ko/templates/filters/)를 참고합니다.

## 테스트

조건을 평가합니다.

```jinja
{% if page.url is startswith("/blog/") %}
<span>Blog post</span>
{% endif %}

{% if page.description is empty %}
<meta name="description" content="{{ site.description }}">
{% endif %}
```

테스트는 필터가 아니지만 같은 페이지에 문서화되어 있습니다 — [필터 › 테스트](/ko/templates/filters/) 참고.

## 공백 제어

마이너스 기호로 공백을 제거합니다.

```jinja
{%- if condition -%}
trimmed
{%- endif -%}
```

## raw 블록

Jinja 문법을 그대로 출력합니다.

```jinja
{% raw %}
{{ this will not be parsed }}
{% endraw %}
```

## 연산자

### 비교

| 연산자 | 설명 |
|----------|-------------|
| `==` | 같음 |
| `!=` | 같지 않음 |
| `<` | 미만 |
| `>` | 초과 |
| `<=` | 이하 |
| `>=` | 이상 |

### 논리

| 연산자 | 설명 |
|----------|-------------|
| `and` | 둘 다 참 |
| `or` | 둘 중 하나라도 참 |
| `not` | 부정 |

```jinja
{% if page.section == "blog" and not page.draft %}
<article>{{ content | safe }}</article>
{% endif %}
```

### 포함 여부

```jinja
{% if "tutorial" in page.tags %}
<span class="badge">Tutorial</span>
{% endif %}
```

## 자주 쓰는 패턴

### 활성 내비게이션

```jinja
<nav>
  <a href="/"{% if page.url == "/" %} class="active"{% endif %}>Home</a>
  <a href="/blog/"{% if page.section == "blog" %} class="active"{% endif %}>Blog</a>
</nav>
```

### 조건부 메타 태그

```jinja
<head>
  {% if page.description %}
  <meta name="description" content="{{ page.description }}">
  {% endif %}
  {{ og_all_tags | safe }}
</head>
```

### 섹션별 레이아웃

```jinja
<body data-section="{{ page.section }}">
  {% if page.section == "docs" %}
  {% include "partials/sidebar.html" %}
  {% endif %}
  
  <main>{{ content | safe }}</main>
</body>
```

### 빈 목록 확인과 반복

```jinja
{% if section.pages %}
<ul>
{% for p in section.pages %}
  <li><a href="{{ p.url }}">{{ p.title }}</a></li>
{% endfor %}
</ul>
{% else %}
<p>No articles yet.</p>
{% endif %}
```

## 함께 보기

- [데이터 모델](/ko/templates/data-model/) — 사용할 수 있는 변수
- [함수](/ko/templates/functions/) — 내장 함수
- [필터](/ko/templates/filters/) — 필터와 테스트
