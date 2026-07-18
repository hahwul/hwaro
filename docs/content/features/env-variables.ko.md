+++
title = "환경 변수"
description = "설정 파일과 템플릿에서 환경 변수를 참조합니다"
weight = 18
toc = true
+++

Hwaro는 `config.toml`과 템플릿 양쪽에서 환경 변수 치환을 지원합니다. CI/CD 파이프라인, 시크릿 관리, 개발자별 설정 같은 동적 구성이 가능합니다.

## 설정 치환

`config.toml`의 환경 변수는 TOML 파싱 전에 해석됩니다.

### 문법

| 패턴 | 설명 |
|---------|-------------|
| `${VAR}` | `VAR`의 값으로 치환 |
| `$VAR` | 동일(축약형) |
| `${VAR:-default}` | `VAR`가 없거나 비어 있으면 `default` 사용 |

### 예시

```toml
# CI/CD용 동적 base URL
base_url = "${SITE_URL:-https://localhost:1313}"

# 축약형
title = "$SITE_TITLE"

# 기본값
description = "${SITE_DESC:-My awesome site}"

[og]
fb_app_id = "${FB_APP_ID:-}"
```

기본값이 없는 미설정 변수는 그대로 남고 빌드 시 경고가 출력됩니다.

```
WARN: Environment variable 'SITE_URL' is not set (referenced in config.toml)
```

## 템플릿 함수

템플릿 안에서 환경 변수를 읽으려면 `env()` 함수를 사용합니다.

```jinja
{{ env("ANALYTICS_ID") }}
{{ env("API_KEY", default="none") }}
```

| 파라미터 | 타입 | 설명 |
|-----------|------|-------------|
| name | String | 변수 이름 |
| default | String? | 미설정 시 대체값(선택) |

변수가 설정되어 있지 않고 기본값도 없으면 빈 문자열이 반환되고 경고가 기록됩니다.

### 예시

**조건부 애널리틱스 스니펫:**

```jinja
{% if env("GA_ID") %}
<script async src="https://www.googletagmanager.com/gtag/js?id={{ env("GA_ID") }}"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', '{{ env("GA_ID") }}');
</script>
{% endif %}
```

**대체값이 있는 API 엔드포인트:**

```jinja
<script>
  const API_URL = "{{ env("API_URL", default="https://api.example.com") }}";
</script>
```

## 활용 사례

### CI/CD 파이프라인

배포 환경별로 base URL을 지정합니다.

```bash
SITE_URL=https://staging.example.com hwaro build
SITE_URL=https://example.com hwaro build
```

### 시크릿 관리

API 키와 트래킹 ID를 버전 관리 바깥에 둡니다.

```toml
# config.toml
[og]
fb_app_id = "${FB_APP_ID}"
```

```bash
export FB_APP_ID="123456789"
hwaro build
```

### 개발자별 설정

`config.toml`을 수정하지 않고도 각 개발자가 자기 셸 환경에서 값을 로컬로 재정의할 수 있습니다.

```bash
export SITE_URL="http://localhost:1313"
hwaro serve
```

## 함께 보기

- [설정](/ko/start/config/) — 설정 전체 참조
- [함수](/ko/templates/functions/) — 템플릿 함수 전체 목록
