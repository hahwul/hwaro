+++
title = "Vercel"
description = "Hwaro 사이트를 Vercel에 배포"
weight = 5
+++

Vercel에 Hwaro 사이트를 배포합니다. 별도 설정 없이도 바로 배포됩니다.

## 빠른 시작

### 설정 파일 생성

```bash
hwaro tool platform vercel
```

빌드 설정, 별칭(alias) 기반 리다이렉트, 캐시 헤더가 담긴 `vercel.json`이 생성됩니다.

### Git으로 배포

1. 저장소를 GitHub, GitLab 또는 Bitbucket에 푸시
2. [Vercel](https://vercel.com)에서 **Add New** > **Project** 클릭
3. 저장소 가져오기
4. Vercel이 `vercel.json` 설정을 자동 감지
5. **Deploy** 클릭

## 수동 설정

직접 설정하려면 `vercel.json`을 작성합니다:

```json
{
  "buildCommand": "hwaro build",
  "outputDirectory": "public"
}
```

## 리다이렉트

`hwaro tool platform vercel`을 사용하면 프론트 매터에 정의한 페이지 별칭이 301 리다이렉트로 자동 포함됩니다:

```markdown
---
title: New Post
aliases:
  - /old-url/
---
```

생성 결과:

```json
{
  "redirects": [
    {
      "source": "/old-url/",
      "destination": "/posts/new-post/",
      "statusCode": 301
    }
  ]
}
```

## 커스텀 도메인

1. **Settings** > **Domains**로 이동
2. 커스텀 도메인 추가
3. DNS 설정 안내를 따라 진행
4. `config.toml`의 `base_url` 갱신:

```toml
base_url = "https://www.yourdomain.com"
```

## 프리뷰 배포

Vercel은 프로덕션이 아닌 브랜치에 푸시할 때마다 프리뷰 배포를 자동 생성합니다. 추가 설정은 필요 없습니다.

## 함께 보기

- [platform](/ko/start/tools/platform/) — 플랫폼 설정 생성기 상세 옵션
- [CLI](/ko/start/cli/) — tool 명령 전체
- 다른 플랫폼: [Netlify](/ko/deploy/netlify/) | [Cloudflare Pages](/ko/deploy/cloudflare-pages/) | [GitHub Pages](/ko/deploy/github-pages/)
