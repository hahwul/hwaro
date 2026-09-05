+++
title = "콘텐츠 생성"
description = "[[content.generate]]로 site.data 레코드를 실제 페이지로 만들기"
weight = 23
toc = true
+++

`[[content.generate]]`는 `site.data` 배열의 각 레코드(로컬 `data/` 파일 또는 [원격 데이터 소스](/ko/features/remote-data/))를 실제 콘텐츠 페이지로 만듭니다. 규칙 하나로 레코드 배열을 가리키고 어떤 필드가 슬러그·제목·본문이 될지 지정하면, 레코드마다 페이지가 빌드됩니다.

생성된 페이지는 **일급 콘텐츠**입니다. 작성한 파일과 같은 지점에서 빌드에 합류하므로 섹션 목록, `[permalinks]` 패턴, 택소노미, 피드, 검색 인덱스, 사이트맵, OG 이미지, 출력 포맷이 `content/`의 파일과 완전히 동일하게 적용됩니다. `[[data.remote]]`와 조합하면 헤드리스 CMS나 임의의 JSON API로 섹션 전체를 만들 수 있습니다. 커밋할 파일도, 스크립트도 필요 없습니다.

## 빠른 시작

```toml
# config.toml
[[content.generate]]
source = "products.items"       # site.data.products.items — 배열이어야 함
section = "products"            # 페이지는 /products/<slug>/ 에 생성
slug = "sku"                    # 레코드 필드 (슬러그화됨)
title = "name"                  # 레코드 필드
body = "description_md"         # 마크다운을 담은 레코드 필드
date = "released"               # 선택
description = "{{ item.name }} — {{ item.price }} USD"  # 선택, 템플릿
taxonomies = { tags = "categories" }                    # 선택
```

```json
// data/products.json
{"items": [
  {"sku": "blue-widget", "name": "Blue Widget", "price": 19.99,
   "released": "2024-01-15", "description_md": "A **blue** widget.",
   "categories": ["gadgets"]}
]}
```

빌드 한 번이면 `/products/blue-widget/`이 생깁니다. `page.html`로 렌더링되고, `products` 섹션 목록에 나오고, `/tags/gadgets/`에 등록되고, RSS 피드·검색 인덱스·사이트맵에 포함됩니다.

## 필드 또는 템플릿

모든 값 스펙(`slug`, `title`, `body`, `date`, `description`, 각 `taxonomies` 값)은 두 형태 중 하나입니다.

- **필드 이름** — `slug = "sku"`는 레코드의 `sku` 필드를 읽습니다. 점 표기로 중첩 객체에 접근합니다: `slug = "meta.id"`. 존재하지 않는 필드는 **레코드 번호와 실제 존재하는 키를 알려주는 하드 에러**입니다. 오타가 조용히 잘못된 페이지를 만드는 일은 없습니다. 필드가 존재하지만 `null`/`""`이면 선택 값은 그냥 생략됩니다(날짜 없는 레코드도 괜찮습니다). 필수 스펙(`slug`, `title`)에서는 에러입니다.
- **템플릿** — `{{` 또는 `{%`를 포함한 스펙은 레코드를 `item`으로 바인딩한 템플릿으로 렌더링되며, hwaro의 모든 필터를 쓸 수 있습니다: `slug = "{{ item.sku | slugify }}"`, `title = "{{ item.name | title }}"`.

## 규칙 레퍼런스

| 키 | 필수 | 의미 |
|-----|------|------|
| `source` | 예 | `site.data` 아래 배열의 점 표기 경로(`"products"` 또는 `"products.items"`). 키가 없거나 테이블이면 무엇이 발견됐는지 알려주는 하드 에러입니다. |
| `section` | 예 | 대상 섹션. 페이지 경로가 `<section>/<slug>.md`가 되므로 기존 `content/<section>/_index.md`가 목록을 만들고 해당 섹션의 `[permalinks]` 패턴이 적용됩니다. |
| `slug` | 예 | 각 페이지의 슬러그를 만드는 필드/템플릿. 결과는 슬러그화되며, 규칙 내·규칙 간 중복은 두 레코드를 모두 지목하는 하드 에러입니다. |
| `title` | 예 | 페이지 제목을 만드는 필드/템플릿. |
| `body` | 아니요 | 페이지의 **마크다운** 본문을 만드는 필드/템플릿. 숏코드, 구문 강조, 모든 마크다운 확장이 적용됩니다. |
| `body_template` | 아니요 | `body`의 대안: `templates/`의 템플릿 파일을 레코드를 `item`으로 렌더링합니다. 출력은 마크다운입니다. `body`와 상호 배타적입니다. |
| `date` | 아니요 | 페이지 날짜를 만드는 필드/템플릿. 작성 front matter와 같은 형식을 받습니다. 미래 날짜는 작성 콘텐츠와 똑같이 기본 빌드에서 제외됩니다. |
| `description` | 아니요 | 페이지 설명 필드/템플릿. |
| `taxonomies` | 아니요 | `taxonomy = "스펙"` 테이블. 배열 필드는 모든 원소를 term으로, 스칼라는 하나를, `null`/`""`은 아무것도 기여하지 않습니다. |

## 템플릿에서 레코드 전체 쓰기

템플릿은 소스 레코드 전체를 `page.extra.item`으로 보므로 필드마다 규칙에 매핑할 필요가 없습니다.

```html
{% if page.synthesized %}
<p class="price">{{ page.extra.item.price }} USD</p>
<p class="stock">{{ page.extra.item.inventory.count }}</p>
{% endif %}
```

`page.synthesized`는 생성된 페이지에서만 `true`이므로 공유 템플릿에서 분기할 수 있습니다. 작성 페이지에는 `item`이 없으니 `page.extra.item` 접근은 이 플래그로 가드하세요.

## 충돌

경로가 겹치면 항상 작성한 파일이 이깁니다. `content/products/red-widget.md`가 있으면 같은 슬러그의 생성 페이지는 경고와 함께 버려지며, 반대 방향은 없습니다. 두 레코드가 같은 슬러그를 만들면 두 레코드를 지목하며 빌드가 실패합니다.

## 리빌드와 캐시

생성 콘텐츠는 데이터와 함께 움직입니다. `data/` 파일 수정(또는 `[[data.remote]]` 페이로드 변경)은 config 수정과 같은 방식으로 캐시된 페이지를 무효화하고, `hwaro serve`는 데이터 수정 시 리빌드합니다. `build --cache`에서 생성 페이지는 항상 다시 렌더링됩니다. 지문을 만들 소스 파일이 없기 때문입니다. 작성 페이지의 캐시 동작은 그대로입니다.

레코드가 데이터에서 사라지면 다음 빌드의 페이지 집합에서도 사라지지만, `--cache`/보존된 출력 디렉터리에는 이전에 쓴 파일이 남을 수 있습니다(작성 파일의 이름 변경과 동일). 전체 빌드(`hwaro build`)는 깨끗한 출력 디렉터리에서 시작합니다.

## 툴링

`hwaro tool list`는 생성 페이지를 출처와 함께 보여줍니다(`products/blue-widget.md ← data.products.items`). 로컬 데이터 파일 기준으로 계획하며, 아직 가져오지 않은 `[[data.remote]]` 키 기반 규칙은 행 대신 안내 문구로 표시됩니다. 빌드를 실행하면 구체화됩니다.

## 에러

모든 실패는 규칙, 레코드(1부터, 데이터 순서), 고칠 내용을 지목합니다.

```
Error [HWARO_E_CONTENT]: [[content.generate]] "products.items": record #37: missing field 'skuu' (available: categories, name, price, released, sku).
```

`source`가 없거나 배열이 아닌 규칙도 빌드를 실패시킵니다. 오타가 조용히 0개의 페이지를 생성하는 일은 없어야 합니다.
