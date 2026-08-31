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

`max_deletes`는 **내장** `file://` 동기화에만 적용됩니다. 커맨드 타깃
(`s3://`, `gs://`, `az://`, 또는 명시적 `command`)은 외부 도구가 자체
플래그로 삭제하므로 hwaro가 미리 개수를 셀 수 없습니다.

소스 디렉터리가 비어 있거나, `include`/`exclude`가 아무 파일도 고르지
못했는데 대상에는 파일이 남아 있는 경우에도 배포를 거부합니다. 이 조합은
대부분 "사이트를 빌드하지 않았다"는 뜻이고, 그대로 진행하면 대상을 통째로
지우게 됩니다. 의도적으로 비우려면 `--force`를 넘기세요. `{source}`를 쓰지 않는
`command` 타깃은 소스를 읽지 않으므로 제외됩니다.

`.hwaro-dev` 마커가 있는 소스 디렉터리도 거부합니다. 이 마커는 해당
디렉터리가 `hwaro serve` 출력이라는 뜻이며, 모든 링크에 개발 서버의
`base_url`(예: `http://127.0.0.1:3000`)이 박혀 있습니다. `hwaro build`를
실행해 그 출력을 배포하세요. 우회 플래그는 없습니다(마커 파일을 직접
지우는 것이 의도적인 탈출구입니다).

`workers`는 앞으로를 위해 파싱만 하고 적용하지 않습니다. 내장 동기화는
순차적으로 복사하고, 커맨드 타깃은 각자 동시성을 관리합니다. 값을 지정하면
경고가 출력됩니다.

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

URL 스킴으로 시작하는 값은 로컬 경로로 취급하지 않습니다. 따라서 슬래시를
하나 빠뜨린 오타(`s3:/bucket`)는 `s3:`라는 디렉터리를 조용히 만드는 대신
지원하지 않는 스킴 오류로 실패합니다. `include`, `exclude`,
`strip_index_html`은 내장 `file://` 동기화에만 적용되며, 커맨드 타깃에서는
외부 도구가 소스 트리 전체를 받기 때문에 경고만 출력합니다.

**로컬 디렉터리 동기화와 심볼릭 링크.** 내장 동기화는 모든 쓰기를 대상
디렉터리 안에 가둡니다. 파일이나 디렉터리가 있어야 할 자리의 링크는 실제
파일/디렉터리로 교체하고, 소스에 대응하는 항목이 없는 링크는 제거합니다.
어느 쪽도 링크를 따라가서 읽거나 지우지 않으므로, 대상 밖에 있는 내용은
절대 건드리지 않습니다.

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| name | string | — | 타깃 식별자(고유해야 합니다. 중복되면 경고하고 첫 번째만 사용) |
| url | string | — | 대상 URL (`file://`, `s3://`, `gs://`, `az://`) |
| path | string | — | 로컬 디렉터리로 배포할 때 쓰는 `url` 별칭 (`path = "~/public"`, `~`는 확장됨) |
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
