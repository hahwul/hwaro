+++
title = "템플릿"
description = "Jinja2 템플릿으로 사이트를 디자인합니다"
weight = 3
sort_by = "weight"
+++

템플릿은 콘텐츠가 HTML로 바뀌는 방식을 정의합니다. Hwaro는 Jinja2 호환 엔진인 Crinja를 사용합니다.

## 템플릿 디렉터리

```
templates/
├── base.html           # Base layout
├── page.html           # Regular pages
├── section.html        # Section index pages
├── index.html          # Homepage (optional)
├── taxonomy.html       # Taxonomy listing
├── taxonomy_term.html  # Taxonomy term page
├── 404.html            # Error page
├── shortcodes/         # Shortcode templates
└── hooks/              # Markdown render-element overrides (link/image/heading/codeblock)
```

`shortcodes/` 디렉터리에는 마크다운에 삽입할 수 있는 재사용 컴포넌트를 둡니다. 사용법과 커스텀 숏코드 만드는 방법은 [콘텐츠 작성: 숏코드](/ko/writing/shortcodes/)를 참고합니다.

HTML 외에도 페이지/섹션은 `[outputs]` 설정으로 활성화한 형제 파일 `templates/page.<fmt>.jinja` / `templates/section.<fmt>.jinja`(JSON, XML, TXT, CSV)를 추가로 렌더링할 수 있습니다 — [출력 포맷](/ko/features/output-formats/) 참고.

`hooks/` 디렉터리는 개별 마크다운 요소가 렌더링되는 방식을 재정의합니다 — [렌더 훅](/ko/templates/render-hooks/) 참고.

## 템플릿 선택

| 콘텐츠 | 템플릿 |
|---------|----------|
| content/index.md | index.html 또는 page.html |
| content/about.md | page.html |
| content/blog/_index.md | section.html |
| content/blog/post.md | page.html |
| 택소노미 인덱스 | taxonomy.html |
| 택소노미 항목 | taxonomy_term.html |

## 간단한 예시

```jinja
{% extends "base.html" %}

{% block content %}
<article>
  <h1>{{ page.title }}</h1>
  <time>{{ page.date }}</time>
  {{ content | safe }}
</article>
{% endblock %}
```
