+++
title = "Netlify"
description = "Hwaro 사이트를 Netlify에 배포"
weight = 4
+++

Netlify에 Hwaro 사이트를 배포하면 자동 빌드와 글로벌 CDN을 이용할 수 있습니다.

## 빠른 시작

### 설정 파일 생성

```bash
hwaro tool platform netlify
```

빌드 설정, 별칭(alias) 기반 리다이렉트, 캐시 헤더가 담긴 `netlify.toml`이 생성됩니다.

### Git으로 배포

1. 저장소를 GitHub, GitLab 또는 Bitbucket에 푸시
2. [Netlify](https://app.netlify.com)에서 **Add new site** > **Import an existing project** 클릭
3. 저장소 연결
4. Netlify가 `netlify.toml` 설정을 자동 감지
5. **Deploy site** 클릭

## 수동 설정

생성기 대신 직접 설정하려면 `netlify.toml`을 작성합니다:

```toml
[build]
  command = "hwaro build"
  publish = "public"

[build.environment]
  # 필요한 환경 변수를 설정합니다
```

## 리다이렉트

`hwaro tool platform netlify`를 사용하면 프론트 매터에 정의한 페이지 별칭이 301 리다이렉트로 자동 포함됩니다:

```markdown
---
title: New Post
aliases:
  - /old-url/
  - /legacy/post/
---
```

생성 결과:

```toml
[[redirects]]
  from = "/old-url/"
  to = "/posts/new-post/"
  status = 301

[[redirects]]
  from = "/legacy/post/"
  to = "/posts/new-post/"
  status = 301
```

## 커스텀 도메인

1. **Site settings** > **Domain management**로 이동
2. **Add custom domain** 클릭
3. DNS 설정 안내를 따라 진행
4. `config.toml`의 `base_url` 갱신:

```toml
base_url = "https://www.yourdomain.com"
```

## 배포 프리뷰

Netlify는 풀 리퀘스트마다 배포 프리뷰를 자동 생성합니다. 프리뷰 빌드는 임시 URL을 사용하므로, 배포 컨텍스트에서 base URL을 재정의합니다:

```toml
[context.deploy-preview]
  command = "hwaro build --base-url $DEPLOY_PRIME_URL"
```

`$DEPLOY_PRIME_URL`은 Netlify가 제공하는 환경 변수로, 고유한 프리뷰 URL이 담겨 있습니다(예: `https://deploy-preview-42--your-site.netlify.app`).

## 함께 보기

- [platform](/ko/start/tools/platform/) — 플랫폼 설정 생성기 상세 옵션
- [CLI](/ko/start/cli/) — tool 명령 전체
- 다른 플랫폼: [Vercel](/ko/deploy/vercel/) | [Cloudflare Pages](/ko/deploy/cloudflare-pages/) | [GitHub Pages](/ko/deploy/github-pages/)
