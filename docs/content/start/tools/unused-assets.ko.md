+++
title = "unused-assets"
description = "참조되지 않는 정적 파일 찾기"
weight = 9
+++

정적 파일과 콘텐츠 옆에 함께 두는 에셋을 스캔해, 어떤 콘텐츠나 템플릿에서도 참조하지 않는 파일을 보고합니다.

```bash
# 사용하지 않는 에셋 찾기
hwaro tool unused-assets

# 디렉터리 지정
hwaro tool unused-assets -c posts -s assets

# 사용하지 않는 파일 삭제 (확인 프롬프트 표시)
hwaro tool unused-assets --delete

# 프롬프트 없이 삭제 (스크립트/CI)
hwaro tool unused-assets --delete --force

# JSON으로 출력
hwaro tool unused-assets --json

# JSON 모드에서 삭제 (프롬프트가 없으므로 --force 필요)
hwaro tool unused-assets --delete --force --json
```

## 옵션

| 플래그 | 설명 |
|------|-------------|
| -c, --content DIR | 콘텐츠 디렉터리 (기본값: content) |
| -s, --static-dir DIR | 정적 파일 디렉터리 (기본값: static) |
| --delete | 사용하지 않는 파일 삭제 (확인 프롬프트 표시) |
| -f, --force | 삭제 시 확인 프롬프트 생략 (`--json`에서 삭제하려면 필수) |
| -j, --json | 결과를 JSON으로 출력 |
| -h, --help | 도움말 표시 |

## 스캔 대상

**에셋 소스:**
- `static/` 디렉터리의 파일 (이미지, CSS, JS, 폰트, 미디어 등)
- 콘텐츠 디렉터리에 함께 있는 에셋 (`.md` 파일 옆의 마크다운 이외 파일)

**참조 소스:**
- 모든 콘텐츠 파일 (`.md`, `.markdown`)
- 모든 템플릿 파일 (`.html`, `.css`, `.js`)

**지원 에셋 확장자:**
이미지(png, jpg, jpeg, gif, svg, webp, avif, ico, bmp, tiff), 스타일시트(css), 스크립트(js), 폰트(woff, woff2, ttf, eot, otf), 미디어(mp4, webm, ogg, mp3, wav), 문서(pdf, zip).

## 출력 예시

```
hwaro: unused-assets static
total: 24
referenced: 20
unused: 4
unused files:
    - static/old-logo.png
    - static/unused-banner.jpg
    - content/blog/my-post/draft-image.png
    - static/deprecated.css
    [info] dynamic references (e.g. template variables) may cause false positives
found: 4 unused assets
```

색상 터미널에서는 정렬된 행으로 구성된 `hwaro unused-assets` 영수증과
`✦ found` 결과 줄로 표시됩니다(모두 참조 중이면 `found: no unused assets`).
`--delete`를 쓰면 확인 후 결과 줄이 `deleted: N files`로 바뀌고, 취소하면
`cancelled: no files deleted`가 됩니다.

## JSON 출력

```json
{
  "unused_files": [
    "static/old-logo.png",
    "static/unused-banner.jpg"
  ],
  "total_assets": 24,
  "referenced_count": 22,
  "unused_count": 2
}
```

## 제한 사항

- 템플릿 변수 등으로 동적으로 참조되는 에셋 파일명(예: `{{ page.image }}`)은 감지되지 않아 오탐(false positive)이 생길 수 있습니다.
- 감지는 파일명 매칭 기반입니다 — 서로 다른 디렉터리의 두 파일이 이름이 같으면, 실제로는 하나만 쓰이더라도 둘 다 참조된 것으로 간주될 수 있습니다.
