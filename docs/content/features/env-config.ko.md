+++
title = "환경별 설정"
description = "배포 환경마다 설정을 재정의합니다"
weight = 19
toc = true
+++

Hwaro는 환경별 설정 재정의를 지원합니다. 개발, 스테이징, 프로덕션마다 다른 설정을 쓸 수 있습니다.

## 동작 방식

1. 기본 설정을 `config.toml`에서 불러옵니다
2. 환경이 지정되면 `config.<env>.toml`을 불러와 그 위에 병합합니다
3. 중첩 섹션(테이블)은 깊은 병합(deep merge)되고, 최상위 값과 말단 값은 교체됩니다

## 환경 지정

`--env` 플래그나 `HWARO_ENV` 환경 변수를 사용합니다.

```bash
# CLI 플래그로
hwaro build --env production
hwaro serve --env development

# 환경 변수로
HWARO_ENV=staging hwaro build

# CLI 플래그가 HWARO_ENV보다 우선
```

## 파일 구조

```
mysite/
├── config.toml                  # Base configuration (always loaded)
├── config.development.toml      # Development overrides
├── config.staging.toml          # Staging overrides
└── config.production.toml       # Production overrides
```

## 예시

**config.toml** (기본):

```toml
title = "My Blog"
base_url = "http://localhost:3000"

[sitemap]
enabled = true
changefreq = "weekly"

[search]
enabled = true
```

**config.production.toml** (재정의):

```toml
base_url = "https://myblog.com"

[sitemap]
changefreq = "daily"
```

`hwaro build --env production`을 실행하면 다음과 동일한 설정이 됩니다.

```toml
title = "My Blog"                     # 기본 설정에서
base_url = "https://myblog.com"       # production이 재정의

[sitemap]
enabled = true                        # 기본 설정에서(깊은 병합)
changefreq = "daily"                  # production이 재정의

[search]
enabled = true                        # 기본 설정에서(변경 없음)
```

## 깊은 병합 동작

하위 테이블은 통째로 교체되지 않고 재귀적으로 병합됩니다. 바꾸고 싶은 값만 지정하면 됩니다.

| 기본 | 재정의 | 결과 |
|------|----------|--------|
| `[sitemap] enabled = true, changefreq = "weekly"` | `[sitemap] changefreq = "daily"` | `[sitemap] enabled = true, changefreq = "daily"` |

최상위 스칼라와 배열은 병합되지 않고 교체됩니다.

| 기본 | 재정의 | 결과 |
|------|----------|--------|
| `title = "Base"` | `title = "Prod"` | `title = "Prod"` |

## 환경 변수

환경별 설정 파일에서도 [환경 변수](/ko/features/env-variables/) 치환을 사용할 수 있습니다.

```toml
# config.production.toml
base_url = "${PRODUCTION_URL}"

[og]
fb_app_id = "${FB_APP_ID}"
```

## 활용 사례

### 환경별로 다른 base URL

```toml
# config.development.toml
base_url = "http://localhost:3000"

# config.staging.toml
base_url = "https://staging.myblog.com"

# config.production.toml
base_url = "https://myblog.com"
```

### 프로덕션에서만 기능 활성화

```toml
# config.production.toml
[search]
enabled = true

[feeds]
enabled = true
```

### 환경별로 다른 애널리틱스

```toml
# config.staging.toml
[og]
fb_app_id = "staging-app-id"

# config.production.toml
[og]
fb_app_id = "prod-app-id"
```

## 함께 보기

- [설정](/ko/start/config/) — 설정 전체 참조
- [환경 변수](/ko/features/env-variables/) — 설정과 템플릿의 환경 변수 치환
- [CLI](/ko/start/cli/) — 명령줄 옵션
