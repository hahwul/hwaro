+++
title = "렌더 훅"
description = "Hugo/Zola 스타일 템플릿 훅으로 마크다운 요소의 렌더링 방식 재정의"
weight = 5
toc = true
+++

렌더 훅을 사용하면 hwaro의 마크다운 파서를 건드리지 않고 개별 마크다운 요소 — 링크, 이미지, 헤딩, 펜스 코드 블록, 인용문, 표 — 가 HTML로 바뀌는 방식을 재정의할 수 있습니다. `templates/hooks/`에 템플릿을 두면 모든 페이지의 해당 요소가 내장 마크업 대신 그 템플릿을 거쳐 렌더링됩니다.

`templates/hooks/render-*` 템플릿을 하나도 만들지 않으면 아무것도 바뀌지 않습니다. hwaro는 지금까지와 완전히 동일하게 렌더링합니다.

## 파일 구조

```
templates/
└── hooks/
    ├── render-link.html        # [text](url "title")
    ├── render-image.html       # ![alt](url "title")
    ├── render-heading.html     # ## Heading
    ├── render-codeblock.html   # ```lang ... ```
    ├── render-blockquote.html  # > quoted
    └── render-table.html       # | GFM | tables |
```

파일마다 독립적으로 동작하므로 재정의하고 싶은 것만 추가하면 됩니다. `render-image.html`만 있는 사이트는 이미지 래퍼만 커스텀되고 나머지는 기본 렌더링을 유지합니다.

그 밖의 `hooks/render-*` 이름은 인식되지 않으며 빌드 시 경고를 남깁니다.

## 컨텍스트 변수

모든 값은 Crinja `Value`이고, 다른 hwaro 템플릿과 마찬가지로 **필요한 곳은 이미 HTML 이스케이프되어** 있습니다. `| e` 필터를 쓰기 전에 아래 [규칙 1](#규칙)을 먼저 확인합니다.

### `render-link.html`

| 변수 | 설명 |
|----------|--------------|
| `destination` | 링크 대상. 이스케이프됨. `markdown.safe = true`이고 대상이 안전하지 않은 프로토콜(`javascript:` 등)을 쓰면 빈 문자열 |
| `title` | 링크의 `"title"` 텍스트. 이스케이프됨. 없으면 빈 문자열 |
| `text` | 이미 렌더링된 링크 내부 HTML(중첩 마크업이 들어 있을 수 있고, 링크가 이미지를 감싸면 훅으로 렌더링된 `<img>`가 들어 있을 수도 있음) |

### `render-image.html`

| 변수 | 설명 |
|----------|--------------|
| `destination` | 이미지 `src`. 이스케이프됨(안전하지 않은 프로토콜 규칙은 링크와 동일) |
| `alt` | 이미지의 alt 텍스트 — 마크다운 소스의 alt에 인라인 마크업이 중첩돼 있어도 순수 텍스트만(CommonMark와 동일: 이미지의 "자식"은 태그를 만들지 않음) |
| `title` | 이미지의 `"title"` 텍스트. 이스케이프됨. 없으면 빈 문자열 |

### `render-heading.html`

| 변수 | 설명 |
|----------|--------------|
| `level` | 헤딩 레벨 정수(`1`–`6`) |
| `text` | 이미 렌더링된 헤딩 내부 HTML |
| `id` | 헤딩의 id — 마크다운 소스의 커스텀 `{#id}`이거나, 자동 생성 후 중복 제거된 슬러그(`heading`, `heading-1`, `heading-2`, …) |

### `render-codeblock.html`

| 변수 | 설명 |
|----------|--------------|
| `lang` | 펜스의 언어 토큰. 이스케이프됨(`` ```python ``의 `python`). 언어 없는 펜스는 빈 문자열 |
| `options` | 언어 뒤의 Zola/Pandoc 스타일 `{...}` 옵션 블록 원문([구문 강조](/ko/features/syntax-highlighting/) 참고), `{...}` 블록이 없으면 정보 문자열의 나머지 텍스트. 이스케이프됨 |
| `code` | 펜스 본문. HTML 이스케이프됨 |
| `highlighted` | 서버 모드로 구문 강조된 본문(hljs 클래스 span). `[highlight] mode`가 `"server"`가 아니거나, 강조가 꺼져 있거나, 해당 언어의 렉서가 없으면 빈 문자열. `{hide_lines=…}` 펜스 옵션은 이미 적용된 상태 — 서버 모드에서 숨긴 줄은 템플릿(그리고 `code`)에 절대 도달하지 않음 |
| `name` | 파싱된 `{name=...}`/`{title=...}` 파일 이름 레이블. 이스케이프됨. 없으면 빈 문자열 |
| `copy` | 이 블록에 복사 버튼이 적용되면 `"true"`(`[highlight] copy` / 펜스별 `{copy=...}`, mermaid에는 절대 적용 안 됨), 아니면 빈 문자열. 어떤 마크업을 출력할지는 템플릿이 결정 |

### `render-blockquote.html`

| 변수 | 설명 |
|----------|--------------|
| `text` | 이미 렌더링된 인용문 내부 HTML — 블록 수준 콘텐츠(문단, 목록, 중첩 인용)이며 보통 개행으로 끝남 |

### `render-table.html`

| 변수 | 설명 |
|----------|--------------|
| `html` | 완성된 기본 `<table>...</table>` 마크업 전체 |
| `header_html` | 표의 `<thead>...</thead>` 부분 |
| `body_html` | 표의 `<tbody>...</tbody>` 부분 — 헤더만 있는 표는 빈 문자열 |

모든 훅 템플릿은 추가로 표준 `page`(`url`, `title`, `path`, `language`)와 `config`(`base_url`, `title`) 변수도 볼 수 있습니다.

## 기본 출력과 동일한 템플릿

다음 템플릿들은 hwaro의 기본 출력을 그대로 재현합니다 — 수정의 출발점으로 쓰기 좋습니다.

```jinja
{# templates/hooks/render-link.html #}
<a href="{{ destination }}"{% if title is present %} title="{{ title }}"{% endif %}>{{ text }}</a>
```

```jinja
{# templates/hooks/render-image.html #}
<img src="{{ destination }}" alt="{{ alt }}"{% if title is present %} title="{{ title }}"{% endif %} />
```

```jinja
{# templates/hooks/render-heading.html #}
<h{{ level }} id="{{ id }}">{{ text }}</h{{ level }}>
```

```jinja
{# templates/hooks/render-codeblock.html #}
<pre><code{% if lang is present %} class="language-{{ lang }} hljs"{% endif %}>{% if highlighted is present %}{{ highlighted }}{% else %}{{ code }}{% endif %}</code></pre>
```

```jinja
{# templates/hooks/render-blockquote.html #}
<blockquote>
{{ text }}</blockquote>
```

```jinja
{# templates/hooks/render-table.html #}
{{ html }}
```

`{% if title %}`이 아니라 `{% if title is present %}`인 점에 주의합니다 — Crinja의 참/거짓 판정은 `false`/`0`/nil만 거짓으로 보기 때문에, 그냥 `{% if title %}`을 쓰면 title이 없을 때도 `title=""`이 렌더링됩니다. 커스텀 `is present`/`is empty` 테스트(hwaro 자체 템플릿 전반에서도 사용)가 이를 올바르게 확인합니다.

codeblock 템플릿의 ` hljs` 클래스는 기본 설정(`[highlight] enabled = true` — 대부분의 Highlight.js 테마가 이 클래스를 기준으로 기본 스타일을 적용)에서의 기본 출력과 일치합니다. 강조를 완전히 껐다면 기본 출력은 ` hljs` 없이 `class="language-{{ lang }}"`을 내보내므로, 바이트 단위로 동일하게 맞추려면 훅에서도 빼면 됩니다.

## 예시: figure로 감싼 이미지

```jinja
{# templates/hooks/render-image.html #}
<figure>
  <img src="{{ destination }}" alt="{{ alt }}" loading="lazy" />
  {% if title is present %}<figcaption>{{ title }}</figcaption>{% endif %}
</figure>
```

이제 마크다운의 모든 `![alt](src "caption")`이 캡션 달린 `<figure>`로 렌더링됩니다 — 콘텐츠 파일마다 이미지 마크업을 따로 쓸 필요가 없습니다.

## 규칙

1. **값은 이미 이스케이프되어 있으니 그대로 출력합니다.** hwaro 템플릿은 (다른 곳과 마찬가지로) 자동 이스케이프가 꺼져 있고, `destination`/`title`/`alt`/`lang`/`options`/`code`는 렌더러가 이미 HTML 이스케이프한 값입니다. 이들을 `| e`에 통과시키면 이중 이스케이프가 되고, `text`나 `highlighted`를 통과시키면 이미 렌더링된 HTML이 깨집니다.
2. **관례대로 큰따옴표로 감싼 `href`/`src` 속성을 유지합니다.** 이후 단계 전부 — `@/internal-page.md` 링크 해석, 루트 상대 링크의 서브패스(`base_path`) 접두사 처리, 반응형 이미지 `srcset`/`sizes` 주입, `loading="lazy"` — 가 *최종* HTML을 대상으로 `href="..."` / `src="..."` 패턴을 찾는 일반 텍스트 패스로 동작합니다. 따옴표 없는 속성이나 작은따옴표 속성을 내보내는 훅, 또는 대상을 일반적인 속성 값이 아닌 형태로 바꿔 버리는 훅은 해당 요소를 이 모든 처리에서 제외시킵니다. `@/` 접두사가 붙은 `destination`은 `InternalLinkResolver`가 찾아 해석할 수 있도록 반드시 `href="..."` 안에 들어가야 합니다.
3. **`render-heading.html`은 `<hN id="{{ id }}">` 요소를 출력해야 합니다.** 목차(`{{ toc }}` / `page.toc`)와 `insert_anchor_links`는 둘 다 최종 HTML에서 `id` 속성이 있는 `<h1>`–`<h6>` 태그를 찾아 후처리합니다. 헤딩 태그가 아닌 것을 렌더링하거나 `id`를 빼먹는 훅은 조용히 둘 다에서 빠집니다.
4. **`{{ text }}`를 변형하지 않습니다.** 이미 렌더링된 HTML이고, 숏코드를 쓰는 페이지에서는 나중 패스에서 숏코드 출력으로 치환될 내부 플레이스홀더 주석(`<!--HWARO-SHORTCODE-PLACEHOLDER-N-->`)이 들어 있을 수 있습니다 — `text`를 필터링·잘라내기·재이스케이프하면 그 플레이스홀더가 깨지거나 미아가 될 수 있습니다.
5. **Mermaid는 자기 펜스를 직접 처리합니다.** `[markdown] mermaid = true`이면 `` ```mermaid `` 펜스는 항상 기존 Mermaid 파이프라인(`<div class="mermaid">…</div>`)을 거치고 `render-codeblock.html`은 절대 거치지 않습니다 — "모든 훅은 일치하는 모든 요소에 항상 적용된다"의 설정으로 결정되는 예외입니다. `mermaid = false`로 설정하면 codeblock 훅이 mermaid 펜스도 다른 언어처럼 렌더링합니다.
6. **어드모니션은 자기 인용문을 직접 처리합니다.** `[markdown] admonitions = true`(기본값)이면 `> [!NOTE]` 스타일 인용문은 계속 어드모니션 파이프라인(`<div class="admonition admonition-note">…</div>`)을 거치고 `render-blockquote.html`은 절대 거치지 않습니다 — Mermaid와 같은, 설정으로 결정되는 패턴입니다. `admonitions = false`로 설정하면 그런 인용문도 다른 인용문처럼 훅을 거칩니다.
7. **`render-table.html` 출력에 빈 줄을 넣지 않습니다.** 표 훅의 출력은 본 파싱 *이전에* 마크다운에 삽입되는데, HTML 블록은 첫 빈 줄에서 끝나므로 그 뒤는 다시 마크다운으로 파싱됩니다. hwaro가 안전장치로 출력에서 빈 줄을 제거해 주므로 여러 줄 템플릿도 동작하지만, 빈 줄에 의존하는 마크업은 쓰지 않는 것이 좋습니다.
8. **훅은 표 셀, 각주 본문, 정의 목록, 프론트 매터의 `description`/요약 텍스트 안에는 적용되지 않습니다.** 이들은 훅이 붙는 본 Markd 파서를 전혀 거치지 않는 별도의 단순한 인라인 마크다운 경로로 렌더링됩니다(`render-table.html`이 표 자체를 감싸더라도 표 *셀*은 그 경로를 유지합니다). 버그가 아니라 알려진 제약입니다.

## 증분 빌드

`templates/hooks/` 아래 파일 편집은 `hwaro build --cache`와 `hwaro serve`에서 다른 템플릿 편집과 똑같이 추적됩니다 — 다만 훅은 어떤 페이지 템플릿에서도 `{% include %}`/`{% extends %}`로 도달하지 않기 때문에, hwaro가 영향을 받는 페이지를 좁혀낼 수 없습니다. `templates/hooks/render-*.html` 파일을 편집하면 `[build] template_deps` 설정과 무관하게 **모든** 페이지가 다시 렌더링됩니다. [증분 빌드](/ko/features/incremental-build/)를 참고합니다.

## 함께 보기

- [구문 강조](/ko/features/syntax-highlighting/) — `render-codeblock.html`에 전달되는 펜스 언어/옵션 파싱
- [마크다운 확장](/ko/features/markdown-extensions/) — `{#custom-id}` 헤딩과 Mermaid 다이어그램
- [템플릿](/ko/templates/) — 템플릿 디렉터리 구조와 선택 규칙
