+++
title = "Codeberg Pages"
description = "Hwaro 사이트를 Codeberg Pages에 배포"
weight = 7
+++

[Codeberg Pages](https://codeberg.page/)에 Hwaro 사이트를 배포합니다. Codeberg의 Forgejo 인스턴스가 뒷받침하는 무료 정적 호스팅입니다.

## Codeberg Pages 동작 방식

Codeberg는 정적 사이트를 두 가지 방식으로 제공합니다:

- **사용자/조직 사이트** — 계정 아래 **`pages`**라는 이름의 저장소. Codeberg는 이 저장소의 *기본 브랜치*를 `https://USERNAME.codeberg.page/`에서 제공합니다.
- **프로젝트 사이트** — 그 외 모든 저장소. **`pages`**라는 이름의 브랜치를 `https://USERNAME.codeberg.page/REPO/`에서 제공합니다.

이 구분이 중요합니다. 프로젝트 사이트는 `pages` *브랜치*에 푸시하고, 사용자 사이트는 `pages` *저장소*의 *기본 브랜치*(보통 `main`)에 푸시합니다. 아래 워크플로는 프로젝트 사이트를 기본값으로 하되 `PAGES_BRANCH` 변수를 노출해, 사용자 사이트는 한 줄만 바꾸면 되도록 했습니다.

## 사전 준비

- Codeberg 계정
- Codeberg 저장소 (사용자 사이트는 `pages`, 프로젝트 사이트는 아무 저장소나)
- `write:repository` 스코프를 가진 Codeberg 액세스 토큰 (Settings → Applications → Generate new token)

## 방법 1: Forgejo Actions (권장)

Codeberg는 GitHub Actions와 호환되는 [Forgejo Actions](https://forgejo.org/docs/latest/user/actions/)를 지원합니다. Forgejo Actions는 저장소별로 직접 켜야 하는 옵트인 기능이므로, 워크플로를 실행하기 전에 **Settings → Actions**에서 활성화합니다.

> Forgejo는 하위 호환을 위해 `.gitea/workflows/` 경로도 허용하지만, 업스트림이 권장하는 경로이자 Hwaro가 생성하는 경로는 `.forgejo/workflows/`입니다.

### 워크플로 생성

```bash
hwaro tool platform codeberg-pages
```

다음 내용이 `.forgejo/workflows/deploy.yml`에 생성됩니다:

```yaml
---
name: Hwaro Deploy

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: docker
    container:
      image: ghcr.io/hahwul/hwaro:latest
    env:
      # 프로젝트 사이트: "pages" (기본값). 사용자/조직 사이트("pages"라는
      # 이름의 저장소): 기본 브랜치(예: "main")로 바꿉니다.
      PAGES_BRANCH: pages
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build site
        run: hwaro build

      - name: Deploy to Codeberg Pages
        env:
          CODEBERG_TOKEN: ${{ secrets.CODEBERG_TOKEN }}
        run: |
          cd public
          git init -b "$PAGES_BRANCH"
          git config user.name  "${{ github.actor }}"
          git config user.email "${{ github.actor }}@noreply.codeberg.org"
          git add -A
          git commit -m "Deploy: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
          git push --force \
            "https://${{ github.actor }}:$CODEBERG_TOKEN@codeberg.org/${{ github.repository }}.git" \
            "$PAGES_BRANCH"
```

> **브랜치 히스토리는 보존되지 않습니다.** 실행할 때마다 새로 `git init`한 뒤 강제 푸시하므로, 게시 브랜치는 게시 전용 산출물로 취급합니다. 소스는 `main`(또는 개발에 쓰는 브랜치)에 두고, `pages` 브랜치는 직접 수정하지 않습니다.

### 사용자 사이트와 프로젝트 사이트

기본값 `PAGES_BRANCH: pages`는 **프로젝트 사이트**(아무 저장소, `USERNAME.codeberg.page/REPO/`에서 제공)를 대상으로 합니다. 저장소 이름이 정확히 `pages`인 **사용자/조직 사이트**라면 브랜치를 기본 브랜치로 바꿉니다:

```yaml
    env:
      PAGES_BRANCH: main   # `pages` 저장소의 기본 브랜치
```

### 토큰 시크릿 추가

1. 저장소 **Settings → Actions → Secrets**로 이동
2. `CODEBERG_TOKEN`이라는 이름으로 새 시크릿 추가
3. `write:repository` 스코프를 가진 Codeberg 액세스 토큰 붙여넣기

### Base URL 설정

`config.toml`을 수정합니다:

```toml
# 사용자/조직 사이트 ("pages"라는 이름의 저장소)
base_url = "https://USERNAME.codeberg.page"

# 프로젝트 사이트 (그 외 저장소)
base_url = "https://USERNAME.codeberg.page/REPO"
```

`main`에 푸시하면 워크플로가 자동으로 빌드하고 배포합니다.

## 방법 2: `hwaro deploy`로 배포

로컬 머신에서 배포하려면 간단한 셸 스크립트를 호출하는 `[[deployment.targets]]` 항목으로 연결합니다.

`scripts/deploy-codeberg.sh`를 작성합니다:

```bash
#!/bin/bash
set -e

SOURCE_DIR="${1:?Usage: deploy-codeberg.sh <source-dir>}"
REMOTE_URL="${CODEBERG_REMOTE:-$(git remote get-url origin)}"
PAGES_BRANCH="${PAGES_BRANCH:-pages}"
TMPDIR=$(mktemp -d)

cp -r "$SOURCE_DIR"/. "$TMPDIR"

cd "$TMPDIR"
git init -b "$PAGES_BRANCH"
git add -A
git commit -m "Deploy to Codeberg Pages"
git push --force "$REMOTE_URL" "$PAGES_BRANCH"

rm -rf "$TMPDIR"
```

```bash
chmod +x scripts/deploy-codeberg.sh
```

`config.toml`에 타깃을 추가합니다:

```toml
[[deployment.targets]]
name = "codeberg-pages"
command = "scripts/deploy-codeberg.sh {source}"
```

이제 빌드하고 배포합니다:

```bash
hwaro build
hwaro deploy codeberg-pages

# 배포하지 않고 미리 보기
hwaro deploy codeberg-pages --dry-run

# 사용자 사이트 (`pages` 대신 기본 브랜치에 푸시)
PAGES_BRANCH=main hwaro deploy codeberg-pages
```

방법 1과 마찬가지로 스크립트는 새로 초기화한 저장소를 강제 푸시하므로, 브랜치 히스토리는 보존되지 않습니다.

## 방법 3: 브랜치 수동 배포

```bash
hwaro build

cd public
git init -b pages
git add -A
git commit -m "Deploy"
git push --force https://codeberg.org/USERNAME/REPO.git pages
```

사용자 사이트(`pages` 저장소)라면 `init`과 `push` 명령의 `pages` 자리에 기본 브랜치 이름(예: `main`)을 넣습니다.

## 커스텀 도메인

Codeberg Pages는 `.domains` 파일과 DNS 레코드로 커스텀 도메인을 지원합니다. 정확한 최신 내용은 [공식 Codeberg 문서](https://docs.codeberg.org/codeberg-pages/using-custom-domain/)를 참고합니다.

> **점(`.`)이 들어간 저장소 이름은 지원되지 않습니다.** 커스텀 도메인을 붙일 계획이라면 저장소 이름에 `-`나 `_`를 사용합니다.

### 1. `.domains` 파일 추가

제공되는 브랜치의 루트에 `.domains` 파일을 두고 도메인을 한 줄에 하나씩 나열합니다. **첫 줄이 대표(canonical) 도메인**이며, 나머지 도메인은 모두 첫 줄로 301 리다이렉트됩니다. 빈 줄과 `#` 주석을 쓸 수 있습니다.

```
www.example.org
example.org
```

`static/.domains`에 두면 Hwaro가 빌드할 때마다 `public/`으로 복사합니다:

```
static/
└── .domains
```

Hwaro는 콜드 빌드든 `--cache`/증분 빌드든 매번 `static/`의 숨김 dot 경로를 그대로 `public/`에 복사하므로, `static/.domains`는 항상 게시 브랜치에 포함됩니다. 자세한 내용은 [설정](/ko/start/config/) 문서의 정적 파일 항목을 참고합니다.

### 2. DNS 설정

아래 세 가지 옵션 중 **하나만** 선택합니다.

**옵션 A — CNAME (권장, 가장 간단).** 도메인을 다음 이름 중 하나로 연결합니다:

| 사이트 유형     | CNAME 대상                              |
|---------------|-------------------------------------------|
| 개인 사이트 | `USERNAME.codeberg.page`                  |
| 프로젝트 사이트  | `REPO.USERNAME.codeberg.page`             |
| 커스텀 브랜치 | `BRANCH.REPO.USERNAME.codeberg.page`      |

CNAME은 *호스트네임 전체*를 위임하므로, 이 옵션에서는 같은 이름으로 이메일(MX)을 운영할 수 없습니다.

**옵션 B — ALIAS + TXT.** DNS 제공자가 `ALIAS`(또는 `ANAME`) 레코드를 지원하는 경우:

| 타입  | 이름 | 값                                |
|-------|------|--------------------------------------|
| ALIAS | @    | `codeberg.page`                      |
| TXT   | @    | `REPO.USERNAME.codeberg.page` (사용자 사이트는 `USERNAME.codeberg.page`) |

**옵션 C — A + AAAA + TXT.** 제공자가 ALIAS를 지원하지 않거나, 존이 DNSSEC를 사용하는 경우(`codeberg.page` CNAME과 호환되지 않음) 사용합니다:

| 타입 | 이름 | 값                                |
|------|------|--------------------------------------|
| A    | @    | `217.197.84.141`                     |
| AAAA | @    | `2a0a:4580:103f:c0de::2`             |
| TXT  | @    | `REPO.USERNAME.codeberg.page` (사용자 사이트는 `USERNAME.codeberg.page`) |

> Codeberg는 이 IP를 가끔 교체하므로, 사용하기 전에 [Codeberg Pages 문서](https://docs.codeberg.org/codeberg-pages/using-custom-domain/)에서 최신 IP를 확인합니다.

존에 CAA 레코드가 있다면 Codeberg가 TLS 인증서를 발급할 수 있도록 Let's Encrypt를 허용하는 항목을 추가합니다:

```
@   CAA   0 issue "letsencrypt.org"
```

### 3. `base_url` 갱신

```toml
base_url = "https://www.example.org"
```

## 문제 해결

### 워크플로가 실행되지 않을 때

- 저장소 **Settings → Actions**에서 Forgejo Actions가 활성화되어 있는지 확인합니다
- 워크플로 파일이 `.forgejo/workflows/deploy.yml`(또는 `.gitea/workflows/deploy.yml`)에 커밋되어 있는지 확인합니다

### 푸시가 401/403으로 실패할 때

- `CODEBERG_TOKEN` 시크릿 값과 토큰에 `write:repository` 스코프가 아직 있는지 다시 확인합니다
- 토큰은 계정에 귀속되므로, 해당 계정에 대상 저장소 푸시 권한이 있는지 확인합니다

### 배포된 사이트가 404일 때

- Codeberg Pages는 첫 푸시 후 게시까지 1~2분 걸릴 수 있습니다
- 프로젝트 사이트라면 브랜치 이름이 정확히 `pages`인지 확인합니다
- 사용자 사이트라면 저장소 이름이 정확히 `pages`이고 `PAGES_BRANCH`가 기본 브랜치와 일치하는지 확인합니다
- `base_url`이 게시된 URL과 일치하는지(끝 슬래시 없음) 확인합니다

### 커스텀 도메인이 HTTPS로 연결되지 않을 때

- `.domains` 파일이 게시 브랜치 루트에 있는지 확인합니다
- CAA 레코드가 있다면 `letsencrypt.org`가 허용되어 있는지 확인합니다
- DNS 전파 후 인증서 발급까지 몇 분 기다립니다

## 함께 보기

- [배포 설정](/ko/deploy/config/) — 타깃 설정과 매처
- [CLI](/ko/start/cli/) — 배포 명령 옵션 전체
- [Codeberg Pages 문서](https://docs.codeberg.org/codeberg-pages/) — 업스트림 레퍼런스
- 다른 플랫폼: [GitHub Pages](/ko/deploy/github-pages/) | [GitLab CI](/ko/deploy/gitlab-ci/) | [Netlify](/ko/deploy/netlify/) | [Cloudflare Pages](/ko/deploy/cloudflare-pages/)
