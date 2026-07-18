+++
title = "출력 포맷"
description = "HTML과 함께 페이지/섹션별 추가 출력 포맷(JSON, XML, TXT, CSV) 렌더링"
weight = 12
toc = true
+++

모든 페이지와 섹션이 항상 렌더링하는 HTML 페이지 외에, Hwaro는 나란히 놓이는 비HTML 파일도 추가로 렌더링할 수 있습니다 — 글의 JSON 표현, 섹션의 피드 형태 XML 목록, 일반 텍스트 내보내기 등. HTML 렌더링에는 영향이 없으며, 추가 포맷은 어디까지나 덧붙는 것입니다.

사이트의 RSS/Atom 피드 마크업을 커스터마이즈하려는 거라면, 그건 출력 포맷이 아니라 [커스텀 피드 템플릿](/ko/features/seo/)(`templates/rss.xml.jinja`)입니다.

## 설정

```toml
[outputs]
page = []                 # 예: ["json"] — 모든 일반 페이지가 내보내는 포맷
section = ["json"]        # 모든 섹션 인덱스가 내보내는 포맷
sections = []              # 선택적 섹션 이름 허용 목록. 비어 있으면 전체
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| page | array | [] | 모든 일반 페이지가 내보내는 포맷 |
| section | array | [] | 모든 섹션 인덱스가 내보내는 포맷 |
| sections | array | [] | `section` 출력을 제한할 섹션 이름(과 그 하위). 비어 있으면 모든 섹션 |

지원되는 포맷은 네 가지뿐이며, 포맷 이름이 곧 파일 확장자입니다.

```
json  txt  xml  csv
```

`[outputs]`에 알 수 없는 포맷 이름이 있으면 조용히 아무것도 출력하지 않는 대신, 분류된 설정 오류와 함께 빌드가 즉시 실패합니다.

`sections`는 섹션 이름 자체 또는 그 하위 어느 것과도 매칭됩니다(`"posts"` 값은 `"posts/reviews"`에도 매칭). `[feeds].sections`와 같은 규칙입니다.

## 프론트 매터 오버라이드

페이지(또는 섹션)는 프론트 매터의 최상위 `outputs` 키로 설정 기본값을 덮어쓸 수 있습니다.

```toml
+++
title = "My Post"
outputs = ["json"]
+++
```

`outputs`는 일급 프론트 매터 필드가 아닙니다 — 다른 알 수 없는 최상위 키처럼 `page.extra["outputs"]`에 담기고 템플릿에는 `page.extra.outputs`로 노출됩니다. 프론트 매터에 이 키가 *존재*하기만 하면 명시적인 빈 목록을 포함해 항상 설정 기본값을 이깁니다.

```toml
+++
title = "Opt this page out"
outputs = []
+++
```

이렇게 하면 `config.toml`의 `[outputs].page`가 비어 있지 않더라도 그 한 페이지의 모든 포맷이 억제됩니다. 키가 아예 없으면 설정 기본값(섹션의 경우 `sections` 허용 목록 포함)이 적용됩니다.

일반적인 `extra` 값이므로 다른 extra 필드처럼 섹션의 `[cascade.extra]` 테이블을 통해 캐스케이드되기도 합니다.

```toml
+++
title = "Blog"

[cascade.extra]
outputs = ["json"]
+++
```

이렇게 하면 페이지가 직접 설정하지 않는 한 모든 하위 페이지가 `outputs = ["json"]`을 갖습니다. 형식이 잘못된 오버라이드(배열이 아니거나 `json`/`txt`/`xml`/`csv` 밖의 이름을 포함)는 1회성 빌드 경고와 함께 무시됩니다 — 빌드를 실패시키는 대신 해당 페이지는 추가 포맷 없음으로 처리됩니다.

## 템플릿

활성화된 각 포맷은 전용 Crinja 템플릿에서 렌더링됩니다. 템플릿 이름은 `page.html`/`section.html`과 같은 관례로 확장자를 따릅니다.

```
templates/page.json.jinja
templates/section.json.jinja
templates/page.xml.jinja
```

Hwaro가 템플릿을 로드할 때는 마지막의 인식되는 템플릿 확장자(`.html`, `.j2`, `.jinja2`, `.jinja`, `.ecr`)만 제거합니다 — `.json`/`.xml` 부분은 템플릿 이름의 일부로 남습니다. 예를 들어 `templates/page.json.jinja`는 `page.json`으로 로드됩니다.

페이지 자신의 본문 마크다운/콘텐츠, `toc`, 그리고 `page.html`/`section.html`에서 평소 쓸 수 있는 다른 모든 값(`page`, `section`, `site`, `config`, …)을 포맷 템플릿에서도 쓸 수 있습니다. 포맷에 필요한 것을 자유롭게 작성하면 됩니다. 예:

```jinja
{# templates/page.json.jinja #}
{
  "title": {{ page.title | tojson }},
  "url": "{{ page.url }}",
  "date": "{{ page.date }}"
}
```

```jinja
{# templates/section.json.jinja #}
{
  "title": {{ section.title | tojson }},
  "pages": [
    {% for p in section.pages %}
    "{{ p.url }}"{% if not loop.last %},{% endif %}
    {% endfor %}
  ]
}
```

### 템플릿 선택 체인

주어진 페이지/섹션과 활성화된 포맷 `<fmt>`에 대해 Hwaro는 다음 순서로 시도합니다.

1. `<entry-template>.<fmt>` — 페이지가 실제로 해석되는 템플릿의 포맷별 형제(프론트 매터가 `template = "post"`라면 `post.json`을 먼저 찾음)
2. `section.<fmt>` — 섹션만
3. `page.<fmt>` — 최종 폴백

**활성화된 포맷의 템플릿이 없으면 하드 빌드 오류입니다.** 후보가 하나도 없으면 빌드가 즉시 실패하고 시도한 템플릿 이름을 모두 나열합니다. 예:

```
Error [HWARO_E_TEMPLATE]: No template found for output format 'txt' on about.md. Tried: page.txt.
Create one of: templates/page.txt.jinja.
```

이는 의도된 동작입니다. 설정이나 프론트 매터에서 켠 포맷이 조용히 아무것도 만들지 않는 것이, 시끄럽게 실패하는 것보다 더 나쁜 실패 방식이기 때문입니다.

## 출력 위치

포맷은 페이지의 `index.html` 옆에 나란히 `index.<fmt>`로 렌더링됩니다.

```
public/
  posts/hello/index.html
  posts/hello/index.json   <- [outputs].page = ["json"]
```

## 페이지네이션

포맷은 페이지/섹션당 한 번만 — **1페이지에만** 적용됩니다. 페이지네이션된 섹션의 `/page/2/`, `/page/3/`, …는 평소처럼 HTML을 출력하지만 자체 `index.<fmt>`는 절대 생기지 않습니다. 섹션 자신의 URL에만 생성됩니다.

## `alternate_output_tags`

활성화된 모든 포맷은 `<link rel="alternate" type="…">` 태그를 얻으며, `page.html`/`section.html`에서 `{{ alternate_output_tags }}`로 쓸 수 있습니다(포맷이 없는 페이지에서는 빈 문자열).

```jinja
<head>
  {{ alternate_output_tags }}
</head>
```

`outputs = ["json"]`인 페이지에서는 다음과 같이 렌더링됩니다.

```html
<link rel="alternate" type="application/json" href="https://example.com/posts/hello/index.json">
```

href는 `canonical`/`hreflang` 링크와 같은 방식으로 `base_url`을 거쳐 해석되므로, 서브패스 배포(`base_url = "https://user.github.io/repo"`)에서도 올바릅니다.

## 결정성

포맷 템플릿은 `page.html`과 같은 렌더링 파이프라인을 거칩니다 — 빌드 간에 바이트 단위로 동일한 출력을 원한다면 포맷 템플릿에서 `now()` 같은 비결정적 값을 피합니다([증분 빌드](/ko/features/incremental-build/) 참고).

## 알려진 제한: `--cache`에서 포맷 비활성화

`[outputs]`(또는 페이지 프론트 매터)에서 포맷을 제거해도 *이전* 빌드가 `--cache`로 이미 써 둔 파일이 소급해서 삭제되지는 않습니다 — 증분 빌드는 변경으로 감지된 페이지만 다시 렌더링하는데, "설정에서 포맷이 제거됨"은 파일별 변경으로 추적되지 않기 때문입니다. 포맷을 끈 뒤에는 전체(비증분) 빌드를 실행해 남아 있는 `index.<fmt>` 파일을 정리합니다.

## 함께 보기

- [설정](/ko/start/config/) — 전체 설정 레퍼런스
- [섹션](/ko/writing/sections/) — `[cascade.extra]`와 캐스케이드 가능한 키
- [데이터 모델](/ko/templates/data-model/) — `page.extra`
- [증분 빌드](/ko/features/incremental-build/) — `--cache` 의미론
