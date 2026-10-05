+++
title = "위키링크와 백링크"
description = "Obsidian 볼트나 위키 스타일 노트를 그대로 빌드합니다: 위키링크, 이미지 임베드, 노트 트랜스클루전, 접을 수 있는 콜아웃, page.backlinks"
weight = 7
toc = true
+++

Hwaro는 Obsidian 스타일 노트 폴더를 변환 없이 바로 빌드할 수 있습니다. 스위치는 두 개이며 둘 다 기본값은 꺼짐입니다.

```toml
[markdown]
wikilinks = true   # [[링크]], ![[임베드]], 접을 수 있는 콜아웃

[content]
backlinks = true   # page.backlinks
```

볼트를 한 번만 일반 마크다운으로 변환하려면 [`hwaro tool import obsidian`](/ko/start/tools/import/)을 사용하세요.

## 위키링크

| 문법 | 링크 대상 |
|------|-----------|
| `[[Page]]` | 이름이 `Page`인 페이지 |
| `[[Page\|text]]` | 같은 페이지, `text`로 표시 |
| `[[Page#Heading]]` | 그 페이지의 제목(heading) |
| `[[Page#Heading\|text]]` | 제목, 표시 텍스트 지정 |
| `[[#Heading]]` | 현재 페이지의 제목 |

별칭이 없으면 링크 텍스트는 작성한 대상 그대로입니다(`[[Page#Heading]]`은 `Page > Heading`으로 표시). 표 안에서는 별칭 구분자를 `\|`로 이스케이프하세요. 블록 참조(`[[Page#^id]]`)는 페이지 자체로 연결됩니다.

### 대상을 찾는 방법

대상은 대소문자를 구분하지 않고 다음 기준으로 페이지와 일치합니다.

- 확장자와 언어 접미사를 뺀 파일 이름(`about.ko.md`는 `about`으로 찾음)
- 번들(`setup/index.md`)이나 섹션(`guides/_index.md`)이면 디렉터리 이름
- 대상에 `/`가 있으면 콘텐츠 경로(`[[docs/setup]]`)

제목(title)은 사용하지 않습니다. 여러 페이지가 일치하면 다음 순서로 고릅니다: 링크하는 페이지와 같은 언어, 같은 디렉터리, 가장 짧은 경로, 경로의 알파벳 순. 같은 언어에서 둘 이상이 일치하면 링크마다 한 번 경고하고 모든 후보를 나열합니다.

`#Heading`은 빌드가 그 제목에 붙이는 id와 같은 값이 되므로, `[links] broken_anchors`가 다른 프래그먼트 링크처럼 검사합니다.

### 무엇이 바뀌는가

해석된 위키링크는 마크다운 렌더링 전에 일반 내부 링크(`[text](@/path.md#heading)`)로 바뀝니다. 그래서 렌더 훅, `base_path`, 외부 링크 정책, `[links]` 검사가 `@/` 링크와 똑같이 적용됩니다.

마크다운이 링크를 만들지 않는 곳에서는 위키링크도 그대로 둡니다: 펜스 코드, 들여쓰기 코드, 인라인 코드(두 줄에 걸친 코드 스팬 포함), 원시 HTML 블록, HTML 태그와 그 속성, HTML 주석, 수식(`[markdown] math`가 켜져 있을 때 `$…$`, `$$…$$`, `\(…\)`), 백슬래시 뒤(`\[[링크 아님]]`). 숏코드 호출이나 본문 안의 위키링크도 바꾸지 않습니다.

`.md`가 아닌 확장자가 붙은 대상(`[[report.pdf]]`, `![[report.pdf]]`)은 게시된 그 파일로 연결되며, [이미지 임베드](#이미지-임베드)와 같은 방법으로 찾습니다.

어떤 페이지나 파일과도 일치하지 않는 대상은 `<span class="wikilink wikilink-missing">text</span>`로 렌더링되고 `[links] broken_internal`을 따릅니다. 기본은 경고이고, `broken_internal = "error"`이면 빌드 오류입니다.

## 이미지 임베드

| 문법 | 결과 |
|------|------|
| `![[photo.png]]` | 이미지, 파일 이름이 alt 텍스트 |
| `![[photo.png\|300]]` | 너비 300픽셀 |
| `![[photo.png\|300x200]]` | 300 × 200 |
| `![[photo.png\|A view]]` | alt 텍스트 `A view` |

파일은 먼저 페이지 자신의 번들 파일에서 찾고, 없으면 게시되는 모든 파일에서 이름으로 찾습니다: 게시된 페이지의 번들 파일, `[content.files]`, `static/`. 초안 등 게시되지 않는 번들의 파일은 찾지 않습니다. 이름이 겹치면 페이지 링크와 같은 규칙을 따릅니다.

임베드는 마크다운 이미지(크기가 있으면 `{width=… height=…}` 속성 블록 포함)가 되므로 render-image 훅, 반응형 `srcset`, `[image_processing] dimensions`가 적용됩니다. 너비를 지정하면 자동 크기 지정이 덮어쓰지 않습니다.

`wikilinks`를 켜면 `[markdown] attributes`처럼 일반 마크다운 이미지에도 `{…}` 속성 블록(`![alt](x.png){.wide}`)이 적용됩니다.

## 노트 임베드(트랜스클루전)

한 줄에 홀로 있는 노트 임베드는 그 노트의 마크다운을 페이지 안으로 가져옵니다:

| 문법 | 결과 |
|------|------|
| `![[note]]` | 노트 본문 전체 |
| `![[note#Setup]]` | `Setup` 제목부터, 같은 수준이나 더 높은 수준의 다음 제목 바로 앞 줄까지 |

가져온 텍스트는 [`include_md`](/ko/writing/shortcodes/#include-md)처럼 그 자리에 쓴 것으로 렌더링됩니다: 안의 숏코드가 펼쳐지고 제목은 페이지 목차에 들어갑니다. 결과는 `<div class="transclusion" data-source="/note/">…</div>`로 감싸며, `data-source`는 노트의 URL입니다. 노트가 다른 노트(자기 자신의 다른 제목 포함)를 다시 임베드할 수 있고 깊이는 8단계까지이며, 순환은 빌드 오류입니다.

한 줄에 홀로 있지 않은 임베드나 노트에 없는 제목을 가리키는 임베드는 노트로 가는 링크로 렌더링됩니다. 디스플레이 수식(`$$`)이나 raw HTML 블록 안의 임베드는 그대로 둡니다. 어떤 노트와도 일치하지 않는 대상은 다른 [해석되지 않는 위키링크](#위키링크)와 똑같이 처리됩니다. 임베드한 페이지는 노트가 바뀌면 `--cache` 웜 빌드와 `hwaro serve`에서 다시 렌더링됩니다.

## 접을 수 있는 콜아웃

`wikilinks`를 켜면 접기 표시가 붙은 [admonition](/ko/features/markdown-extensions/)이 `<details>` 요소로 렌더링됩니다.

```markdown
> [!TIP]- 기본으로 접힘
> 열기 전까지 숨겨짐.

> [!NOTE]+ 기본으로 펼침
> 보이며, 접을 수 있음.
```

```html
<details class="admonition admonition-tip">
<summary class="admonition-title">기본으로 접힘</summary>
<p>열기 전까지 숨겨짐.</p>
</details>
```

클래스가 admonition 클래스와 같으므로 기존 admonition CSS가 그대로 적용됩니다. `+`나 `-`가 없는 콜아웃은 이전과 같이 렌더링됩니다.

## 백링크

`page.backlinks`는 같은 언어의 게시된 페이지 중 이 페이지로 링크하는 페이지 목록입니다. 최신 페이지가 먼저 오고(날짜 없는 페이지는 마지막), 그다음 경로 순입니다. 자기 자신으로의 링크는 무시하고, 링크하는 페이지는 한 번만 나옵니다.

```jinja
{% if page.backlinks %}
<aside class="backlinks">
  <h2>이 페이지를 링크한 글</h2>
  <ul>
  {% for p in page.backlinks %}
    <li><a href="{{ p.url }}">{{ p.title }}</a></li>
  {% endfor %}
  </ul>
</aside>
{% endif %}
```

링크는 각 페이지의 마크다운 원문에서 읽습니다.

- `@/path.md` 링크
- 위키링크(`[markdown] wikilinks`가 켜져 있을 때)
- URL이 페이지 URL인 마크다운·HTML 링크(`[x](/docs/setup/)`, `href="../setup/"`)

숏코드나 템플릿이 만든 링크는 세지 않으며, 숏코드 호출이나 본문 안에 쓴 링크도 세지 않습니다(바꾸지 않으므로 세지도 않습니다).

`--cache` 빌드와 `hwaro serve`는 백링크가 바뀐 페이지를 다시 렌더링합니다. 예를 들어 다른 페이지가 이 페이지로 가는 링크를 추가하거나 지웠을 때입니다.
