+++
title = "Cloudflare Pages"
description = "Hwaro 사이트를 Cloudflare Pages에 배포"
weight = 6
+++

Cloudflare Pages에 Hwaro 사이트를 배포해 전 세계에 빠르게 서비스합니다.

## 빠른 시작

### 설정 파일 생성

```bash
hwaro tool platform cloudflare
```

프로젝트 설정과 사이트 버킷 구성이 담긴 `wrangler.toml`이 생성됩니다.

### 대시보드로 배포

1. [Cloudflare Dashboard](https://dash.cloudflare.com) > **Workers & Pages**로 이동
2. **Create application** > **Pages** > **Connect to Git** 클릭
3. 저장소 선택
4. 빌드 설정 입력:
   - **Build command**: `hwaro build`
   - **Build output directory**: `public`
5. **Save and Deploy** 클릭

### Wrangler CLI로 배포

```bash
# Wrangler 설치
npm install -g wrangler

# 사이트 빌드
hwaro build

# 배포
wrangler pages deploy public --project-name my-site
```

## 수동 설정

직접 설정하려면 Cloudflare Pages 대시보드에서 다음 값을 지정합니다:

| 설정 | 값 |
|---------|-------|
| Build command | `hwaro build` |
| Build output directory | `public` |

또는 `wrangler.toml`을 작성합니다:

```toml
name = "my-site"
compatibility_date = "2024-01-01" # 배포 시점의 날짜 사용

[site]
  bucket = "./public"
```

## 리다이렉트

Cloudflare Pages는 출력 디렉터리의 `_redirects` 파일을 사용합니다. 페이지 별칭(alias)에 대한 리다이렉트 규칙을 `static/_redirects`에 작성합니다:

```
/old-url/ /posts/new-post/ 301
/legacy/post/ /posts/new-post/ 301
```

별칭은 페이지 프론트 매터에 정의합니다:

```markdown
---
title: New Post
aliases:
  - /old-url/
  - /legacy/post/
---
```

`hwaro tool platform cloudflare`로 생성한 `wrangler.toml`에는 이 리다이렉트 목록이 주석으로 포함되어 있어 `static/_redirects`로 그대로 복사하면 됩니다.

## 커스텀 도메인

1. **Workers & Pages** > 프로젝트 > **Custom domains**로 이동
2. **Set up a custom domain** 클릭
3. DNS 설정 안내를 따라 진행
4. `config.toml`의 `base_url` 갱신:

```toml
base_url = "https://www.yourdomain.com"
```

## 프리뷰 배포

Cloudflare Pages는 브랜치에 푸시할 때마다 프리뷰 배포를 자동 생성합니다. 프리뷰 URL은 `<branch>.<project>.pages.dev` 형식을 따릅니다.

## 함께 보기

- [platform](/ko/start/tools/platform/) — 플랫폼 설정 생성기 상세 옵션
- [CLI](/ko/start/cli/) — tool 명령 전체
- 다른 플랫폼: [Netlify](/ko/deploy/netlify/) | [Vercel](/ko/deploy/vercel/) | [GitHub Pages](/ko/deploy/github-pages/)
