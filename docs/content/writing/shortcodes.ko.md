+++
title = "숏코드"
description = "마크다운 콘텐츠에서 쓰는 재사용 가능한 템플릿 조각"
weight = 4
toc = true
+++

숏코드는 마크다운 콘텐츠 안에서 쓸 수 있는 재사용 가능한 템플릿 조각입니다. 커스텀 숏코드는 `templates/shortcodes/`에 두는 Jinja2 템플릿입니다 — 템플릿 언어 레퍼런스는 [문법](/ko/templates/syntax/)을 참고합니다.

## 숏코드 사용

콘텐츠 파일에서는 두 가지 문법이 동작합니다:

```markdown
{%raw%}{{ shortcode_name(arg1="value", arg2="value") }}{%endraw%}
```

또는 명시적으로:

```markdown
{%raw%}{{ shortcode("shortcode_name", arg1="value") }}{%endraw%}
```

### 블록 숏코드 닫기

블록 숏코드는 두 가지 닫기 스타일을 지원합니다:

- **단순 닫기(bare closer)**:
  ```jinja
  {% note %}...{% end %}
  ```

- **이름 있는 닫기(named closer)** (권장):
  ```jinja
  {% note %}...{% endnote %}
  {% alert(type="info") %}...{% endalert %}
  ```

단순하지 않은 콘텐츠에는 **이름 있는 닫기**(`{% endNAME %}`)를 강력히 권장합니다. 여러 숏코드를 섞어 쓰거나 깊게 중첩할 때 마크다운을 읽고 유지보수하기가 훨씬 쉬워집니다.

## 내장 숏코드

Hwaro에는 템플릿 파일 없이 바로 동작하는 내장 숏코드가 들어 있습니다.

### youtube

YouTube 동영상을 삽입합니다.

```markdown
{%raw%}{{ youtube(id="dQw4w9WgXcQ") }}
{{ youtube(id="dQw4w9WgXcQ", width="800", height="450") }}{%endraw%}
```

| 파라미터 | 기본값 | 설명 |
|-------|---------|-------------|
| `id` | (필수) | YouTube 동영상 ID |
| `width` | `560` | 플레이어 너비 |
| `height` | `315` | 플레이어 높이 |
| `title` | `YouTube Video` | 접근성용 제목 |

### vimeo

Vimeo 동영상을 삽입합니다.

```markdown
{%raw%}{{ vimeo(id="123456789") }}{%endraw%}
```

| 파라미터 | 기본값 | 설명 |
|-------|---------|-------------|
| `id` | (필수) | Vimeo 동영상 ID |
| `width` | `560` | 플레이어 너비 |
| `height` | `315` | 플레이어 높이 |
| `title` | `Vimeo Video` | 접근성용 제목 |

### gist

GitHub Gist를 삽입합니다.

```markdown
{%raw%}{{ gist(user="octocat", id="abc123") }}
{{ gist(user="octocat", id="abc123", file="hello.rb") }}{%endraw%}
```

| 파라미터 | 기본값 | 설명 |
|-------|---------|-------------|
| `user` | (필수) | GitHub 사용자 이름 |
| `id` | (필수) | Gist ID |
| `file` | (없음) | 표시할 특정 파일 |

### alert / callout

알림 상자를 표시합니다. 콘텐츠를 감싸는 블록 숏코드로 사용합니다.

단순 닫기와 이름 있는 닫기를 모두 지원합니다(복잡한 페이지에는 이름 있는 닫기를 권장합니다):

```markdown
{%raw%}{% alert(type="warning", title="Caution") %}Be careful with this!{% end %}
{% alert(type="tip") %}Using named closer also works{% endalert %}{%endraw%}
```

(명확성을 위해 이름 있는 닫기 스타일을 권장합니다.)

| 파라미터 | 기본값 | 설명 |
|-------|---------|-------------|
| `type` | `info` | `info`, `warning`, `danger`, `tip`, `success` |
| `title` | (없음) | 선택적 제목 |

### figure

캡션을 붙일 수 있는 이미지입니다.

```markdown
{%raw%}{{ figure(src="/img/photo.jpg", alt="A photo", caption="My caption") }}{%endraw%}
```

| 파라미터 | 기본값 | 설명 |
|-------|---------|-------------|
| `src` | (필수) | 이미지 URL |
| `alt` | `""` | 대체 텍스트 |
| `caption` | (없음) | 이미지 아래 캡션 |
| `width` | (없음) | 이미지 너비 |
| `height` | (없음) | 이미지 높이 |

### tweet

트윗을 삽입합니다.

```markdown
{%raw%}{{ tweet(user="jack", id="20") }}{%endraw%}
```

| 파라미터 | 기본값 | 설명 |
|-------|---------|-------------|
| `user` | (필수) | Twitter 사용자 이름 |
| `id` | (필수) | 트윗 ID |

### codepen

CodePen을 삽입합니다.

```markdown
{%raw%}{{ codepen(user="chriscoyier", id="gfdDu") }}
{{ codepen(user="chriscoyier", id="gfdDu", tab="css,result", height="400") }}{%endraw%}
```

| 파라미터 | 기본값 | 설명 |
|-------|---------|-------------|
| `user` | (필수) | CodePen 사용자 이름 |
| `id` | (필수) | Pen ID |
| `tab` | `result` | 기본으로 열릴 탭 |
| `height` | `300` | 삽입 높이 |
| `title` | `CodePen Embed` | 접근성용 제목 |

> 내장 숏코드를 덮어쓰려면 `templates/shortcodes/`에 같은 이름의 파일을 만들면 됩니다(예: `templates/shortcodes/youtube.html`). 사용자 템플릿이 항상 우선합니다.

## 커스텀 숏코드 작성

숏코드 템플릿은 `templates/shortcodes/`에 둡니다.

### 예시: 알림 상자

`templates/shortcodes/alert.html`을 만듭니다:

```jinja
{% if type and message %}
<div class="alert alert-{{ type }}">
  {{ message | safe }}
</div>
{% endif %}
```

콘텐츠에서 사용:

```markdown
{%raw%}{{ alert(type="warning", message="This is important!") }}{%endraw%}
```

출력:

```html
<div class="alert alert-warning">
  This is important!
</div>
```

### 예시: YouTube 삽입

`templates/shortcodes/youtube.html`을 만듭니다:

```jinja
{% if id %}
<div class="video-container">
  <iframe 
    src="https://www.youtube.com/embed/{{ id }}"
    frameborder="0"
    allowfullscreen>
  </iframe>
</div>
{% endif %}
```

콘텐츠에서 사용:

```markdown
{%raw%}{{ youtube(id="dQw4w9WgXcQ") }}{%endraw%}
```

### 예시: 캡션 있는 figure

`templates/shortcodes/figure.html`을 만듭니다:

```jinja
<figure>
  <img src="{{ src }}" alt="{{ alt | default(value='') }}">
  {% if caption %}
  <figcaption>{{ caption }}</figcaption>
  {% endif %}
</figure>
```

콘텐츠에서 사용:

```markdown
{%raw%}{{ figure(src="/images/photo.jpg", alt="A photo", caption="My caption") }}{%endraw%}
```

### 예시: 이미지 갤러리(에셋 코로케이션)

페이지와 같은 디렉터리(페이지 번들)에 있는 이미지를 자동으로 나열하는 갤러리를 만들 수 있습니다.

`templates/shortcodes/gallery.html`을 만듭니다:

```jinja
<div class="gallery">
{% for asset in page.assets -%}
  {%- if asset is matching("[.](jpg|png)$") -%}
    {% set image = resize_image(path=asset, width=240, height=180) %}
    <a href="{{ get_url(path=asset) }}" target="_blank">
      <img src="{{ image.url }}" alt="{{ asset }}" />
    </a>
  {%- endif %}
{%- endfor %}
</div>
```

콘텐츠에서 사용(페이지 번들 디렉터리 안에서):

```markdown
{%raw%}{{ gallery() }}{%endraw%}
```

마크다운 파일 옆에 있는 모든 JPG/PNG 이미지가 그리드로 렌더링됩니다.

## 블록 숏코드

블록 숏코드는 여는 태그와 닫는 태그 사이의 콘텐츠를 감쌉니다:

```markdown
{%raw%}{% note() %}
This is the **body** content of the shortcode.
{% end %}{%endraw%}
```

본문은 `body` 변수로 숏코드 템플릿에 전달됩니다. 마크다운 변환은 자동으로 적용되지 **않으므로**, 필요하면 템플릿에서 `markdownify` 필터를 사용합니다:

```jinja
<div class="note">
  {{ body | markdownify | safe }}
</div>
```

원문 그대로 쓰려면 `body`를 그대로 출력합니다:

```jinja
<div class="note">{{ body }}</div>
```

### 중첩 숏코드

블록 숏코드는 최대 5단계까지 중첩할 수 있습니다:

```markdown
{%raw%}{% outer() %}
  Some text with {{ inner(type="info") }} inside.
{% end %}{%endraw%}
```

## 인자 문법

### 이름 있는 인자

인자는 여러 따옴표 스타일을 지원합니다:

```markdown
{%raw%}{{ alert(type="warning", message="Double quotes") }}
{{ alert(type='info', message='Single quotes') }}
{{ alert(type=danger, message=No quotes for simple values) }}{%endraw%}
```

### 위치 인자

`key=value` 문법을 쓰지 않으면 인자가 `_0`, `_1`, … 로 할당됩니다:

```markdown
{%raw%}{{ youtube("dQw4w9WgXcQ") }}{%endraw%}
```

숏코드 템플릿에서는 `{{ _0 }}`으로 접근합니다:

```jinja
<iframe src="https://www.youtube.com/embed/{{ _0 }}"></iframe>
```

## 내장 변수

숏코드에서 접근할 수 있는 값:

- 전달된 모든 인자
- `site` 객체
- `page` 객체
- 표준 필터와 함수

```jinja
{# In shortcode template #}
<a href="{{ site.base_url }}/{{ url }}">{{ text }}</a>
```

## 팁

### 인자 검증

필수 인자는 항상 확인합니다:

```jinja
{% if not url %}
<p class="error">Missing url parameter</p>
{% else %}
<a href="{{ url }}">{{ text | default(value="Link") }}</a>
{% endif %}
```

### HTML에는 safe 필터 사용

HTML 콘텐츠를 전달할 때:

```jinja
{{ content | safe }}
```

### 숏코드 정리

관련 숏코드를 묶어서 관리합니다:

```
templates/shortcodes/
├── alert.html
├── youtube.html
├── figure.html
├── code/
│   ├── tabs.html
│   └── snippet.html
└── social/
    ├── twitter.html
    └── github.html
```

## 함께 보기

- [문법](/ko/templates/syntax/) — 커스텀 숏코드를 위한 Jinja2 레퍼런스
- [함수](/ko/templates/functions/) — 내장 템플릿 함수
