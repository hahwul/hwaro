+++
title = "Docker"
description = "Docker로 Hwaro 사이트 배포"
weight = 8
+++

Docker로 Hwaro 사이트를 배포합니다.

## 공식 이미지

공식 Docker 이미지는 `ghcr.io/hahwul/hwaro`에서 받을 수 있습니다.

```bash
docker pull ghcr.io/hahwul/hwaro:latest
```

## 멀티 스테이지 빌드

멀티 스테이지 빌드로 사이트를 빌드한 뒤 Nginx 같은 경량 웹 서버로 서비스할 수 있습니다.

프로젝트 루트에 `Dockerfile`을 만듭니다:

```dockerfile
# 1단계: 사이트 빌드
FROM ghcr.io/hahwul/hwaro:latest AS builder

WORKDIR /site
COPY . .

# 사이트 빌드
RUN hwaro build

# 2단계: Nginx로 서비스
FROM nginx:alpine

# 빌더 스테이지에서 빌드 결과 복사
COPY --from=builder /site/public /usr/share/nginx/html

# 80 포트 노출
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

### 빌드 및 실행

```bash
# 이미지 빌드
docker build -t my-hwaro-site .

# 컨테이너 실행
docker run -d -p 8080:80 my-hwaro-site
```

`http://localhost:8080`에 접속해 사이트를 확인합니다.

## CLI 사용

Crystal이나 Hwaro를 로컬에 설치하지 않고도 Docker 이미지로 Hwaro 명령을 바로 실행할 수 있습니다.

```bash
# 사이트 빌드
docker run --rm -v $(pwd):/site -w /site ghcr.io/hahwul/hwaro build

# 대화형 셸
docker run --rm -it -v $(pwd):/site -w /site ghcr.io/hahwul/hwaro /bin/sh
```

## 함께 보기

- [배포 설정](/ko/deploy/config/) — 타깃 설정과 매처
- [CLI](/ko/start/cli/) — 빌드/배포 옵션 전체
- 다른 플랫폼: [GitHub Pages](/ko/deploy/github-pages/) | [Netlify](/ko/deploy/netlify/) | [Vercel](/ko/deploy/vercel/)
