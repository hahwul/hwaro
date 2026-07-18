+++
title = "배포"
description = "사이트를 빌드해 프로덕션에 배포"
weight = 5
sort_by = "weight"
+++

Hwaro 사이트는 어떤 정적 호스팅 서비스에도 배포할 수 있습니다.

## 프로덕션 빌드

```bash
hwaro build
```

`public/`에 정적 파일이 생성됩니다. 필요하면 출력을 압축(minify)합니다:

```bash
hwaro build --minify
```

보수적인 최적화만 수행합니다. HTML 주석과 줄 끝 공백을 제거하고 JSON/XML 공백을 줄이며, 코드 블록과 콘텐츠 구조는 모두 그대로 유지됩니다.

`static/`의 모든 파일은 `public/`으로 복사되어 함께 배포됩니다. `.well-known/security.txt`, `.domains` 같은 숨김 dot 경로도 포함되며, 콜드 빌드와 `--cache`/증분 빌드에서 동일하게 동작합니다. `.DS_Store`, `.git/` 같은 OS·에디터·VCS 잔여 파일은 자동으로 걸러집니다. 조정 방법은 [설정](/ko/start/config/) 문서의 정적 파일 항목을 참고합니다.

## 기본 절차

1. 사이트 빌드: `hwaro build`
2. `public/` 디렉터리를 호스트에 업로드 (또는 `hwaro deploy` 사용)
3. 도메인 설정

## 내장 배포 명령

Hwaro에는 설정해 둔 타깃으로 배포하는 `hwaro deploy` 명령이 내장되어 있습니다:

```bash
hwaro deploy              # 첫 번째로 설정된 타깃에 배포
hwaro deploy s3           # 이름으로 특정 타깃에 배포
hwaro deploy s3 backup    # 여러 타깃에 배포
hwaro deploy --dry-run    # 변경 사항 미리 보기
```

타깃 설정, 매처, 옵션 전체는 [배포 설정](/ko/deploy/config/)을 참고합니다.

## 플랫폼 가이드

플랫폼별 배포 절차는 아래 가이드에서 단계별로 안내합니다.
