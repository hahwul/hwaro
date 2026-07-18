+++
title = "구문 강조"
description = "코드 블록 자동 구문 강조"
weight = 7
+++

마크다운의 코드 블록은 자동으로 구문 강조됩니다.

## 사용법

언어 식별자를 붙인 펜스 코드 블록을 사용합니다.

````markdown
```javascript
function greet(name) {
  console.log(`Hello, ${name}!`);
}
```
````

## 지원 언어

자주 쓰는 언어:

| 언어 | 식별자 |
|----------|-------------|
| JavaScript | javascript, js |
| TypeScript | typescript, ts |
| Python | python, py |
| Ruby | ruby, rb |
| Go | go, golang |
| Rust | rust, rs |
| Crystal | crystal, cr |
| HTML | html |
| CSS | css |
| JSON | json |
| YAML | yaml, yml |
| TOML | toml |
| Markdown | markdown, md |
| Shell | bash, sh, shell |
| SQL | sql |

## 설정

`config.toml`에서 설정합니다.

```toml
[highlight]
enabled = true
theme = "github-dark"
use_cdn = true
mode = "server"
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| enabled | bool | true | 구문 강조 활성화 |
| theme | string | "github" | Highlight.js 테마 이름 |
| use_cdn | bool | true | 에셋을 CDN에서 로드(false = 로컬 파일) |
| mode | string | "server" | `"server"`는 빌드 시점에 강조, `"client"`는 브라우저에서 Highlight.js로 강조 |
| line_numbers | bool | false | 모든 펜스 코드 블록에 기본으로 줄 번호 추가(아래 참고) |
| copy | bool | false | 펜스 코드 블록에 클립보드 복사 버튼 추가(아래 참고) |

## 서버 사이드 강조(기본값)

`mode = "server"`(기본값)에서는 빌드 중에 코드 블록이 강조됩니다 — 브라우저로 JavaScript가 전송되지 않고, JavaScript를 꺼 놓아도 코드에 색이 입혀집니다.

빌드 시점 하이라이터는 Highlight.js 호환 CSS 클래스를 출력하므로, 아래의 모든 테마가 그대로 동작합니다. `{{ highlight_css }}`는 여전히 테마 스타일시트를 주입하고, `{{ highlight_js }}`는 빈 값이 됩니다.

250개가 넘는 언어를 지원합니다(Pygments/Chroma에서 포팅된 [Tartrazine](https://github.com/ralsina/tartrazine) 렉서 사용). 렉서가 없는 언어의 코드 블록은 강조 없는 일반 출력으로 대체됩니다.

## 클라이언트 사이드 강조

`mode = "client"`로 설정하면 대신 브라우저에서 Highlight.js로 강조합니다.

```toml
[highlight]
mode = "client"
theme = "github-dark"
```

클라이언트 모드에서는 `{{ highlight_js }}`가 Highlight.js 스크립트를 주입하고(CDN 또는 로컬 에셋에서 — 아래 참고), 코드 블록은 브라우저가 색을 입힐 수 있도록 일반 `<pre><code class="language-...">` 마크업으로 출력됩니다.

## 줄 번호와 줄 강조

펜스 코드 블록의 언어 뒤에 옵션 블록 `{...}`을 붙여 줄 번호를 넣거나 특정 줄을 강조할 수 있습니다.

````markdown
```python {linenos=true, hl_lines="2-4 7", linenostart=5}
def main():
    setup()
    run()
    teardown()
    return 0
```
````

| 옵션 | 값 | 설명 |
|--------|-------|--------------|
| `linenos` | `true` / `false` | 줄 번호 거터 표시. 이 블록에 한해 `[highlight] line_numbers` 기본값을 덮어씀 |
| `hl_lines` | 예: `"2-4 7"` | 지정한 줄을 강조 — 공백/쉼표로 구분한 줄 번호나 범위. 항상 블록 자체의 **물리적** 1-기반 줄 번호이며 `linenostart`의 영향을 받지 않음 |
| `linenostart` | 예: `5` | 표시되는 첫 줄 번호(기본 `1`). 화면에 보이는 번호만 바꿀 뿐, `hl_lines`가 강조하는 물리적 줄은 바뀌지 않음 |
| `hide_lines` | 예: `"1 9-12"` | 지정한 줄을 렌더링 출력에서 제외(서버 모드 전용 — 아래 참고). 문법과 물리적 줄 의미는 `hl_lines`와 동일 |
| `copy` | `true` / `false` | 이 블록에 복사 버튼 표시. `[highlight] copy` 기본값을 덮어씀. `mermaid` 펜스에서는 무시됨 |
| `name` | 예: `"main.cr"` | 블록 위에 렌더링되는 파일명/제목 라벨(`title=`도 별칭으로 허용). `mermaid` 펜스에서는 무시됨 |

이름이 붙은 블록은 스타일링을 위해 래핑됩니다(내부의 `<pre>`는 그대로).

```html
<div class="code-block"><div class="code-filename">main.cr</div>
<pre><code class="language-crystal hljs">…</code></pre>
</div>
```

스캐폴드로 만든 사이트에는 이에 맞는 `.code-block` / `.code-filename` 스타일이 포함되어 있습니다. 그 외에는 직접 CSS를 준비해야 합니다.

옵션 블록은 몇 가지 동등한 형태를 허용합니다. `python {linenos=true}`, `python{linenos=true}`(공백 없음), 언어 없이 `{linenos=true}`만 쓰는 형태 모두 가능합니다. 형식이 잘못됐거나 인식할 수 없는 옵션 블록(예: `{oops}`)은 펜스 옵션이 없는 것처럼 언어 토큰의 리터럴 텍스트로 남습니다.

`[highlight] line_numbers = true`를 설정하면 언어가 지정된 *모든* 펜스 코드 블록에 줄 번호가 켜집니다. 블록별 `{linenos=false}`로 다시 끌 수 있습니다.

숨긴 줄도 물리적 줄 번호는 그대로 차지하므로, `linenos=true`일 때 거터에는 줄이 생략된 자리에 **번호 공백**이 생깁니다. 남은 줄의 번호를 다시 매기는 Zola와는 다른 동작입니다. 덕분에 `hl_lines`와 `linenostart`가 숨김 여부와 무관하게 항상 블록의 물리적 줄을 가리킨다는 문서화된 불변 조건이 유지됩니다(숨긴 줄을 강조하는 것은 그저 아무 효과가 없을 뿐입니다).

숨긴 줄을 HTML에서 실제로 제거하는 것은 `mode = "server"`뿐입니다. 클라이언트 모드의 `hide_lines`는 표시용 메타데이터(비활성 `data-hide-lines` 속성)일 뿐이며, 해당 줄은 페이지 소스에 그대로 남습니다. 클라이언트 모드에서 비밀 값을 가리는 용도로 `hide_lines`를 사용하면 **안 됩니다**.

**서버 모드와 클라이언트 모드:**

- `mode = "server"`(기본값)는 빌드 시점에 결과를 완전히 렌더링합니다. 각 줄이 자체 요소로 래핑되므로 줄 번호와 줄 강조가 JavaScript 없이 표시됩니다.
- `mode = "client"`는 본문을 다시 렌더링하지 않습니다. 대신 `<pre>` 태그에 `data-linenos="true"`, `data-linenostart="N"`(1보다 클 때), `data-hl-lines="2-4 7"`, `data-hide-lines="1 9-12"` 속성이 붙어서 클라이언트 스크립트나 커스텀 CSS가 이를 활용할 수 있습니다. Hwaro는 클라이언트 모드용 스크립트를 제공하지 않습니다. 완전한 렌더링(과 실제 줄 숨김)에는 `mode = "server"`가 필요합니다.

스캐폴드 사이트는 서버 모드 마크업 스타일을 기본으로 제공합니다. 스캐폴드가 아닌 사이트나 커스텀 테마에서는 다음을 추가합니다.

```css
pre code .line.hl { display: inline-block; width: 100%; background: color-mix(in srgb, var(--code-keyword) 12%, transparent); }
pre code .ln { user-select: none; -webkit-user-select: none; opacity: .45; }
```

(Hwaro Ember 토큰 시스템을 쓰지 않는다면 `var(--code-keyword)`를 테마에 맞는 아무 색으로 바꾸면 됩니다.)

## 복사 버튼

`[highlight] copy = true`는 모든 펜스 코드 블록에 클립보드 복사 버튼을 추가합니다. 펜스별 `{copy=false}`(또는 전역 기본값이 꺼진 상태의 `{copy=true}`)가 이를 덮어씁니다.

```toml
[highlight]
copy = true
```

마크업 계약은 이렇습니다. 옵트인한 각 블록의 `<pre>`에 `data-copy="true"` 속성이 붙고, `{{ highlight_js }}`가 의존성 없는 작은 인라인 런타임을 주입합니다(서버·클라이언트 모드 모두 동작). `copy = true`이면 런타임이 사이트 전체에 포함되고, 전역 기본값이 꺼져 있으면 옵트인 블록이 본문에 있는 페이지에만 해당 페이지의 `{{ highlight_js }}`에 덧붙습니다 — 없는 페이지는 JavaScript가 없는 상태를 유지합니다. 런타임은 각 `pre[data-copy]`를 `<div class="code-wrapper">`로 감싸고(이름 붙은 펜스처럼 기존 `.code-block` 래퍼가 있으면 그것을 앵커로 재사용), `<button class="code-copy-btn">`을 덧붙인 뒤, 클릭 시 코드 텍스트를 복사합니다(서버 모드의 `.ln` 줄 번호 거터는 복사되는 텍스트에서 제거됩니다). 인라인 스타일은 테마 중립적(currentColor, 호버 시 표시)이며, 스캐폴드 사이트는 토큰 기반 스타일로 이를 덮어씁니다.

`mermaid` 펜스에는 이 속성이 절대 붙지 않습니다 — 그 `<pre>` 구조는 Mermaid 파이프라인이 소유합니다.

새로 스캐폴드한 사이트는 `copy = true`가 기본으로 켜져 있습니다.

## 테마

Hwaro는 [Highlight.js](https://highlightjs.org/) 테마를 사용합니다. 유효한 Highlight.js 테마 이름이면 무엇이든 동작합니다. 많이 쓰는 테마:

- `github` — 밝은 GitHub 스타일(기본값)
- `github-dark` — 어두운 GitHub 스타일
- `github-dark-dimmed` — 톤을 낮춘 어두운 GitHub 스타일
- `monokai` — 클래식 다크 테마
- `dracula` — 어두운 보라색 테마
- `solarized-dark` — Solarized 다크
- `solarized-light` — Solarized 라이트
- `nord` — 북극 색 팔레트
- `tokyo-night-dark` — Tokyo Night 다크

전체 테마 목록은 [highlightjs.org/demo](https://highlightjs.org/demo)에서 볼 수 있습니다.

## CDN과 로컬

`use_cdn = true`(기본값)이면 에셋을 cdnjs에서 로드합니다.

```html
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
```

`use_cdn = false`이면 로컬 경로에서 로드합니다.

```html
<link rel="stylesheet" href="/assets/css/highlight/github-dark.min.css">
<script src="/assets/js/highlight.min.js"></script>
```

`use_cdn = false`를 쓸 때는 로컬 파일을 직접 준비해야 합니다. 기본값인 서버 모드에서는 테마 스타일시트만 참조됩니다 — 위의 `<script>` 태그는 `mode = "client"`일 때만 나타납니다.

## 템플릿 연동

템플릿에 강조 에셋을 포함합니다.

```jinja
<head>
  {{ highlight_css | safe }}
</head>
<body>
  ...
  {{ highlight_js | safe }}
</body>
```

또는 한 번에:

```jinja
<head>
  {{ highlight_tags | safe }}
</head>
```

## 빌드 옵션

빌드 속도를 높이려면 강조를 비활성화합니다.

```bash
hwaro build --skip-highlighting
```

## 일반 텍스트 블록

강조하지 않으려면 언어를 생략하거나 `text`를 사용합니다.

````markdown
```text
Plain text content
No highlighting applied
```
````

## 인라인 코드

인라인 코드는 백틱을 사용하며 강조되지 않습니다.

```markdown
Use the `console.log()` function.
```

## 함께 보기

- [마크다운 확장](/ko/features/markdown-extensions/) — 코드 블록과 언어 지원
- [설정](/ko/start/config/) — 강조 설정 레퍼런스
