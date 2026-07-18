+++
title = "배포 설정"
description = "배포 타깃, 매처, 옵션 설정"
weight = 1
toc = true
+++

`hwaro deploy` 명령이 사용할 배포 타깃을 `config.toml`에 설정합니다.

## 전역 옵션

```toml
[deployment]
target = "prod"
source_dir = "public"
confirm = false
dry_run = false
max_deletes = 256
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| target | string | — | 기본으로 배포할 타깃 이름 |
| source_dir | string | "public" | 빌드된 사이트가 있는 디렉터리 |
| confirm | bool | false | 배포 전 확인 프롬프트 표시 |
| dry_run | bool | false | 실제 변경 없이 배포될 내용만 표시 |
| force | bool | false | 변경 사항이 없어도 강제로 배포 |
| max_deletes | int | 256 | 파일 삭제 개수의 안전 한도(음수를 지정하면 한도 해제) |

## 타깃

배포 타깃을 하나 이상 정의합니다:

```toml
[[deployment.targets]]
name = "prod"
url = "file:///var/www/mysite"

[[deployment.targets]]
name = "s3"
url = "s3://my-bucket"
# 자동 생성: aws s3 sync {source}/ s3://my-bucket --delete

[[deployment.targets]]
name = "custom"
url = "s3://my-bucket"
command = "aws s3 sync {source}/ {url} --delete --exclude '.git/*'"
# 사용자 지정 명령이 자동 생성보다 우선합니다
```

**URL 스킴별 자동 생성 명령:**

| 스킴 | 명령 | 필요 도구 |
|--------|---------|----------|
| `file://` | 내장 디렉터리 동기화 | — |
| `s3://` | `aws s3 sync {source}/ {url} --delete` | AWS CLI |
| `gs://` | `gsutil -m rsync -r -d {source}/ {url}` | Google Cloud SDK |
| `az://` | `az storage blob sync --source {source} --container <container> [--destination <path>]` | Azure CLI |

`az://container/sub/dir` 형태의 URL에서는 경로가 컨테이너 내부의 `--destination` 접두사가 됩니다.

`command` 필드를 지정하면 항상 자동 생성보다 우선합니다.

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| name | string | — | 타깃 식별자 |
| url | string | — | 대상 URL (`file://`, `s3://`, `gs://`, `az://`) |
| include | string | — | 포함할 파일의 글롭 패턴 |
| exclude | string | — | 제외할 파일의 글롭 패턴 |
| strip_index_html | bool | false | URL에서 `index.html` 제거 |
| command | string | — | 사용자 지정 명령(자동 생성보다 우선) |

사용자 지정 명령에서는 플레이스홀더를 사용할 수 있습니다:

| 플레이스홀더 | 설명 |
|-------------|-------------|
| `{source}` | 소스 디렉터리(기본값: `public`) |
| `{url}` | 타깃 URL |
| `{target}` | 타깃 이름 |

## 매처

패턴 매처로 파일별 배포 설정을 지정합니다:

```toml
[[deployment.matchers]]
pattern = "^.+\\.html$"
force = true
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| pattern | string | — | 파일 경로에 매칭할 정규식 패턴 |
| force | bool | false | 대상에 동일한 파일이 있어도 매칭된 파일을 항상 복사 |
| cache_control | string | — | 예약됨 — 내장 동기화에서는 적용되지 않음(아래 참고) |
| content_type | string | — | 예약됨 — 내장 동기화에서는 적용되지 않음(아래 참고) |
| gzip | bool | false | 예약됨 — 내장 동기화에서는 적용되지 않음(아래 참고) |

내장 동기화는 파일을 복사하고 외부 CLI를 실행할 뿐 오브젝트 스토어 API와 직접 통신하지 않으므로, 실제로 반영되는 옵션은 `force`뿐입니다. `cache_control`, `content_type`, `gzip`을 설정하면 경고가 출력됩니다. 헤더와 압축은 호스트나 CDN에서 설정합니다.

## 함께 보기

- [CLI](/ko/start/cli/) — 배포 명령줄 옵션 전체
- [배포 명령](/ko/features/deployment/) — 간단한 개요
