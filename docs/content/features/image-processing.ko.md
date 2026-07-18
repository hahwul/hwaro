+++
title = "이미지 처리"
description = "빌드 시 자동 이미지 리사이즈, LQIP 플레이스홀더, 대표 색상 추출"
weight = 23
toc = true
+++

Hwaro는 빌드 중에 리사이즈된 이미지 변형을 자동으로 생성할 수 있습니다. 반응형 이미지, 썸네일, 성능 최적화에 유용합니다. 외부 도구는 필요 없습니다 — 이미지 처리는 [stb](https://github.com/nothings/stb) 라이브러리 기반으로 바이너리에 내장되어 있습니다.

## 지원 포맷

| 포맷 | 읽기 | 쓰기 |
|--------|------|-------|
| JPEG (.jpg, .jpeg) | 가능 | 가능 |
| PNG (.png) | 가능 | 가능 |
| BMP (.bmp) | 가능 | 가능 |

## 설정

`config.toml`에서 이미지 처리를 활성화합니다:

```toml
[image_processing]
enabled = true
widths = [320, 640, 1024, 1280]
quality = 85
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| enabled | bool | false | 이미지 리사이즈 활성화 |
| widths | array | [] | 생성할 대상 너비(픽셀) |
| quality | int | 85 | JPEG 출력 품질 (1-100) |

### LQIP (저화질 이미지 플레이스홀더)

LQIP를 활성화하면 빌드 시점에 작은 base64 인코딩 플레이스홀더 이미지를 만들고 대표 색상을 추출합니다. CLS(Cumulative Layout Shift)를 없애고, 원본 이미지가 로드되는 동안 즉시 시각적 피드백을 보여줍니다.

```toml
[image_processing.lqip]
enabled = true
width = 32
quality = 20
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| enabled | bool | false | LQIP 생성 활성화 |
| width | int | 32 | 플레이스홀더 이미지 너비(픽셀, 8-128) |
| quality | int | 20 | 플레이스홀더 JPEG 품질 (1-100, 낮을수록 작음) |

너비 32, 품질 20이면 이미지당 보통 400-800바이트 정도의 base64 문자열이 나옵니다 — HTML에 바로 인라인해도 될 만큼 작습니다.

## 동작 방식

1. 빌드 중 Hwaro는 세 위치의 이미지를 스캔합니다:
   - **페이지 번들 에셋** (`index.md`와 함께 둔 이미지)
   - **콘텐츠 파일** (`[content.files]` 설정으로 게시되는 이미지)
   - **정적 파일** (`static/` 디렉터리의 이미지)
2. 각 이미지마다 설정된 모든 너비의 리사이즈 변형을 생성합니다
3. 종횡비는 항상 유지됩니다
4. 대상 너비가 원본보다 크면 업스케일 없이 원본을 그대로 복사합니다
5. 원본 이미지는 한 번만 디코딩한 뒤 모든 너비로 리사이즈합니다 (효율적)

## 출력 파일 이름

리사이즈된 이미지에는 `{name}_{width}w.{ext}` 규칙으로 이름이 붙습니다. 예를 들어 `static/hwaro.png`라면:

```
static/hwaro.png
  -> public/hwaro_320w.png
  -> public/hwaro_640w.png
  -> public/hwaro_1024w.png
  -> public/hwaro_1280w.png
```

## 템플릿에서 사용

`resize_image()` 함수로 리사이즈 변형의 URL을 얻습니다:

```jinja
{% set img = resize_image(path="/hwaro.png", width=640) %}
<img src="{{ img.url }}" width="{{ img.width }}">
```

`srcset`을 사용하는 반응형 이미지:

```jinja
{% set sm = resize_image(path="/hwaro.png", width=320) %}
{% set md = resize_image(path="/hwaro.png", width=640) %}
{% set lg = resize_image(path="/hwaro.png", width=1024) %}
<img
  src="{{ md.url }}"
  srcset="{{ sm.url }} 320w, {{ md.url }} 640w, {{ lg.url }} 1024w"
  sizes="(max-width: 640px) 320px, (max-width: 1024px) 640px, 1024px"
  alt="Hwaro logo"
>
```

이 함수는 가장 가까운 너비를 선택합니다. `width=500`을 요청했는데 설정된 너비가 `[320, 640, 1024]`라면 640px 변형(요청값 이상 중 가장 작은 너비)을 반환합니다. 충분히 큰 변형이 없으면 가장 큰 변형으로 폴백합니다.

### LQIP 플레이스홀더 사용

LQIP가 활성화되면 `resize_image()`가 두 속성을 추가로 반환합니다: `lqip`(base64 데이터 URI)와 `dominant_color`(16진수 색상 문자열)입니다. 블러업(blur-up) 효과나 단색 플레이스홀더에 사용합니다:

**블러업 효과:**

```jinja
{% set img = resize_image(path="/images/hero.jpg", width=1024) %}
<img
  src="{{ img.url }}"
  style="background-image: url({{ img.lqip }}); background-size: cover;"
  loading="lazy"
  alt="Hero image"
>
```

**대표 색상 플레이스홀더:**

```jinja
{% set img = resize_image(path="/images/hero.jpg", width=1024) %}
<img
  src="{{ img.url }}"
  style="background-color: {{ img.dominant_color }}"
  loading="lazy"
  alt="Hero image"
>
```

**결합 방식 (색상 → 블러 → 원본 이미지 순서):**

```jinja
{% set img = resize_image(path="/images/hero.jpg", width=1024) %}
<div style="background-color: {{ img.dominant_color }}">
  <img
    src="{{ img.url }}"
    style="background-image: url({{ img.lqip }}); background-size: cover;"
    loading="lazy"
    alt="Hero image"
  >
</div>
```

LQIP가 비활성화 상태면 `lqip`와 `dominant_color`는 빈 문자열을 반환하므로 템플릿을 고치지 않아도 됩니다.

## 라이브 데모

### 리사이즈 데모

이 문서 사이트는 `widths = [128, 256, 512]`와 LQIP를 켠 상태로 이미지 처리를 사용합니다. 아래 이미지들은 `static/hwaro.png`에서 자동 생성된 리사이즈 변형입니다:

**원본** (`hwaro.png`):

<img src="/hwaro.png" alt="Hwaro 로고 - 원본" style="max-width:256px">

**128px** (`hwaro_128w.png`):

<img src="/hwaro_128w.png" alt="Hwaro 로고 - 가로 128px">

**256px** (`hwaro_256w.png`):

<img src="/hwaro_256w.png" alt="Hwaro 로고 - 가로 256px">

**512px** (`hwaro_512w.png`):

<img src="/hwaro_512w.png" alt="Hwaro 로고 - 가로 512px">

이 파일들은 빌드 시점에 생성됩니다 — 런타임 리사이즈나 외부 서비스가 필요 없습니다. 템플릿에서는 `resize_image()`로 참조합니다:

```jinja
{% set img = resize_image(path="/hwaro.png", width=256) %}
<img src="{{ img.url }}">
{# renders as: <img src="/hwaro_256w.png"> #}
```

### LQIP 데모

`resize_image()` 함수는 LQIP 데이터도 제공합니다. `hwaro.png`의 실제 출력은 다음과 같습니다:

{{ lqip_demo(src="/hwaro.png") }}

## 성능

- **단일 디코드**: 원본 이미지를 한 번만 디코딩해 메모리에서 모든 대상 너비로 리사이즈
- **병렬 처리**: 워커 풀로 여러 이미지를 동시에 처리
- **업스케일 없음**: 대상 너비보다 작은 이미지는 그대로 복사
- **효율적인 LQIP**: LQIP 썸네일은 원본 해상도가 아니라 가장 작은 리사이즈 변형에서 생성하고, 대표 색상도 그 썸네일에서 계산

## 간단한 예시

사이트에 `static/hwaro.png`(Hwaro 로고)가 있고 이를 반응형 이미지로 표시하려는 경우입니다:

**config.toml:**

```toml
[image_processing]
enabled = true
widths = [128, 256, 512]
quality = 90

[image_processing.lqip]
enabled = true
width = 32
quality = 20
```

**템플릿:**

```jinja
{% set logo_sm = resize_image(path="/hwaro.png", width=128) %}
{% set logo_md = resize_image(path="/hwaro.png", width=256) %}
{% set logo_lg = resize_image(path="/hwaro.png", width=512) %}
<img
  src="{{ logo_md.url }}"
  srcset="{{ logo_sm.url }} 128w, {{ logo_md.url }} 256w, {{ logo_lg.url }} 512w"
  sizes="(max-width: 480px) 128px, (max-width: 768px) 256px, 512px"
  style="background-color: {{ logo_md.dominant_color }}"
  loading="lazy"
  alt="Hwaro"
>
```

**빌드 출력:**

```
public/
  hwaro.png           (original, copied by static files)
  hwaro_128w.png      (128px wide)
  hwaro_256w.png      (256px wide)
  hwaro_512w.png      (512px wide)
```

## 블로그 글 이미지

프론트 매터에 히어로 이미지를 지정한 블로그 글이라면:

```toml
[image_processing]
enabled = true
widths = [320, 640, 1024]
quality = 85

[image_processing.lqip]
enabled = true

[content.files]
allow_extensions = ["jpg", "jpeg", "png"]
```

```jinja
{% if page.image %}
  {% set hero = resize_image(path=page.image, width=1024) %}
  {% set thumb = resize_image(path=page.image, width=320) %}
  <picture>
    <source media="(min-width: 768px)" srcset="{{ hero.url }}">
    <img
      src="{{ thumb.url }}"
      style="background-color: {{ thumb.dominant_color }}"
      loading="lazy"
      alt="{{ page.title }}"
    >
  </picture>
{% endif %}
```

## 함께 보기

- [콘텐츠 파일](/ko/features/content-files/) — content/의 마크다운 이외 파일 게시
- [자동 OG 이미지](/ko/features/og-images/) — 자동 생성되는 Open Graph 미리보기 이미지
- [함수](/ko/templates/functions/) — 템플릿 함수 레퍼런스
