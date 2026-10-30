+++
title = "필터"
description = "파이프 연산자로 템플릿의 값 변환"
weight = 4
toc = true
+++

필터는 템플릿에서 값을 변환합니다. 파이프 `|` 연산자로 적용합니다.

Hwaro는 표준 Crinja(Jinja2) 내장 필터(`upper`, `lower`, `join`, `map`, `select`, `batch` 등) 위에 자체 필터를 얹어 제공하므로, 아래 어디서든 두 종류 모두 사용할 수 있습니다.

아래 표에 나온 내장 필터 외에 다음 Jinja2 필터도 사용할 수 있습니다: `abs`, `attr`, `batch`, `center`, `dictsort`, `escape`(`e`), `filesizeformat`, `float`, `format`, `groupby`, `indent`, `int`, `list`, `map`, `random`, `reject`, `rejectattr`, `round`, `select`, `selectattr`, `slice`, `string`, `striptags`, `sum`, `title`, `truncate`, `urlencode`, `urlize`, `wordcount`, `wordwrap`, `xmlattr`.

## 문법

```jinja
{{ value | filter }}
{{ value | filter(arg="value") }}
{{ value | filter1 | filter2 }}
```

## 텍스트 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| upper | 대문자로 변환 | {{ "hello" \| upper }} → HELLO |
| lower | 소문자로 변환 | {{ "HELLO" \| lower }} → hello |
| capitalize | 첫 글자를 대문자로 | {{ "hello" \| capitalize }} → Hello |
| trim | 앞뒤 공백 제거 | {{ "  hi  " \| trim }} → hi |
| replace | 텍스트 치환 | {{ "hello" \| replace("l", "x") }} → hexxo |
| slugify | URL 슬러그로 변환 | {{ "Hello World" \| slugify }} → hello-world |
| truncate_words | 단어 수 제한. `end`로 말줄임 문자 지정(기본 `...`) | {{ text \| truncate_words(20, end="…") }} |
| regex_replace | 정규식에 맞는 부분을 모두 치환([정규 표현식](#정규-표현식) 참고) | {{ "a1b22" \| regex_replace(pattern="[0-9]+", rep="#") }} → a#b# |

## 인코딩 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| base64_encode | 텍스트를 base64로 인코딩(표준 알파벳, 패딩 포함) | {{ "hi" \| base64_encode }} → aGk= |
| base64_decode | base64 디코딩(표준/URL-safe 알파벳 모두, 패딩은 선택) | {{ "aGk=" \| base64_decode }} → hi |
| md5 | 텍스트의 MD5 다이제스트(소문자 16진수) | {{ "abc" \| md5 }} → 900150983cd2… |
| sha1 | SHA-1 다이제스트(소문자 16진수) | {{ "abc" \| sha1 }} |
| sha256 | SHA-256 다이제스트(소문자 16진수) | {{ "abc" \| sha256 }} |
| sha384 | SHA-384 다이제스트(소문자 16진수) | {{ "abc" \| sha384 }} |
| sha512 | SHA-512 다이제스트(소문자 16진수) | {{ "abc" \| sha512 }} |

해시 필터는 문자열의 UTF-8 바이트로 다이제스트를 계산합니다. `base64=true`를 넘기면 16진수 대신 base64로 돌려주므로, 예를 들어 `sha384-{{ css | sha384(base64=true) }}`는 그대로 SRI(Subresource Integrity) 값이 됩니다(디스크의 파일이라면 [`asset_integrity()`](/ko/templates/functions/)가 이 일을 대신합니다). `base64_decode`는 입력이 올바른 base64가 아니거나 디코딩한 바이트가 UTF-8 텍스트가 아니면 템플릿 오류로 빌드를 멈춥니다.

## HTML 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| safe | HTML을 이스케이프하지 않음 | {{ content \| safe }} |
| strip_html | HTML 태그 제거 | {{ html \| strip_html }} |
| markdownify | 마크다운 렌더링 | {{ text \| markdownify }} |
| xml_escape | XML 이스케이프 | {{ text \| xml_escape }} |

`markdownify`는 사이트의 [`[markdown]`](/ko/features/markdown-extensions/)
설정 중 safe 모드와 `smart_punctuation`을 따르므로, 같은 텍스트가 페이지
본문에서 렌더링되는 결과와 일치합니다. 나머지 확장 파이프라인(각주, 정의
목록, 컨테이너 등)은 적용되지 않습니다.

## 배열 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| length | 길이 | {{ items \| length }} |
| first | 첫 요소(빈 컬렉션이면 빈 값) | {{ items \| first }} |
| last | 마지막 요소(빈 컬렉션이면 빈 값) | {{ items \| last }} |
| reverse | 순서 뒤집기 | {{ items \| reverse }} |
| sort | 배열 정렬 | {{ items \| sort }} |
| min | 가장 작은 요소. `attribute=`로 필드 기준 비교 | {{ posts \| min(attribute="date") }} |
| max | 가장 큰 요소. `attribute=`로 필드 기준 비교 | {{ [3, 7, 5] \| max }} → 7 |
| join | 요소 이어 붙이기 | {{ tags \| join(", ") }} |
| split | 문자열 분할 | {{ "a,b,c" \| split(pat=",") }} |
| where | 필드 값으로 객체 필터링 | {{ posts \| where(attribute="draft", value=false) }} |
| sort_by | 필드로 객체 정렬 | {{ posts \| sort_by(attribute="date", reverse=true) }} |
| group_by | 필드로 객체 그룹화 | {{ posts \| group_by(attribute="section") }} |

`min`과 `max`는 Jinja2와 같이 동작합니다. 비교 방식은 `sort`와 같고(`case_sensitive=true`를 주지 않으면 문자열은 대소문자를 구분하지 않음), `attribute=`에는 `"extra.weight"` 같은 점 경로를 쓸 수 있으며 요소 전체를 돌려줍니다. 값이 같으면 앞의 요소가 선택되고, 빈 리스트는 정의되지 않은 값을 돌려줍니다.

## 컬렉션 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| unique | 서로 다른 값의 타입은 구분해 중복 제거 | {{ items \| unique }} |
| flatten | 중첩 배열을 한 단계 평탄화 | {{ nested \| flatten }} |
| compact | nil/빈 값 제거 | {{ items \| compact }} |

## 수학 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| ceil | 올림하여 정수로 | {{ 3.2 \| ceil }} → 4 |
| floor | 내림하여 정수로 | {{ 3.8 \| floor }} → 3 |
| num_format | 세 자리마다 구분 기호 넣기([숫자 포맷](#숫자-포맷) 참고) | {{ 1234567 \| num_format }} → 1,234,567 |

## i18n 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| t | 키 번역 | {{ "nav.home" \| t }} |
| pluralize | 단수/복수형 선택 | {{ count \| pluralize(singular="item", plural="items") }} |

`t` 필터는 `i18n/` 디렉터리의 TOML 파일에서 번역 키를 찾습니다. 현재 페이지의 언어를 먼저 보고 기본 언어로 폴백하며, 번역이 없으면 키 자체를 반환합니다. i18n 파일 구성은 [다국어](/ko/features/multilingual/)를 참고합니다.

## 디버그 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| inspect | 디버그용 표현 | {{ value \| inspect }} |

## URL 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| absolute_url | base를 포함한 전체 URL | {{ "/about/" \| absolute_url }} |
| relative_url | base_url의 경로 부분(스킴과 호스트 제외)을 접두사로 추가 | {{ "/img.png" \| relative_url }} |
| active_path | 이 URL이 현재 페이지(또는 그 상위)인지 | {{ item.url \| active_path }} |

`active_path`는 URL(보통 [메뉴](/ko/features/menus/) 엔트리의 `item.url`)을 현재 페이지와 비교합니다. 기본은 정확히 일치할 때만 참이고, `ancestor=true`를 넘기면 하위 페이지도 매칭합니다.

```jinja
<a href="{{ item.href }}"{% if item.url | active_path %} aria-current="page"{% endif %}>{{ item.name }}</a>
<a href="{{ item.href }}"{% if item.url | active_path(ancestor=true) %} class="open"{% endif %}>{{ item.name }}</a>
```

비교 전에 양쪽 모두 끝 슬래시 하나로 정규화되므로 `/posts`와 `/posts/`는 같습니다. 루트 경로(`/`)는 `ancestor=true`여도 정확히 일치할 때만 매칭됩니다. 외부 `item.url`(`http://`, `https://`, `//`)은 절대 매칭되지 않으며, `url` 없이 적은 엔트리(그룹 제목)의 빈 `url`도 마찬가지입니다.

## 데이터 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| default | 정의되지 않았거나 none이거나 빈 값일 때의 폴백 값([기본값](#기본값) 참고) | {{ value \| default(value="N/A") }} |
| jsonify | JSON 인코딩 | {{ data \| jsonify }} |
| tojson | JSON 인코딩. `indent`를 주면 그만큼의 공백(0–16)으로 들여쓰기 | {{ data \| tojson(indent=2) }} |
| date | 날짜 포맷(기본 포맷 `%Y-%m-%d`) | {{ page.date \| date("%Y-%m-%d") }} |

## 예시

### safe 필터

렌더링된 콘텐츠에는 항상 `safe`를 사용합니다.

```jinja
{{ content | safe }}
{{ og_tags | safe }}
{{ toc | safe }}
```

### 기본값

```jinja
{{ page.description | default(value=site.description) }}
{{ page.image | default(value="/images/default.png") }}
```

`default`는 값이 정의되지 않았거나 `none`이거나 빈 문자열일 때 폴백 값을 반환합니다. 폴백 값은 원래 타입을 유지하므로 `default(value=0)`의 결과로 산술 연산을 할 수 있으며, `none` 폴백(`default(value=none)`)은 빈 문자열로 렌더링됩니다. 값이 비어 있지 않으면 배열, 맵, 객체는 그대로 반환하고, 그 밖의 값(문자열, 숫자, 불리언)은 문자열로 반환하므로 뒤에 `length`나 `replace` 같은 문자열 필터를 이어서 쓸 수 있습니다. `boolean=true`를 함께 넘기면(`default(value="N/A", boolean=true)`) `false`, `0`, 빈 리스트나 맵처럼 거짓으로 평가되는 값도 폴백 값으로 바꿉니다.

### 날짜 포맷

```jinja
<time>{{ page.date | date("%B %d, %Y") }}</time>
```

포맷 코드:
- `%Y` — 연도(2024)
- `%m` — 월(01-12)
- `%d` — 일(01-31)
- `%B` — 월 이름(January)
- `%b` — 월 축약형(Jan)

### URL 처리

```jinja
<a href="{{ page.url | absolute_url }}">Permalink</a>
<img src="{{ "/logo.png" | relative_url }}">
```

### 문자열과 체이닝

```jinja
{{ page.title | lower | slugify }}
{{ content | strip_html | truncate_words(100) }}
{{ description | default(value="No description") | upper }}

{% set tags = "a,b,c" | split(pat=",") %}
{% for tag in tags %}
  <span>{{ tag | trim }}</span>
{% endfor %}
```

### 정규 표현식

`regex_replace`는 Zola와 같은 인자 이름 `pattern`과 `rep`를 받습니다(두 값을 순서대로 넘겨도 됩니다). `rep`의 기본값은 `""`이라 생략하면 맞는 부분을 지웁니다. 패턴은 PCRE2 문법입니다. 치환 문자열은 Crystal이 아니라 Zola와 Hugo(Rust/Go 정규식)의 문법을 따릅니다.

- `$1`이나 `${1}`은 번호 그룹, `$name`이나 `${name}`은 이름 있는 그룹(`(?<name>…)`), `$$`는 `$` 문자 자체를 넣습니다.
- `$name`은 영문자, 숫자, `_`가 이어지는 가장 긴 부분을 이름으로 보므로 `$1a`는 `1a`라는 그룹을 뜻합니다. 그룹 1 뒤에 `a`를 붙이려면 `${1}a`로 씁니다.
- 없는 그룹이나 매치에 참여하지 않은 그룹은 빈 문자열이 됩니다. 뒤에 이름이 없는 `$`는 그대로 남고, 백슬래시는 평범한 문자입니다(`\1`은 그룹 참조가 아닙니다).

```jinja
{{ "2024-03-05" | regex_replace(pattern="(\d+)-(\d+)-(\d+)", rep="$3/$2/$1") }}  {# 05/03/2024 #}
{{ "John Smith" | regex_replace(pattern="(?<first>\w+) (?<last>\w+)", rep="$last, $first") }}
{{ page.title | regex_replace("\s+", " ") }}
```

패턴이 잘못되었거나 백트래킹이 PCRE2의 매치 한도를 넘으면, 패턴을 알려 주는 템플릿 오류로 빌드가 멈춥니다.

### 숫자 포맷

`num_format`은 숫자(또는 일반 십진수가 담긴 문자열)의 정수 부분을 세 자리씩 묶습니다. 선택 인자는 세 가지입니다: `decimals`(고정 소수 자릿수, 0–20, 반올림은 0에서 먼 쪽으로. 지정하지 않으면 숫자의 원래 소수 자릿수 유지), `separator`(기본 `,`), `decimal_point`(기본 `.`).

```jinja
{{ 1234567 | num_format }}                                    {# 1,234,567 #}
{{ 1234.5 | num_format(decimals=2) }}                         {# 1,234.50 #}
{{ 1234567.5 | num_format(separator=".", decimal_point=",") }} {# 1.234.567,5 #}
{{ 1234567 | num_format(separator=" ") }}                     {# 1 234 567 #}
```

숫자가 아닌 값(텍스트, `true`, 정의되지 않은 값, NaN)은 그대로 돌려주므로, 프런트 매터 필드가 없어도 페이지가 깨지지 않습니다.

### 컬렉션 질의

```jinja
{% set published = site.pages | where(attribute="draft", value=false) %}
{% set newest = published | sort_by(attribute="date", reverse=true) %}

{% for group in newest | group_by(attribute="section") %}
  <h3>{{ group.grouper }}</h3>
  <ul>
  {% for p in group.list %}
    <li><a href="{{ p.url }}">{{ p.title }}</a></li>
  {% endfor %}
  </ul>
{% endfor %}

{# Unique tags across all pages #}
{% set all_tags = site.pages | map(attribute="tags") | flatten | unique %}
```

### 번역

```jinja
{# Translate UI strings (requires i18n/*.toml files) #}
<nav>
  <a href="/">{{ "nav.home" | t }}</a>
  <a href="/blog/">{{ "nav.blog" | t }}</a>
</nav>

{# Pluralize based on count #}
<p>{{ post_count }} {{ post_count | pluralize(singular="post", plural="posts") }}</p>
```

---

## 테스트

테스트는 `{% if %}` 문에서 조건을 평가합니다.

| 테스트 | 설명 | 예시 |
|------|-------------|---------|
| startswith | ~로 시작 | `{% if page.url is startswith("/blog/") %}` |
| endswith | ~로 끝남 | `{% if page.url is endswith("/") %}` |
| containing | 부분 문자열(문자열) 또는 요소(리스트) 포함 | `{% if page.url is containing("docs") %}` |
| matching | 정규식 일치 | `{% if asset is matching("[.](jpg\|png)$") %}` |
| empty | 비어 있음 | `{% if page.description is empty %}` |
| present | 비어 있지 않음 | `{% if page.title is present %}` |
| eq, ne, lt, le, gt, ge | 값과 비교(`==`, `!=`, `<`, `<=`, `>`, `>=`, `equalto`, `lessthan`, `greaterthan`도 사용 가능) | `{{ posts \| selectattr("extra.year", ">=", 2020) \| list }}` |

### 테스트 예시

```jinja
{% if page.url is startswith("/blog/") %}
<span class="badge">Blog</span>
{% endif %}

{% if page.description is empty %}
<meta name="description" content="{{ site.description }}">
{% endif %}

{% if page.image is present %}
<meta property="og:image" content="{{ page.image | absolute_url }}">
{% endif %}

{% if "hero.jpg" is matching("[.](jpg|png)$") %}
<span>Image file</span>
{% endif %}
```

### 내장 테스트

```jinja
{% if value is defined %}
{% if value is none %}
{% if value is number %}
{% if value is string %}
{% if value is iterable %}
{% if value is even %}
{% if value is odd %}
```

---

## 함께 보기

- [데이터 모델](/ko/templates/data-model/) — 사용할 수 있는 변수
- [함수](/ko/templates/functions/) — 템플릿 함수
- [문법](/ko/templates/syntax/) — 템플릿 기본
