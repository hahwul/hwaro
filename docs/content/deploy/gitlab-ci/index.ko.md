+++
title = "GitLab CI"
description = "GitLab CI/CD로 Hwaro 사이트 배포"
weight = 3
+++

GitLab CI/CD로 Hwaro 사이트를 배포합니다.

## 빠른 시작

설정 파일을 자동 생성합니다:

```bash
hwaro tool platform gitlab-ci
```

## 설정

또는 저장소에 `.gitlab-ci.yml`을 직접 추가합니다:

```yaml
image: ghcr.io/hahwul/hwaro:latest

pages:
  script:
    - hwaro build
  artifacts:
    paths:
      - public
  only:
    - main
```

이 설정은 공식 Hwaro Docker 이미지로 사이트를 빌드하고 `public` 디렉터리를 GitLab Pages에 배포합니다.

## 함께 보기

- [배포 설정](/ko/deploy/config/) — 타깃 설정과 매처
- [CLI](/ko/start/cli/) — 배포 명령 옵션 전체
- 다른 플랫폼: [GitHub Pages](/ko/deploy/github-pages/) | [Netlify](/ko/deploy/netlify/) | [Vercel](/ko/deploy/vercel/)
