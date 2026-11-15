+++
title = "1.0으로 업그레이드"
description = "Hwaro 0.22로 만든 사이트에서 달라지는 점과 내 사이트를 확인하는 방법"
weight = 6
toc = true
+++

이 페이지는 0.22에서 1.0으로 옮길 때 사이트 운영자가 실제로 보게 되는 변화를 정리합니다. `hwaro init`으로 만든 뒤 템플릿을 고치지 않은 사이트는 출력이 그대로입니다. 아래 항목은 템플릿을 직접 작성했거나, 스크립트에서 hwaro를 호출하거나, 여기에 적힌 동작에 기대고 있을 때 해당됩니다.

## 내 사이트 확인하기

1. **업그레이드하기 전에** 0.22로 빌드해 보관할 디렉터리에 둡니다: `hwaro build -o /tmp/site-0.22`
2. 업그레이드한 뒤 `hwaro doctor`를 실행합니다. `hwaro doctor --fix`는 남아 있는 `[plugins]` 섹션을 지워 줍니다.
3. 1.0으로 빌드하고 경고를 읽습니다: `hwaro build -o /tmp/site-1.0`
4. 둘을 비교합니다: `diff -r /tmp/site-0.22 /tmp/site-1.0`. 차이는 모두 이 페이지의 항목 중 하나여야 합니다.

템플릿 이스케이프로 달라지는 부분만 보려면 [0.x에서 옮겨 올 때](/ko/templates/syntax/#0x에서-옮겨-올-때)를 따르세요.

## 조치가 필요한 변경

### 템플릿이 기본으로 이스케이프합니다

출력이 HTML이나 XML인 템플릿은 이제 Jinja2처럼 안전(safe) 값이 아닌 모든 출력 값을 이스케이프합니다. 템플릿이 그대로 출력하던 텍스트(`&`, `<`, 따옴표가 든 `{{ page.title }}`)는 이스케이프되며, 이것은 원래 필요했던 동작입니다. 반면 마크업으로 출력하던 작성자 HTML은 이제 텍스트로 보입니다.

```jinja
{{ page.extra.banner }}          {# 0.22: 마크업    1.0: &lt;b&gt;…&lt;/b&gt; #}
{{ page.extra.banner | safe }}   {# 둘 다 마크업 #}
```

실제로 가장 흔한 경우는 태그가 든 번역 문자열이나 데이터 값을 `t`로 출력하는 곳입니다.

```toml
# i18n/ko.toml
lede = "모든 요청은 <b>플로우</b>가 됩니다."
```

```jinja
<p>{{ "home.lede" | t }}</p>          {# 1.0: <b>가 텍스트로 보입니다 #}
<p>{{ "home.lede" | t | safe }}</p>   {# 0.22와 1.0 모두 마크업 #}
```

`| safe`를 붙여도 0.22의 출력은 달라지지 않으므로, 업그레이드하기 전에 미리 고쳐 둘 수 있습니다.

Hwaro가 HTML로 렌더링한 값(`content`, `page.summary`, `toc`, `*_tags` 변수, 페이지네이션)은 전과 같이 출력되고, 이 값들에 붙인 `| e`는 계속 이스케이프합니다. 그래서 피드 템플릿의 `{{ p.summary | escape | xml_escape }}`는 그대로 동작합니다. JSON, 텍스트, CSV 출력은 달라지지 않습니다.

사이트 전체를 0.22 동작으로 두려면 다음과 같이 씁니다.

```toml
[templates]
autoescape = false
```

이 설정에서는 0.22와 바이트 단위로 똑같이 렌더링됩니다. 규칙과, 기본값이 내 사이트에서 바꾸는 곳을 모두 찾아내는 방법은 [HTML 이스케이프](/ko/templates/syntax/#html-이스케이프)를 참고하세요.

### `[plugins]`가 제거되었습니다

이 섹션은 읽기만 하고 쓰인 적이 없으며, 이전 `hwaro init`이 만든 모든 `config.toml`에 들어 있습니다. 이제 모든 명령이 다음을 출력합니다.

```
Key 'plugins' in config.toml was removed in 1.0 — hwaro does not read it; delete the [plugins] section to silence this warning.
```

섹션을 지우거나 `hwaro doctor --fix`를 실행하세요.

### 제거된 명령과 플래그

이들을 호출하는 스크립트와 CI 작업은 이제 종료 코드 2로 멈춥니다.

| 0.22 | 1.0 | 대신 쓸 것 |
|---|---|---|
| `hwaro tool ci github-actions` | `unknown command 'tool ci'` | `hwaro tool platform github-pages` (같은 워크플로 파일을 씁니다) |
| `hwaro tool doctor` | `unknown command 'tool doctor'` | `hwaro doctor` (플래그 동일) |
| `hwaro serve --live-reload` | `Invalid option: --live-reload` | 플래그를 빼세요. 라이브 리로드는 기본으로 켜져 있고 `--no-live-reload`로 끕니다. |

셸 자동 완성은 `hwaro completion <shell>`로 다시 생성하세요.

### `hwaro serve`에는 `config.toml`이 필요합니다

없으면 경고만 하고 기본값으로 서빙하던 것이, 이제 `hwaro build`처럼 `config.toml not found`와 종료 코드 3으로 멈춥니다. 프로젝트 디렉터리에서 실행하거나 `-i DIR`을 넘기세요.

### 터널이나 리버스 프록시 뒤의 `hwaro serve`

개발 서버는 알아보는 `Host` 이름에만 응답합니다. 루프백 주소, 머신 이름, 바인드 주소, `base_url`의 호스트가 그 대상이고, 그 밖의 이름에는 `403`을 돌려줍니다. 터널이나 프록시가 쓰는 이름은 `--allow-host NAME`으로 넘기거나 `[serve]` 아래 `allowed_hosts`에 적으세요. [CLI](/ko/start/cli/)를 참고하세요.

### 인자 뒤에 연산자가 오는 템플릿 테스트

괄호 없이 쓴 테스트 인자는 Jinja2처럼 값 하나로 읽습니다.

```jinja
{% if page.url is startswith "/blog" ~ "/" %}    {# 이제: (page.url is startswith "/blog") ~ "/" — 항상 참 #}
{% if page.url is startswith("/blog" ~ "/") %}   {# 원래 의도 #}
```

빌드는 이런 곳마다 경고하고, 써야 할 괄호 형태를 알려 줍니다. 출력을 대신 바꿔 주지는 않습니다.

### `{% include … without context %}`가 남기던 변수

`without context`로 포함한 부분 템플릿의 최상위 `{% set %}`이나 `{% macro %}`는 포함한 템플릿에서도, 같은 워커가 이후에 빌드하는 페이지에서도 보였습니다. 그래서 같은 소스가 실행할 때마다 다르게 빌드될 수 있었습니다. 이제는 다른 인클루드와 마찬가지로 부분 템플릿과 함께 끝납니다. 그런 변수를 읽던 템플릿은 정의되지 않은 값을 받게 되므로, 변수와 매크로는 `{% import %}`나 `{% from %}`으로 공유하세요.

### 분해형(NFD)으로 저장된 파일 이름

페이지 URL과 출력 파일 이름은 파일 시스템이 어떤 형태로 저장했든 이제 조합형(NFC)입니다. 일부 macOS 도구가 만든 이름은 분해형으로 저장되며, 한글 이름과 악센트가 붙은 이름이 특히 해당됩니다. 그런 사이트를 분해형 URL로 배포해 왔다면 1.0으로 빌드한 뒤에는 그 URL이 없어집니다. 예전 표기를 페이지의 [`aliases`](/ko/writing/pages/#url-별칭)에 추가하거나(적은 그대로 유지됩니다) 서버에서 리다이렉트하세요.

### `include_code`와 `include_md`

`.git/` 아래 파일과 dotenv 파일(`.env`, `.env.*`. 단 `.env.example`, `.env.sample`, `.env.template`은 예외)을 거부합니다. 이런 파일을 포함하던 페이지는 이제 빌드가 실패합니다.

### 스크립트에서 쓰는 `hwaro tool unused-assets --delete`

대화형 터미널이 아니면 `--force`가 필요합니다. 파이프로 넘긴 `y`는 더 이상 받지 않습니다.

### 날짜

문서에 적힌 형식(`YYYY-MM-DD`, `YYYY-MM-DD HH:MM:SS`, RFC 3339)을 벗어난 `date`, 예를 들어 두 자리 연도나 ±23:59를 넘는 오프셋은 "not a recognised date" 경고를 받고 날짜가 없는 페이지로 처리됩니다. 이 중 일부는 전에 조용히 읽혔습니다. 적어 둔 UTC 오프셋은 항상 그대로 반영됩니다.

## 눈에 띌 수 있는 출력 변화

- **리다이렉트 스텁이 목록에서 빠집니다.** `redirect_to`가 있는 페이지는 섹션 목록, 택소노미 페이지, 페이지네이션 개수, 이전/다음 링크에 더 이상 나오지 않으므로 뒤따르던 페이지가 한 칸 앞으로 옵니다.
- **RSS 항목의 description.** 일반 텍스트 설명의 `&`, `<`, `>`를 XML 이스케이프 전에 HTML 이스케이프합니다(`R&D`가 `R&amp;amp;D`가 됩니다). 피드 리더가 이 요소를 HTML로 렌더링하기 때문입니다.
- **하위 경로에서 서빙하는 사이트**(`base_url = "https://example.com/docs"`)에 그 경로와 같은 이름의 섹션이나 static 폴더가 있는 경우: `content/docs/p.md`를 가리키며 `/docs/p/`로 쓴 링크는 이제 페이지가 실제로 게시되는 주소인 `/docs/docs/p/`가 됩니다. 이런 사이트는 링크를 확인하세요.
- **언어 홈 페이지가 없는 언어 피드**는 빌드된 적 없는 URL 대신 사이트 루트로 링크합니다.
- **메뉴.** `active_path(ancestor=true)`는 언어의 홈 항목을 그 언어의 모든 페이지가 아니라 홈 페이지에서만 열린 것으로 표시합니다.
- **렌더 훅.** `templates/hooks/render-*.html` 안에서 `absolute_url`과 `get_url`이 `base_url`을 붙인 전체 URL을 돌려줍니다.
- **파이프 표**는 GFM을 따릅니다. 헤더 열 수를 넘는 셀은 버립니다.
- **이미지.** 애니메이션 PNG는 리사이즈하지 않고 그대로 게시합니다. 이미지는 확장자가 아니라 내용으로 식별하며, 있을 수 없는 크기를 주장하는 파일은 빌드를 멈추는 대신 건너뜁니다.
- **수식, Mermaid, 클라이언트 측 하이라이트 태그**는 정확한 버전을 참조하고 `integrity`와 `crossorigin`을 답니다.
- **코드 블록**은 언어 하이라이터가 인식하지 못하는 비ASCII 문자(`→`, `✓`, 결합 악센트)를 `���`로 출력하지 않고 그대로 둡니다.
- **macOS 배포 바이너리의 Python, C++ 등 코드 블록.** 독스트링은 독스트링으로 칠하고 C++ raw 문자열은 `R` 접두사까지 문자열로 칠합니다. 더 새로운 PCRE2로 링크한 빌드는 이미 그랬습니다. Python, Python 2, C++, Arduino, GDScript 3, Hy, Mojo 블록의 클래스가 바뀔 수 있습니다.
- **페이지 URL**은 `<`와 `>`를 퍼센트 인코딩합니다.
- **`truncate`, 발췌, 요약**은 글자 중간(자모로 쓴 한글, 결합 문자, 이모지 시퀀스)에서 자르지 않으므로, 자르는 위치가 한 글자 앞일 수 있습니다.
- **URL이 50,000개를 넘는 사이트맵**은 사이트맵 인덱스 아래 `sitemap-1.xml`, `sitemap-2.xml`, …으로 나뉩니다.
- **서비스 워커(`[pwa]`).** GET이 아닌 요청은 무시하며, 캐시 이름이 바뀌어 방문자의 캐시가 한 번 새로 고쳐집니다.
- **blog 스캐폴드.** 날짜 없는 글이 빈 `<time>`을 출력하지 않고, 태그 페이지 링크에 텍스트가 들어갑니다. 이전 `hwaro init`이 복사해 둔 템플릿은 여러분의 파일이므로 원래 마크업을 유지합니다.
- **`urlize`**는 `javascript:`, `vbscript:`, `file:`, 이미지가 아닌 `data:` URL을 링크로 만들지 않습니다.
- **Jinja2와 같게 동작하게 된 필터와 함수:** `default(default_value="x")`, `unique(case_sensitive=true)`, `trim("x")`, 문자열 인덱싱(`"héllo"[1]`), 정의되지 않은 값에 대한 `join`/`reverse`/`list`/`batch`/`slice`/`replace`(빌드 실패 대신 빈 값), 숫자에 대한 `replace`, `{# {{ x }} #}` 주석.

## 새 경고와 오류

- `+++`로 열고 닫지 않은 TOML 프론트 매터 블록을 알려 줍니다. 이런 파일은 원래도 본문 텍스트로 게시되었습니다.
- 필터나 함수의 키워드 인자를 잘못 쓰면(`get_page(pth=…)`) 빌드당 한 번 알리고 무시합니다.
- 프론트 매터 오류가 파일 안의 줄 번호를 알려 줍니다.
- 읽을 수 없는 `templates/` 디렉터리나 페이지에 필요한 템플릿 파일은 빌드를 실패시킵니다. 읽을 수 없는 `content/`, `static/`, `data/` 디렉터리는 경고를 냅니다.
- 알 수 없는 명령줄 플래그는 `Invalid option: --x`와 함께 `--help` 안내를 출력합니다.
- `hwaro doctor`는 자체 템플릿이 있으면서 `[templates] autoescape`를 설정하지 않은 사이트를 알려 줍니다.

## 스크립트와 CI

- `-q` / `--quiet`가 명령의 답을 더 이상 숨기지 않습니다. `tool list`, `tool stats`, `tool unused-assets`, `init --list-scaffolds`, `new --list-archetypes`, `deploy --list-targets`와 모든 `--help`가 결과를 출력합니다.
- 사용법 오류와 함께 보여 주는 사용법 텍스트는 stderr로 나가고 stdout은 비어 있습니다. 종료 코드는 여전히 2입니다.
- `.hwaro_cache.json`은 상대 경로를 저장합니다. `--cache`를 쓴 첫 1.0 빌드는 이전 캐시를 무시하고 한 번 전체를 다시 빌드합니다.
- `hwaro tool import`: WordPress는 예전 퍼머링크를 `aliases`에 남기고 제목과 요약의 HTML 엔티티를 디코드합니다. Notion은 Created, Date, Tags를 프론트 매터로 읽습니다. Hexo, Astro, Eleventy, Jekyll은 매핑되지 않은 프론트 매터 키를 `[extra]` 아래에 보존합니다.
