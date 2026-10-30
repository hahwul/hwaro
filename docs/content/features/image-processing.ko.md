+++
title = "이미지 처리"
description = "빌드 시 자동 이미지 리사이즈, LQIP 플레이스홀더, 대표 색상 추출"
weight = 23
toc = true
+++

Hwaro는 빌드 중에 리사이즈된 이미지 변형을 자동으로 생성할 수 있습니다. 반응형 이미지, 썸네일, 성능 최적화에 유용합니다. 외부 도구는 필요 없습니다. 이미지 처리는 [stb](https://github.com/nothings/stb) 라이브러리 기반으로 바이너리에 내장되어 있습니다.

## 지원 포맷

| 포맷 | 읽기 | 쓰기 |
|--------|------|-------|
| JPEG (.jpg, .jpeg) | 가능 | 가능 |
| PNG (.png) | 가능 | 가능 |
| BMP (.bmp) | 가능 | 가능 |
| WebP (.webp) | 불가(그대로 복사) | 추가 변형으로 가능(`formats`) |

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
| quality | int | 85 | JPEG 출력 품질 (1-100), WebP에도 사용 |
| formats | array | [] | 원본 포맷 외에 추가로 쓸 출력 포맷: `["webp"]`. 다른 값은 설정 오류 |
| dimensions | bool | false | 콘텐츠 이미지에 원본 `width`/`height` 추가 (`enabled` 없이도 동작) |

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

너비 32, 품질 20이면 이미지당 보통 400-800바이트 정도의 base64 문자열이 나옵니다. HTML에 바로 인라인해도 될 만큼 작습니다.

### WebP 출력

`formats = ["webp"]`를 설정하면 모든 너비 변형을 WebP로도 씁니다. 같은 화질이라면 WebP 파일은 보통 원본 JPEG이나 PNG보다 훨씬 작습니다:

```toml
[image_processing]
enabled = true
widths = [320, 640, 1024]
quality = 80
formats = ["webp"]
```

- 각 변형 옆에 WebP 사본이 생깁니다: `hero_640w.jpg`와 `hero_640w.webp`.
- WebP 변형은 `quality`에 맞춘 손실 압축입니다(사진을 무손실 WebP로 쓰면 JPEG보다 커지므로 `100`은 `99`로 취급합니다). 투명도는 무손실로 보존됩니다.
- `srcset`이 붙는 콘텐츠 이미지는 WebP `<source>`가 들어간 `<picture>`로 감쌉니다. WebP를 지원하지 않는 브라우저는 계속 `<img>`를 씁니다:

  ```html
  <picture>
    <source type="image/webp" srcset="/hero_320w.webp 320w, /hero_640w.webp 640w" sizes="100vw">
    <img srcset="/hero_320w.jpg 320w, /hero_640w.jpg 640w" sizes="100vw" src="/hero.jpg" alt="Hero">
  </picture>
  ```

  직접 작성한 `<picture>` 안의 `<img>`에는 `srcset`은 붙지만 WebP `<source>`나 또 하나의 `<picture>`는 붙지 않습니다. 자체 `srcset`이 있는 `<img>`는 건드리지 않습니다. 가장 넓은 변형에 WebP 사본이 없는 이미지(WebP는 가로·세로 최대 16383px이라 그보다 큰 변형은 WebP로 쓰지 않습니다)는 `srcset`만 붙고 `<picture>`로 감싸지 않습니다. 감싸면 브라우저가 WebP `<source>`를 골라 더 넓은 크기를 끝내 받지 못하기 때문입니다. AMP 페이지에는 `<img>`만 남습니다.
- 템플릿에서는 `resize_image(path=…, width=…, format="webp")`가 WebP 변형을 돌려줍니다([템플릿에서 사용](#템플릿에서-사용) 참고).
- 인코더는 Hwaro에 내장되어 있어(순수 Crystal) 외부 도구나 라이브러리가 필요 없습니다.
- WebP 파일은 원본으로 쓰지 않습니다. `static/`이나 페이지 번들의 `.webp`는 그대로 복사됩니다.
- 같은 디렉터리에 확장자만 다른 원본(`hero.jpg`와 `hero.png`)이 있으면 같은 WebP 이름을 쓰게 됩니다. 경로가 먼저 정렬되는 쪽이 그 이름을 갖고, 다른 쪽은 WebP 변형 없이 경고로 알려 줍니다.
- WebP 인코딩은 JPEG보다 오래 걸리므로 이미지가 많으면 콜드 빌드가 길어집니다. warm `--cache` 빌드와 `hwaro serve`는 원본 파일과 인코딩 설정(`quality`, LQIP 키)이 그대로인 동안 변형을 재사용하며, 그 기록은 `.hwaro/image_variants.log`에 남습니다. 인코더 출력이 바뀌는 Hwaro 릴리스로 올리면 다음 빌드에서 모든 변형을 한 번 다시 인코딩합니다.

### 이미지 크기 속성

`dimensions = true`를 설정하면 렌더링된 페이지 콘텐츠의 로컬 이미지마다 원본 크기를 붙여, 파일이 도착하기 전에 브라우저가 알맞은 자리를 잡아 둡니다(레이아웃 이동 없음):

```toml
[image_processing]
dimensions = true   # enabled = true가 필요 없습니다
```

```html
<!-- ![Logo](/hwaro.png)는 이렇게 렌더링됩니다 -->
<img width="512" height="512" src="/hwaro.png" alt="Logo" />
```

- 크기는 디코딩하지 않고 파일 헤더에서 읽습니다: JPEG, PNG, BMP, GIF, WebP, SVG(픽셀 단위 `width`/`height`, 없으면 `viewBox`).
- 로컬 파일로 이어지는 이미지만 다룹니다: 페이지 번들 에셋, `static/` 파일, `[content.files]` 복사본. 외부 URL이나 없거나 읽을 수 없는 파일은 그대로 둡니다.
- 이미 `width`나 `height`가 있는 태그는 건드리지 않습니다.
- 반응형 `srcset` 변형이 붙어도 속성 값은 원본 이미지의 크기입니다.

## 동작 방식

1. 빌드 중 Hwaro는 세 위치의 이미지를 스캔합니다:
   - **페이지 번들 에셋** (`index.md`와 함께 둔 이미지)
   - **콘텐츠 파일** (`[content.files]` 설정으로 게시되는 이미지)
   - **정적 파일** (`static/` 디렉터리의 이미지)
2. 각 이미지마다 설정된 모든 너비의 리사이즈 변형을 생성합니다
3. 종횡비는 항상 유지됩니다
4. 대상 너비가 원본보다 크면 업스케일 없이 원본을 그대로 복사합니다
5. 원본 이미지는 한 번만 디코딩한 뒤 모든 너비로 리사이즈합니다 (효율적)
6. EXIF 방향 정보가 있는 JPEG 사진(휴대폰·카메라 촬영본)은 먼저 바로 세워서 처리하므로, 변형·LQIP 플레이스홀더·`fill`/`crop` 결과가 브라우저가 보여 주는 원본과 일치합니다. `dimensions = true`는 화면에 표시되는 크기를 기록합니다

## 출력 파일 이름

리사이즈된 이미지에는 `{name}_{width}w.{ext}` 규칙으로 이름이 붙습니다. 예를 들어 `static/hwaro.png`라면:

```
static/hwaro.png
  -> public/hwaro_320w.png
  -> public/hwaro_640w.png
  -> public/hwaro_1024w.png
  -> public/hwaro_1280w.png
```

직접 게시하는 파일이 이 이름 중 하나와 같으면(예: 직접 만든 `static/hwaro_320w.png`) 덮어쓰지 않습니다. 해당 너비는 생성하지 않고 `srcset`에서도 제외합니다.

`formats = ["webp"]`이면 변형마다 `{name}_{width}w.webp` 사본도 생깁니다(`public/hwaro_320w.webp`, …). 이 이름의 파일을 직접 게시해도 같은 규칙이 적용됩니다.

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

### 템플릿에서 WebP 사용

`formats = ["webp"]`이면 `format="webp"`를 넘겨 변형의 WebP 사본을 받을 수 있습니다. WebP 변형이 없으면 원본 포맷 변형을 받습니다:

```jinja
{% set webp = resize_image(path="/images/hero.jpg", width=1024, format="webp") %}
{% set jpg = resize_image(path="/images/hero.jpg", width=1024) %}
<picture>
  <source type="image/webp" srcset="{{ webp.url }}">
  <img src="{{ jpg.url }}" width="{{ jpg.width }}" alt="Hero">
</picture>
```

투명도가 있는 이미지(PNG 로고, 아이콘)에서는 `dominant_color`가 불투명도로 가중 평균되므로 투명 픽셀 때문에 색이 어두워지지 않습니다. 알파 채널이 없는 `lqip` JPEG는 투명한 영역을 흰색으로 표시합니다.

### 자르기와 채우기

`resize_image()`는 썸네일이나 고정 크기 카드를 위해 `op`와 `anchor`를 받습니다:

```jinja
{# 400x300 상자를 덮도록 맞춘 뒤 넘치는 부분을 가운데 기준으로 자릅니다 #}
{% set card = resize_image(path="/images/hero.jpg", width=400, height=300, op="fill") %}
<img src="{{ card.url }}" width="{{ card.width }}" height="{{ card.height }}">

{# 크기를 바꾸지 않고 왼쪽 위에서 200x200 영역을 잘라냅니다 #}
{% set corner = resize_image(path="/images/hero.jpg", width=200, height=200, op="crop", anchor="top_left") %}
```

| op | 동작 |
|----|-----------|
| `fit` | 기본값. 미리 생성된 너비 변형 중 가장 가까운 것을 고릅니다(위 참고). 확대하지 않습니다. |
| `fill` | `width`x`height`를 덮도록 크기를 맞춘 뒤 `anchor` 기준으로 정확히 그 크기로 자릅니다. |
| `crop` | 크기를 바꾸지 않습니다. `anchor` 위치에서 `width`x`height` 영역을 잘라냅니다(이미지 크기로 제한). |

`anchor`는 `center`(기본값), `top`, `bottom`, `left`, `right`, `top_left`, `top_right`, `bottom_left`, `bottom_right` 중 하나입니다.

- `fill`과 `crop`에는 `width`와 `height`가 모두 필요합니다. 크기가 빠졌거나 `op`, `anchor`를 알 수 없으면 템플릿 오류입니다.
- 이 변형은 페이지가 처음 렌더링될 때 만들어지고, 원본과 `quality`가 그대로인 동안 다음 빌드에서 재사용됩니다(기록은 `.hwaro/`에 보관). `enabled = true`나 `widths`가 필요 없습니다. `--skip-image-processing`에서는 원본 URL을 반환합니다.
- 파일 이름에는 크기, op, anchor가 들어갑니다. 예: 원본 옆의 `hero_400x300_fill_center.jpg`.
- 결과의 `width`/`height`는 실제로 쓴 파일의 크기입니다. 이 변형에서 `lqip`과 `dominant_color`는 빈 문자열입니다.
- JPEG, PNG, BMP 원본만 자를 수 있습니다. 다른 포맷은 원본 URL을 반환합니다.
- `format="webp"`를 더하면 변형을 WebP로 씁니다(`hero_400x300_fill_center.webp`). 설정에 `formats`가 없어도 동작합니다.

## 라이브 데모

### 리사이즈 데모

이 문서 사이트는 `widths = [128, 256, 512, 640]`와 LQIP를 켠 상태로 이미지 처리를 사용합니다. 아래 이미지들은 `static/hwaro.png`에서 자동 생성된 리사이즈 변형입니다:

**원본** (`hwaro.png`):

<img src="/hwaro.png" alt="Hwaro 로고 - 원본" style="max-width:256px">

**128px** (`hwaro_128w.png`):

<img src="/hwaro_128w.png" alt="Hwaro 로고 - 가로 128px">

**256px** (`hwaro_256w.png`):

<img src="/hwaro_256w.png" alt="Hwaro 로고 - 가로 256px">

**512px** (`hwaro_512w.png`):

<img src="/hwaro_512w.png" alt="Hwaro 로고 - 가로 512px">

이 파일들은 빌드 시점에 생성되므로 런타임 리사이즈나 외부 서비스가 필요 없습니다. 템플릿에서는 `resize_image()`로 참조합니다:

```jinja
{% set img = resize_image(path="/hwaro.png", width=256) %}
<img src="{{ img.url }}">
{# renders as: <img src="https://example.com/hwaro_256w.png"> (img.url is absolute, under base_url) #}
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
