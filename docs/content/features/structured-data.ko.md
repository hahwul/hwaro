+++
title = "구조화된 데이터"
description = "리치 검색 결과를 위한 확장 Schema.org JSON-LD 지원"
weight = 2
toc = true
+++

Hwaro는 리치 검색 결과를 위한 JSON-LD 구조화된 데이터를 자동 생성합니다. 기본 제공되는 Article과 BreadcrumbList 외에 추가 Schema.org 타입도 활성화할 수 있습니다.

## 자동 생성 (항상)

모든 페이지에는 페이지 종류에 맞는 페이지 단위 JSON-LD가 생성됩니다:

- **Article** — 콘텐츠 페이지: headline, 날짜, 설명, 작성자, 이미지
- **CollectionPage** — 목록 페이지(섹션 인덱스, 택소노미·용어 페이지, 또는 `[extra] og_type = "website"`를 지정한 페이지): 이름, URL, 설명. 같은 페이지의 `og:type="website"`와 일치합니다
- **WebSite** — 홈 페이지에서 Article 대신 생성 (아래 참고)
- **BreadcrumbList** — 페이지 계층/상위 페이지에서 자동 생성 (홈 페이지 제외)

404 페이지에는 페이지 단위 JSON-LD가 생성되지 않으며, 제목이 없는 페이지에는 Article이 생성되지 않습니다.

템플릿 변수로 제공됩니다: `{{ jsonld }}`, `{{ jsonld_article }}`, `{{ jsonld_breadcrumb }}`

## 사이트 전역 스키마

한 번만 생성되어 모든 페이지에서 사용할 수 있습니다. 둘 다 `base_url`이 필요하며, 없으면 빈 문자열로 렌더링됩니다.

### WebSite + SearchAction

Google의 사이트링크 검색창을 활성화합니다. `[search]`가 켜져 있으면 `SearchAction`이 자동으로 포함됩니다. 대상 URL은 `<base_url>/?q={search_term_string}`이므로 `q` 쿼리 매개변수를 읽는 페이지가 사이트에 있어야 합니다(내장 검색 UI는 읽지 않습니다).

홈 페이지의 `{{ jsonld }}`에는 이 스키마가 이미 포함되어 있으므로, `{{ jsonld_website }}`는 `{{ jsonld }}`를 쓰지 않는 곳에서만 직접 출력하세요.

```jinja
{{ jsonld_website }}
```

### Organization

사이트 설정에서 가져온 기본 조직 정보입니다. `og.default_image`가 설정되어 있으면 로고로 사용합니다.

```jinja
{{ jsonld_organization }}
```

## 페이지별 스키마

프론트 매터에 `schema_type`을 설정하면 추가 타입을 자동 감지해 포함합니다:

### FAQPage

```toml
+++
title = "Frequently Asked Questions"
schema_type = "FAQ"
faq_questions = ["What is Hwaro?", "How do I install it?"]
faq_answers = ["A fast static site generator.", "Run crystal build."]
+++
```

또는 쌍(pair) 배열 형식을 사용합니다:
```toml
faq = ["Question 1", "Answer 1", "Question 2", "Answer 2"]
```

또는 테이블 배열 형식을 사용합니다:
```toml
[[extra.faq]]
question = "What is Hwaro?"
answer = "A fast static site generator."
```

`schema_type = "FAQ"`이면 FAQ 스키마가 `{{ jsonld }}`에 자동 포함됩니다. `{{ jsonld_faq }}`를 직접 써도 됩니다.

### HowTo

```toml
+++
title = "Getting Started with Hwaro"
schema_type = "HowTo"
howto_names = ["Install", "Configure", "Build"]
howto_texts = ["Run the install command.", "Edit config.toml.", "Run hwaro build."]
+++
```

또는 쌍 배열 형식을 사용합니다:
```toml
howto_steps = ["Step Name", "Step Description", "Step 2 Name", "Step 2 Description"]
```

또는 테이블 배열 형식을 사용합니다:
```toml
[[extra.howto_steps]]
name = "Install"
text = "Run the install command."
```

`schema_type = "HowTo"`이면 `{{ jsonld }}`에 자동 포함됩니다. `{{ jsonld_howto }}`로도 쓸 수 있습니다.

## 템플릿 변수

| 변수 | 범위 | 설명 |
|----------|-------|-------------|
| `jsonld` | 페이지별 | 적용 가능한 JSON-LD 전체 결합 (Article 또는 CollectionPage + Breadcrumb + 확장 타입, 홈 페이지에서는 WebSite) |
| `jsonld_article` | 페이지별 | Article 스키마만 (목록 페이지에서는 CollectionPage, 홈 페이지에서는 비어 있음) |
| `jsonld_breadcrumb` | 페이지별 | BreadcrumbList 스키마만 |
| `jsonld_faq` | 페이지별 | FAQPage 스키마 (FAQ가 아니면 비어 있음) |
| `jsonld_howto` | 페이지별 | HowTo 스키마 (HowTo가 아니면 비어 있음) |
| `jsonld_website` | 전역 | WebSite + SearchAction 스키마 |
| `jsonld_organization` | 전역 | Organization 스키마 |

## 템플릿에서 사용

베이스 템플릿의 `<head>`에 넣는 일반적인 배치:

```jinja
<head>
  {{ jsonld }}
</head>
```

`{{ jsonld }}`는 홈 페이지에서 이미 WebSite 스키마를 담고 있으므로, 옆에 `{{ jsonld_website }}`를 추가하면 홈 페이지에 두 번 출력됩니다.

## 함께 보기

- [SEO](/ko/features/seo/) — 사이트맵, 피드, OpenGraph, canonical 태그
- [설정](/ko/start/config/) — 전체 설정 레퍼런스
