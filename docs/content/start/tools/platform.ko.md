+++
title = "platform"
description = "플랫폼 설정과 CI/CD 워크플로 파일 생성"
weight = 5
+++

주요 제공자용 플랫폼 설정과 CI/CD 워크플로 파일을 생성합니다. `config.toml`과 콘텐츠 별칭을 읽어 바로 쓸 수 있는 배포 설정을 만듭니다.

```bash
# 호스팅 플랫폼
hwaro tool platform netlify
hwaro tool platform vercel
hwaro tool platform cloudflare

# CI/CD 워크플로
hwaro tool platform github-pages
hwaro tool platform gitlab-ci
hwaro tool platform codeberg-pages

# 사용자 지정 경로로 출력
hwaro tool platform netlify -o deploy/netlify.toml

# 파일 대신 stdout으로 출력
hwaro tool platform vercel --stdout
```

> **참고:** `hwaro tool ci`는 사용 중단되었습니다. 대신 `hwaro tool platform github-pages`를 사용합니다.

## 지원 플랫폼

| 플랫폼 | 출력 파일 | 설명 |
|----------|-------------|-------------|
| netlify | `netlify.toml` | 빌드 설정, 리다이렉트, 헤더 |
| vercel | `vercel.json` | 빌드 명령, 라우팅, 캐시 헤더 |
| cloudflare | `wrangler.toml` | Workers/Pages 사이트 설정 |
| github-pages | `.github/workflows/deploy.yml` | GitHub Actions 빌드 + 배포 워크플로 |
| gitlab-ci | `.gitlab-ci.yml` | GitLab CI/CD 파이프라인 |
| codeberg-pages | `.forgejo/workflows/deploy.yml` | Codeberg Pages(Forgejo Actions) 배포 워크플로 |

## 옵션

| 플래그 | 설명 |
|------|-------------|
| -o, --output PATH | 출력 파일 경로 (기본값: 자동 감지) |
| --stdout | 파일 대신 stdout으로 출력 |
| -f, --force | 기존 파일을 경고 없이 덮어쓰기 |
| -h, --help | 도움말 표시 |

출력 파일이 이미 있으면 `--force`로 덮어씁니다.

## 생성되는 설정

각 설정에는 다음이 포함됩니다.

- **빌드 명령**: `hwaro build`
- **출력 디렉터리**: `public/`
- **리다이렉트**: 프론트 매터에 정의한 페이지 [`aliases`](/ko/writing/pages/)에서 만든 301 리다이렉트 (예: `aliases: ["/old-url/"]`)
- **캐시 헤더**: 정적 에셋의 장기 캐싱

### Netlify 출력

```toml
[build]
  command = "hwaro build"
  publish = "public"

[build.environment]
  # Add environment variables here

[[redirects]]
  from = "/old-url/"
  to = "/posts/new-post/"
  status = 301

[[headers]]
  for = "/assets/*"
  [headers.values]
    Cache-Control = "public, max-age=31536000, immutable"
```

### Vercel 출력

```json
{
  "buildCommand": "hwaro build",
  "outputDirectory": "public",
  "redirects": [
    {
      "source": "/old-url/",
      "destination": "/posts/new-post/",
      "statusCode": 301
    }
  ],
  "headers": [
    {
      "source": "/assets/(.*)",
      "headers": [
        {
          "key": "Cache-Control",
          "value": "public, max-age=31536000, immutable"
        }
      ]
    }
  ]
}
```

## 함께 보기

- [GitHub Pages](/ko/deploy/github-pages/) | [GitLab CI](/ko/deploy/gitlab-ci/) | [Netlify](/ko/deploy/netlify/) | [Vercel](/ko/deploy/vercel/) | [Cloudflare Pages](/ko/deploy/cloudflare-pages/) | [Codeberg Pages](/ko/deploy/codeberg-pages/) — 플랫폼별 배포 가이드
- [CLI](/ko/start/cli/) — 전체 tool 명령
