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
image:
  name: ghcr.io/hahwul/hwaro:latest
  entrypoint: [""]

pages:
  stage: deploy
  script:
    - hwaro build
  artifacts:
    paths:
      - public
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

이 설정은 기본 브랜치에 푸시할 때 공식 Hwaro Docker 이미지로 사이트를 빌드하고 `public` 디렉터리를 GitLab Pages에 배포합니다. `entrypoint: [""]`는 꼭 필요합니다. 이미지의 엔트리포인트는 받은 인자를 `hwaro`에 넘기므로, 이를 덮어쓰지 않으면 GitLab이 잡의 셸 스크립트를 실행할 수 없습니다.

## 함께 보기

- [배포 설정](/ko/deploy/config/) — 타깃 설정과 매처
- [CLI](/ko/start/cli/) — 배포 명령 옵션 전체
- 다른 플랫폼: [GitHub Pages](/ko/deploy/github-pages/) | [Netlify](/ko/deploy/netlify/) | [Vercel](/ko/deploy/vercel/)
