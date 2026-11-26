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
{{ page.title | e }}
{{ site.description | e }}
{{ content }}
```

출력되는 값은 안전 값으로 표시되지 않으면 HTML 이스케이프됩니다. [HTML 이스케이프](#html-이스케이프)를 참고합니다.

괄호로 묶은 표현식 뒤에도 속성, 인덱스, 호출 접근을 쓸 수 있으므로 필터나 함수 결과에서 바로 필드를 읽을 수 있습니다.

```jinja
{{ (section.pages | first).title | e }}
{{ (get_section(path="blog").pages | map(attribute="title") | list)[0] | e }}
```

## HTML 이스케이프

Jinja2처럼, 템플릿이 출력하는 값은 *안전(safe)* 값이 아니면 모두 HTML 이스케이프됩니다. 작성자 텍스트(제목, 설명, 섹션 이름과 택소노미 이름, `extra` 필드, 데이터 파일, i18n 문자열)는 요소 텍스트든 속성 값이든 출력하는 곳마다 한 번 이스케이프되며, 여기에 `| e`를 붙여도 문제없습니다(두 번 이스케이프하지 않습니다). 마크업으로 출력하려는 작성자 HTML에는 `| safe`가 필요합니다. 예: `{{ page.extra.banner | safe }}`.

hwaro가 HTML로 렌더링한 값(`content`, `toc`, `page.summary`, `og_all_tags`와 그 밖의 `*_tags` 변수 등, [HTML 값](/ko/templates/data-model/#html-값) 참고)은 안전 값이라 그대로 출력됩니다.

`config.toml`에 `[templates] autoescape = false`를 쓰면 이스케이프가 꺼집니다. 모든 값이 hwaro 0.x와 똑같이 그대로 출력되므로, 콘텐츠나 데이터에서 온 텍스트는 출력하는 곳마다 `| e`를 거치게 하세요. 예: `<meta name="description" content="{{ page.description | e }}">`. 텍스트에는 `| e`, 작성자 HTML에는 `| safe`를 붙여 쓴 템플릿은 어느 설정에서나 같은 결과를 냅니다.

출력이 HTML이나 XML인 템플릿이 이스케이프합니다. `.html`, `.htm`, `.xhtml`, `.xml`, `.svg`, `.rss`, `.atom`으로 끝나는 파일(뒤에 붙은 `.jinja`, `.j2`, `.jinja2`, `.ecr`는 무시), 형식이 드러나지 않는 이름(`page.j2`), 내장 숏코드, RSS와 Atom 피드 템플릿이 그렇습니다. 텍스트 출력은 이스케이프하지 않습니다. `.json`, `.txt`, `.csv`, `.js`, `.mjs`, `.css`, `.md`, `.markdown` 템플릿(그래서 `page.json.jinja`, `feed.json.jinja`), `[[content.generate]]`의 스펙과 `body_template` 파일, 그리고 텍스트 출력이 include한 모든 것이 그렇습니다. hwaro가 쓰는 파일의 형식을 알 때는 템플릿 이름이 아니라 그 형식이 진입 템플릿의 이스케이프를 정합니다. 프런트 매터가 `plain.txt.jinja`를 고르더라도 `index.html`로 쓰는 페이지는 이스케이프하고, `[outputs]`의 JSON·텍스트·CSV 파일은 템플릿 이름과 상관없이 이스케이프하지 않습니다. HTML 템플릿이 include, import로 불러온 파일은 자기 이름을 따르지만(`.js` 조각은 이스케이프하지 않습니다), HTML 템플릿이 텍스트 파일에서 import한 값(`vars.txt.jinja`의 `{% set %}` 캡처)은 일반 텍스트로 넘어와 출력할 때 이스케이프됩니다. `{% extends %}` 체인은 ENTRY 템플릿(페이지가 렌더링되는 템플릿)을 따릅니다 — Jinja2처럼 렌더 한 번에 이스케이프 정책 하나입니다. 템플릿 안에서 일부 구간만 끄거나 켤 수 있습니다.

```jinja
{% autoescape false %}{{ legacy_html }}{% endautoescape %}
```

이 블록은 그 안에서 include한 파일에는 미치지 않습니다. 자동 이스케이프에서는 다음도 달라집니다.

- `a ~ b`(문자열의 `a + b`도)에 안전 값이 있으면 다른 쪽을 이스케이프하고 결과도 안전 값입니다. `{{ "<p>" ~ x }}`는 `&lt;p&gt;`를 출력하므로, 마크업은 출력이 안전 값인 `{% set %}…{% endset %}` 블록이나 매크로로 만드세요.
- `| e`와 `| escape`는 안전 값을 건드리지 않습니다. 단, hwaro가 렌더링한 HTML(`content`, `page.summary` 등 데이터 모델의 HTML 값)은 1.0 이전처럼 여전히 이스케이프하므로, `section.pages`를 도는 `{{ p.summary | escape }}`나 RSS·Atom 템플릿의 `{{ p.content_html | escape }}`는 마크업을 텍스트로 보여 줍니다(피드 템플릿의 `p.summary`는 이미 일반 텍스트이므로 `| escape`가 한 번 이스케이프합니다). 0.x처럼 거기서 파생한 값도 마찬가지입니다. `{{ content[:300] | e }}`, `{{ p.summary | truncate(200) | escape }}`, `{{ (content ~ "…") | e }}`, 그리고 `markdownify`와 `tojson`의 결과도 이스케이프하므로 `data-x="{{ v | tojson | e }}"`의 따옴표는 계속 속성 안에 머뭅니다. `| forceescape`와 `| xml_escape`는 어떤 값이든 이스케이프합니다.
- `{{ x | tojson }}`은 `<`, `>`, `&`, `'`를 `\u003c` 형태로 쓴 안전한 JSON이라 `<script>` 안에 바로 넣을 수 있습니다.

### 0.x에서 옮겨 올 때

0.22와 1.0 사이에 달라지는 나머지는 [1.0으로 업그레이드](/ko/start/upgrading/)에 정리되어 있습니다.

1.0 이전에는 템플릿이 `| e`를 쓰지 않으면 아무것도 이스케이프되지 않았습니다. 기본값이 사이트에서 무엇을 바꾸는지 보려면, 그대로 한 번, 이스케이프를 끄고 한 번 서로 다른 디렉터리에 빌드해 비교합니다.

```bash
hwaro build -o /tmp/site-1x
# 이제 config.toml의 [templates]에 `autoescape = false`를 적습니다
hwaro build -o /tmp/site-0x
diff -r /tmp/site-0x /tmp/site-1x
# 다 보면 `true`로 되돌립니다(0.x 출력을 유지하려면 `false`로 둡니다)
```

차이는 둘 중 하나입니다. 0.x가 이스케이프하지 않고 출력하던 텍스트이거나(`Tom & Jerry`가 이제 `Tom &amp; Jerry`로 출력됩니다. 브라우저에서는 똑같이 보이고, 더는 속성 밖으로 빠져나갈 수 없습니다), 이제 텍스트로 보이게 되어 출력하는 곳에 `| safe`가 필요한 작성자 HTML입니다. 그런 다음 `config.toml`에 선택을 적어 둡니다(`autoescape = true`, 또는 0.x 출력을 유지하려면 `false`). 템플릿이 있는데 이 키를 적지 않은 사이트는 `hwaro doctor`가 알려 줍니다. 새 사이트는 `hwaro init`이 이 키를 써 둡니다. 텍스트 출력(`page.json.jinja`, `page.txt.jinja`)에서만 보이는 차이가 하나 있습니다. `toc_obj.headers[].title`, `.id`, `.permalink`가 그곳에서도 완전히 이스케이프된 텍스트로 나오므로 `it's`가 `it&#39;s`로 출력됩니다(0.x에서도 작은따옴표만 빼고 이스케이프된 텍스트였습니다).

## 주석

```jinja
{# This is a comment #}
```

## 조건문

```jinja
{% if page.description %}
<meta name="description" content="{{ page.description | e }}">
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

표현식 안에서 인라인으로 쓸 수도 있습니다(`else` 부분은 생략할 수 있으며, 생략하면 빈 값으로 렌더링됩니다).

```jinja
<a href="{{ item.href }}" class="{{ 'active' if item.url == page.url else '' }}">{{ item.name | e }}</a>
{% set label = page.title if page.title else "Untitled" %}
```

`a or b`는 `a`가 참이면 `a`를, 아니면 `b`를 반환하므로 대체값으로 쓸 수 있습니다: `{{ page.description or site.description }}`.

## 반복문

```jinja
{% for p in section.pages %}
<li><a href="{{ base_url }}{{ p.url }}">{{ p.title | e }}</a></li>
{% endfor %}
```

인덱스와 함께:

```jinja
{% for tag in page.tags %}
{% if not loop.first %}, {% endif %}
{{ tag | e }}
{% endfor %}
```

반복 변수:

| 변수 | 설명 |
|----------|-------------|
| loop.index | 현재 반복 횟수(1부터 시작) |
| loop.index0 | 현재 반복 횟수(0부터 시작) |
| loop.first | 첫 반복에서 true |
| loop.last | 마지막 반복에서 true |
| loop.length | 전체 항목 수(`{% for x in xs if … %}`처럼 걸러낸 반복에서도) |
| loop.revindex | 현재를 포함해 남은 반복 횟수(`loop.revindex0`: 현재 제외) |
| loop.previtem / loop.nextitem | 이전 / 다음 항목(양 끝에서는 빈 값) |
| loop.changed(value) | `value`가 직전 호출과 다르면 true |
| loop.cycle(a, b, …) | 주어진 값을 차례로 반복 |
| loop.depth | `recursive` 반복의 중첩 깊이(최상위가 1, `loop.depth0`은 0부터) |

### 슬라이싱

Jinja2처럼 `[start:stop:step]`으로 리스트나 문자열의 일부를 꺼냅니다. 각 부분은 생략할 수 있고, 음수는 끝에서부터 세며, 범위를 벗어난 값은 양 끝에 맞춰집니다:

```jinja
{% for p in section.pages[:5] %}
<li><a href="{{ base_url }}{{ p.url }}">{{ p.title | e }}</a></li>
{% endfor %}

{{ page.title[:40] | e }}
{% for p in section.pages[::-1] %}…{% endfor %}
```

긴 목록에서 앞의 몇 개만 보여 줄 때는 `{% if loop.index <= 5 %}`로 나머지를 건너뛰지 말고 슬라이스를 쓰세요. `if` 방식은 페이지마다 목록 전체를 순회할 수 있습니다.

## 템플릿 상속

### 베이스 템플릿

`templates/base.html`:

```jinja
<!DOCTYPE html>
<html>
<head>
  <title>{% block title %}{{ site.title | e }}{% endblock %}</title>
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

{% block title %}{{ page.title | e }} - {{ site.title | e }}{% endblock %}

{% block content %}
<article>
  <h1>{{ page.title | e }}</h1>
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

include한 파일은 페이지가 아니라 자기 이름에 따라 이스케이프합니다. HTML 페이지 안의 `{% include "partials/x.txt.jinja" %}`(또는 `.js`, `.css`, `.json`, `.md`, `.csv` 조각)는 값을 이스케이프하지 않고 출력하므로, 이런 조각이 HTML에 출력하는 작성자 텍스트에는 `| e`를 붙이세요.

부분 템플릿 안의 `{% set %}`과 `{% macro %}`는 `with context`든 `without context`든 불러온 템플릿에 전달되지 않습니다. 변수나 매크로를 함께 쓰려면 `{% import %}`나 `{% from %}`을 사용하세요.

## 매크로

`{% macro %}`로 재사용할 조각을 정의하고(보통 부분 템플릿에 둡니다), 필요한 곳에서 가져와 씁니다.

`templates/partials/macros.html`:

```jinja
{% macro card(p, show_date=true) %}
<a href="{{ base_url }}{{ p.url }}">{{ p.title | e }}</a>
{% if show_date and p.date %}<time>{{ p.date }}</time>{% endif %}
{% endmacro %}
```

```jinja
{% import "partials/macros.html" as m %}
{% for p in section.pages %}{{ m.card(p) }}{% endfor %}

{% from "partials/macros.html" import card %}
{{ card(page, show_date=false) }}
```

한 번의 렌더링에서 같은 파일을 여러 번 가져와도 됩니다. 예를 들어 베이스 레이아웃과 그것을 상속하는 자식 템플릿이 각각 가져오거나, 두 이름으로 가져올 수 있습니다. 실제 순환(`a.html`이 `b.html`을, `b.html`이 다시 `a.html`을 가져오는 경우)만 오류입니다.

가져온 파일의 최상위 `{% set %}` 변수도 쓸 수 있습니다. `{% import "partials/vars.html" as v %}` 다음에는 `{{ v.accent }}`로, `{% from "partials/vars.html" import accent %}` 다음에는 `{{ accent }}`로 읽습니다. 이름이 `_`로 시작하는 변수는 내보내지 않습니다.

## 변수 설정

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
<meta name="description" content="{{ site.description | e }}">
{% endif %}
```

테스트는 필터가 아니지만 같은 페이지에 문서화되어 있습니다. [필터 › 테스트](/ko/templates/filters/#테스트)를 참고합니다.

## 공백 제어

마이너스 기호로 공백을 제거합니다. 구분자 옆의 `-`(`{%-`, `-%}`, `{{-`, `-}}`, `{#-`, `-#}`)는 Jinja2와 같이 그쪽의 줄바꿈을 포함한 모든 공백을 제거합니다.

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
  <meta name="description" content="{{ page.description | e }}">
  {% endif %}
  {{ og_all_tags | safe }}
</head>
```

### 섹션별 레이아웃

```jinja
<body data-section="{{ page.section | e }}">
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
  <li><a href="{{ base_url }}{{ p.url }}">{{ p.title | e }}</a></li>
{% endfor %}
</ul>
{% else %}
<p>No articles yet.</p>
{% endif %}
```

## Jinja2와 다른 점

Jinja2용으로 작성한 템플릿은 대부분 그대로 동작합니다. 알아 둘 차이는 다음과 같습니다.

- **출력되는 값.** 불리언과 none은 `true`, `false`, `none`으로 출력되고(Jinja2는 `True`, `False`, `None`), 맵은 `{'a' => 1}`로 출력됩니다. 리스트나 맵을 그대로 출력하지 말고 `| tojson`, `| join` 등으로 형식을 정하세요.
- **Python 메서드 없음.** `s.upper()`, `s.split(",")`, `d.items()`, `list.append(x)`는 정의되지 않습니다. 필터(`| upper`, `| split(pat=",")`, `| dictsort`)를 쓰세요. 맵을 두 이름으로 순회하면(`{% for k, v in d %}`) 키와 값을 얻습니다.
- **지원하지 않는 것:** `namespace()`, `{% set a, b = ... %}`, `{% set x | filter %}...{% endset %}`, 호출의 `*args` / `**kwargs`, `self.<블록>()`, `{%+`, 연쇄 비교(`a < b < c`), 문자열 반복(`"-" * 3`), 지수 표기 숫자(`1e3`), `items` 필터, `true` / `false` / `boolean` / `integer` / `float` 테스트. 모두 위치를 알려 주는 템플릿 오류가 되며, 조용히 잘못 출력되지는 않습니다.
- **연산자.** `**`는 오른쪽부터 묶이고(`2 ** 3 ** 2`는 `512`, Jinja2는 `64`), 앞의 마이너스는 그 뒤에 적용됩니다(`-2 ** 2`는 `-4`, Jinja2는 `4`). 결과가 중요하면 괄호를 쓰세요.
- **괄호 없는 테스트 인자는 값 하나입니다.** Jinja2와 같습니다. `loop.index is divisibleby 3 and not loop.last`는 `(loop.index is divisibleby 3) and not loop.last`입니다. 1.0 이전에는 인자가 표현식의 나머지를 모두 가져갔기 때문에 `page.url is startswith "/blog" ~ "/"`는 `"/blog/"`와 비교했지만, 이제는 테스트 결과 뒤에 `"/"`를 이어 붙이므로 `{% if %}`에서는 항상 참입니다. 이런 인자 뒤에 `~`, `+`, `-`, `*`, `/`, `//`, `%`, 필터 `|`, 또는 다른 `is`가 오면 빌드가 템플릿 파일과 줄을 알려 주는 경고를 냅니다. 표현식 전체와 비교하려면 `startswith("/blog" ~ "/")`로, 지금의 해석을 유지하려면 `(page.url is startswith "/blog") ~ "/"`로 쓰세요.
- **hwaro의 `default`와 `unique`.** `default`는 `none`과 빈 문자열도 바꾸고, 비어 있지 않은 스칼라는 문자열로 반환합니다([필터 › 기본값](/ko/templates/filters/#기본값) 참고). `unique`는 `case_sensitive=false`가 아니면 문자열의 대소문자를 구분합니다.
- **너그러운 호출.** 매크로는 남는 인자를 오류 없이 무시하고, `attr`는 맵의 키도 읽으며, 가져온 매크로는 `with context` 없이도 가져온 템플릿의 변수를 봅니다.
- Jinja2처럼 쓸 수 있는 것: `range()`, `dict()`, `cycler()`, `joiner()` 함수, `forceescape` 필터, `divisibleby`, `sameas`, `mapping`, `sequence`, `lower`, `upper`, `undefined`, `in` 테스트.

## 함께 보기

- [데이터 모델](/ko/templates/data-model/) — 사용할 수 있는 변수
- [함수](/ko/templates/functions/) — 내장 함수
- [필터](/ko/templates/filters/) — 필터와 테스트
