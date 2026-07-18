+++
title = "구조화된 데이터"
description = "리치 검색 결과를 위한 확장 Schema.org JSON-LD 지원"
weight = 2
toc = true
+++

Hwaro는 리치 검색 결과를 위한 JSON-LD 구조화된 데이터를 자동 생성합니다. 기본 제공되는 Article과 BreadcrumbList 외에 추가 Schema.org 타입도 활성화할 수 있습니다.

## 자동 생성 (항상)

다음은 모든 페이지에 생성됩니다:

- **Article** — headline, 날짜, 설명, 작성자, 이미지
- **BreadcrumbList** — 페이지 계층/상위 페이지에서 자동 생성

템플릿 변수로 제공됩니다: `{{ jsonld }}`, `{{ jsonld_article }}`, `{{ jsonld_breadcrumb }}`

## 사이트 전역 스키마

한 번만 생성되어 모든 페이지에서 사용할 수 있습니다:

### WebSite + SearchAction

Google의 사이트링크 검색창을 활성화합니다. `[search]`가 켜져 있으면 `SearchAction`이 자동으로 포함됩니다.

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

`schema_type = "HowTo"`이면 `{{ jsonld }}`에 자동 포함됩니다. `{{ jsonld_howto }}`로도 쓸 수 있습니다.

### Person

작성자 페이지 템플릿에서 사용합니다:

```jinja
{{ jsonld_person }}
```

또는 템플릿 함수로 직접 구성해도 됩니다 (작성자별 페이지용).

## 템플릿 변수

| 변수 | 범위 | 설명 |
|----------|-------|-------------|
| `jsonld` | 페이지별 | 적용 가능한 JSON-LD 전체 결합 (Article + Breadcrumb + 확장 타입) |
| `jsonld_article` | 페이지별 | Article 스키마만 |
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
  {{ jsonld_website }}
</head>
```

## 함께 보기

- [SEO](/ko/features/seo/) — 사이트맵, 피드, OpenGraph, canonical 태그
- [설정](/ko/start/config/) — 전체 설정 레퍼런스
