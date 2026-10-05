+++
title = "프론트 매터 스키마"
description = "섹션마다 필요한 프론트 매터를 타입, enum, 범위, 기본값과 함께 선언합니다"
weight = 6
toc = true
+++

프론트 매터 스키마를 쓰면 오타나 빠진 필드가 조용히 `extra`로 들어가는 대신, 파일과 줄 번호가 붙은 빌드 오류가 됩니다. 스키마는 `config.toml`에서 섹션별로 선언하며, 추가하기 전까지는 꺼져 있습니다.

## 스키마 선언

```toml
[[content.schema]]
sections = ["posts", "docs/**"]   # 섹션 경로 glob, ""는 루트
strict = false                    # true: 알 수 없는 최상위 키는 오류

[content.schema.fields.author]
type = "string"
required = true

[content.schema.fields.status]
type = "string"
enum = ["draft", "review", "final"]
default = "draft"

[content.schema.fields."extra.rating"]
type = "int"
min = 1
max = 5
```

### 스키마 키

| 키 | 타입 | 설명 |
|----|------|------|
| sections | 문자열 또는 배열 | 섹션 경로 glob. 페이지의 섹션은 `content/` 아래 디렉터리입니다(`posts/hello.md` → `posts`, 번들 `posts/hello/index.md` → `posts`, `about.md` → `""`). `"docs/**"`는 `docs`와 그 아래 전부, `"**"`는 모든 페이지와 일치합니다 |
| strict | bool | true면 [알려진 프론트 매터 필드](/ko/writing/pages/)도, 설정된 택소노미 이름(`genres = [...]`)도 아니고 `fields`에 선언되지도 않은 최상위 키가 오류입니다. `[extra]` 아래 키는 항상 허용됩니다 |
| fields | 테이블 | 필드마다 `[content.schema.fields.<이름>]` 테이블 하나 |

### 필드 키

| 키 | 설명 |
|----|------|
| type | 필수. `string`, `int`, `float`, `bool`, `date`, `array`, `table` 중 하나 |
| required | `true`면 필드가 반드시 있어야 합니다 |
| enum | 허용 값 목록(string, int, float 필드) |
| min / max | 범위: `int`/`float`는 값, `string`/`array`는 길이 |
| default | 필드가 없을 때 템플릿이 실행되기 전에 적용됩니다 |

## 매칭

페이지는 `sections`가 자기 섹션과 일치하는 **첫 번째** 스키마(설정 순서)로 검사합니다. `[permalinks]`와 같은 "첫 일치 우선" 규칙입니다. 어떤 스키마와도 일치하지 않는 페이지는 검사하지 않습니다. 섹션 `_index.md`가 아닌 일반 페이지만, 그리고 빌드가 게시하는 페이지만 검사합니다. 초안은 `--drafts`로 빌드할 때 검사됩니다.

검사는 프론트 매터와 [캐스케이드](/ko/writing/sections/#캐스케이드)가 적용된 뒤에 실행되므로, 상위 섹션이 캐스케이드한 값도 있는 것으로 칩니다.

## 필드 이름

- `extra.<키>`는 `page.extra`의 키입니다. 한 단계만 중첩할 수 있어 `extra.author.name`은 허용되지 않습니다. 테이블 헤더에서는 점이 든 이름을 따옴표로 감쌉니다: `[content.schema.fields."extra.rating"]`.
- `extra.`가 없는 이름은 같은 이름의 알려진 프론트 매터 필드(`description`, `weight`, `tags` 등)가 있으면 그 필드입니다. 이때 `type`은 그 필드 고유의 타입이어야 하며(`weight`는 `int`, `tags`는 `array`, `draft`는 `bool`, `date`는 `date`), 다르면 설정이 거부됩니다. 없으면 같은 이름의 `extra` 키입니다. Hwaro는 `author = "x"` 같은 알 수 없는 최상위 키를 `page.extra`에 저장하므로, `fields.author`는 `author = "x"`와 `[extra] author = "x"` 둘 다와 일치합니다.

## 타입

| 타입 | 허용 값 |
|------|---------|
| string | 문자열 |
| int | 정수. `4.0`은 int가 **아닙니다** |
| float | 부동소수점 수. `4`는 float가 **아니므로** `4.0`으로 씁니다 |
| bool | `true` / `false`. 명시한 `false`도 값이므로 `required`를 만족하고 기본값이 덮어쓰지 않습니다 |
| date | `date` 필드가 받는 값: TOML/YAML 날짜시간, 또는 `2024-01-15`, `2024-01-15 10:00:00`, RFC 3339 같은 문자열 |
| array | 목록 |
| table | 테이블 / 매핑 |

## 기본값

필드가 없으면 렌더링 전에 `default`가 페이지에 설정되어 템플릿에서 보입니다. extra 키는 `{{ page.extra.status }}`, 알려진 필드는 타입이 있는 속성(`{{ page.description }}`)으로 읽습니다. 기본값은 extra 키와 다음 알려진 필드를 채울 수 있습니다: `description`, `image`, `template`, `render`, `toc`, `insert_anchor_links`, `in_sitemap`, `in_search_index`, `weight`, `series`, `series_weight`, `tags`, `authors`, `updated`. `slug`, `path`, `date` 같은 필드는 페이지를 파싱하는 동안 결정되므로, 여기에 기본값을 두면 설정 오류입니다. `draft`도 기본값을 가질 수 없습니다. 게시 여부는 프론트 매터와 [`[cascade]`](/ko/writing/sections/#캐스케이드)가 정하며, `doctor`와 `tool list`도 이 둘만 읽기 때문입니다.

기본값은 자기 필드(타입, enum, 범위)를 만족해야 합니다. 기본값이 있는 필드는 누락으로 보고되지 않습니다.

## 오류

모든 페이지의 위반을 모두 모은 뒤 빌드가 한 번 실패합니다(`HWARO_E_CONTENT`, 종료 코드 5). 목록은 파일 순으로 정렬됩니다:

```
Error [HWARO_E_CONTENT]: 4 front-matter schema violations:
  content/posts/a.md: field "author": required but missing
  content/posts/a.md:3: field "status": "bogus" is not one of "draft", "review", "final"
  content/posts/a.md:4: field "autor": unknown front-matter key — did you mean "author"?
  content/posts/b.md:6: field "extra.rating": 9 is greater than the maximum 5
```

줄 번호는 프론트 매터 안에서 해당 키가 있는 줄이며, 빠진 필드는 파일만 표시합니다. `strict`에서 알 수 없는 키는 알려진 필드와 선언된 필드를 기준으로 "did you mean" 제안을 받습니다.

잘못된 스키마(알 수 없는 `type`, 타입이 가질 수 없는 `enum`, `max`보다 큰 `min`, 필드 테이블의 알 수 없는 키, 타입이 틀린 기본값)는 설정 오류입니다(`HWARO_E_CONFIG`, 종료 코드 3).

`hwaro serve`에서는 다른 콘텐츠 오류처럼 위반이 브라우저 오류 오버레이에 표시되고, 고친 파일을 저장하면 다시 빌드되며 사라집니다.

## Doctor와 Validate

[`hwaro doctor`](/ko/start/tools/doctor/)와 [`hwaro tool validate`](/ko/start/tools/validate/)는 기본 빌드가 게시하는 페이지에 같은 검사를 실행하고, 빌드와 같은 위반을 `content-schema-violation` 오류로 보고합니다. `tool validate`는 콘텐츠 디렉터리 옆의 `config.toml`(`-c site/content` → `site/config.toml`)을, 그것이 `[[content.schema]]`를 선언할 때만 읽습니다. `tool validate --json`은 각 페이지가 받는 기본값도 나열합니다:

```json
{
  "findings": [
    {
      "file": "content/posts/a.md",
      "line": 3,
      "rule": "content-schema-violation",
      "severity": "error",
      "message": "line 3: field \"status\": \"bogus\" is not one of \"draft\", \"review\", \"final\""
    }
  ],
  "defaults": {
    "content/posts/b.md": { "status": "draft" }
  }
}
```

## 참고

- [페이지](/ko/writing/pages/) — 알려진 프론트 매터 필드
- [섹션](/ko/writing/sections/) — `[cascade]`
- [설정](/ko/start/config/)
