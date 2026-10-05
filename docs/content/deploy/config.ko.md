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

Windows에서는 `file://` URL에 드라이브 경로를 씁니다: `file:///C:/www/site`(또는
`file://C:/www/site`). `path = "C:\\www\\site"`도 동작합니다.

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

**동기화가 건드리지 않는 것.** 대상 쪽에서는 `.well-known/`을 제외한 숨김
디렉터리를 탐색하지 않으므로 그 안의 내용은 삭제되지 않으며, `.git` 항목은
항상 유지됩니다. 따라서 `git worktree`나 서브모듈 체크아웃인 대상(흔한
gh-pages 구성)이 저장소에서 떨어져 나가지 않습니다. 소스 쪽에서는 빌드가
만든 숨김 디렉터리(`.well-known/`, `.circleci/` 등)를 모두 배포하되, 버전 관리
메타데이터(`.git/`, `.svn/`, `.hg/`, `.bzr/`)는 제외합니다. 빈 디렉터리는
동기화 자신의 삭제로 비게 된 경우에만 제거하며, 동기화가 고르지 않은 빈
디렉터리(예: `include` 밖의 `uploads/`)는 그대로 둡니다.

**파일 ↔ 디렉터리 전환.** `strip_index_html`을 켜거나 끄면 각 페이지가 파일
`foo`와 `index.html`을 담은 디렉터리 `foo/` 사이에서 바뀝니다. 걸리는 항목이
낡은 것이면(안의 내용이 어차피 모두 삭제 대상이면) 새 항목을 복사하기 전에
먼저 제거하고, 계획에는 삭제로 표시됩니다. 동기화가 유지하는 내용(숨김
디렉터리, `include`/`exclude` 밖의 경로)이 들어 있으면 아무것도 쓰기 전에
배포를 거부합니다.

**커맨드 타깃**은 `sh`(Windows에서는 `cmd.exe`)로 실행합니다. 도구가 실행되는 동안 stderr를 포함한
출력이 실시간으로 표시됩니다. 대화형 터미널에서는 도구가 입력(로그인이나 확인
프롬프트)을 읽을 수 있고, 파이프·CI·`--quiet`·`--json` 실행에서는 stdin이
닫힙니다. 명령의 환경에는 `HWARO_DEPLOY_TARGET`, `HWARO_DEPLOY_URL`,
`HWARO_DEPLOY_SOURCE`도 들어갑니다. 이 값들은 명령이 실행하는 스크립트에서
읽으세요. config.toml은 로드할 때 `$VAR`와 `${VAR}`를 직접 확장하고, 그 시점에
설정되지 않은 변수마다 경고합니다.

플레이스홀더 값은 작은따옴표로 감싸지므로, 플레이스홀더가 단독으로 쓰인
자리(`rsync -a {source}/ host:`)에서는 하나의 안전한 단어로 남습니다.
플레이스홀더를 직접 따옴표로 감싸지 마세요(`"{source}"`). 그러면 이 보호가
풀리므로, hwaro는 확장된 값에서 셸 메타문자를 검사하고 발견하면 확인을
요청합니다.

Windows에서는 명령이 `sh` 대신 `cmd.exe`로 실행됩니다. `cmd.exe`에는 작은따옴표가
없으므로 플레이스홀더 값은 큰따옴표로 감싸지고, `{source}`는 `\` 구분자를
씁니다. `cmd.exe`는 큰따옴표 안의 `%NAME%`도 확장하므로 Windows에서는 `%`와
`^`도 메타문자로 취급합니다.

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| name | string | — | 타깃 식별자(고유해야 합니다. 중복되면 경고하고 첫 번째만 사용) |
| url | string | — | 대상 URL (`file://`, `s3://`, `gs://`, `az://`) |
| path | string | — | 로컬 디렉터리로 배포할 때 쓰는 `url` 별칭 (`path = "~/public"`, `~`는 확장됨) |
| include | string | — | 포함할 파일의 글롭 패턴 (아래 참고) |
| exclude | string | — | 제외할 파일의 글롭 패턴 (아래 참고) |
| strip_index_html | bool | false | URL에서 `index.html` 제거 |
| command | string | — | 사용자 지정 명령(자동 생성보다 우선) |

사용자 지정 명령에서는 플레이스홀더를 사용할 수 있습니다:

| 플레이스홀더 | 설명 |
|-------------|-------------|
| `{source}` | 소스 디렉터리(기본값: `public`) |
| `{url}` | 타깃 URL |
| `{target}` | 타깃 이름 |

그 밖의 `{name}` 토큰은 오타로 보고 명령을 실행하기 전에 거부합니다. 앞에
`$`가 붙은 `{`는 셸에 맡깁니다.

`include`와 `exclude`는 소스 디렉터리 기준 상대 경로(예:
`blog/post/index.html`)에 맞추는 글롭입니다. `*`는 `/`를 넘지 않으므로 깊이와
상관없이 맞추려면 `**/`를 쓰세요. `exclude = "**/*.map"`은 모든 위치의 소스맵을
빼지만 `*.map`은 최상위만 맞춥니다. `strip_index_html`을 쓰면 잘린 페이지
`blog/post`는 소스 이름 `blog/post/index.html`로도 판단하며, 어느 쪽 이름이든
제외되면 이미 배포된 그 페이지를 낡은 것으로 보고 지우지 않습니다.

## 매처

패턴 매처로 파일별 배포 설정을 지정합니다:

```toml
[[deployment.matchers]]
pattern = "^.+\\.html$"
cache_control = "max-age=0, no-cache"
gzip = true

[[deployment.matchers]]
pattern = "^assets/.+\\.(css|js)$"
cache_control = "max-age=31536000, immutable"
force = true
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| pattern | string | — | 소스 기준 상대 경로와 대상 이름에 매칭할 정규식 (`strip_index_html`에서는 둘이 다름) |
| force | bool | false | 대상에 동일한 파일이 있어도 매칭된 파일을 항상 복사 |
| cache_control | string | — | 매칭된 파일의 `Cache-Control` 헤더 (클라우드 대상) |
| content_type | string | — | 매칭된 파일의 `Content-Type` 헤더 (클라우드 대상) |
| gzip | bool | false | gzip으로 압축해 `Content-Encoding: gzip`으로 업로드(클라우드), 또는 `.gz` 파일을 옆에 생성(로컬) |

`force`는 패턴이 매칭되는 모든 매처에서 적용됩니다. 메타데이터 키
(`cache_control`, `content_type`, `gzip`)는 이 중 하나라도 설정하고 파일에
매칭되는 매처 중 설정 순서상 **첫 번째** 매처가 세 값을 모두 정합니다.
매처끼리 값을 합치지 않으므로 구체적인 패턴을 일반적인 패턴보다 앞에 둡니다.

### 클라우드 대상 (`s3://`, `gs://`, `az://`)

기본 동기화가 끝나면 매칭된 파일을 클라우드 CLI의 플래그로 헤더와 함께 다시
업로드합니다:

| 대상 | 명령 |
|--------|---------|
| `s3://` | `aws s3 cp FILE s3://… --cache-control … --content-type … --content-encoding gzip` |
| `gs://` | `gsutil -h "Cache-Control:…" -h "Content-Type:…" cp -Z FILE gs://…` |
| `az://` | `az storage blob upload --container-name … --file FILE --name … --overwrite --content-cache-control … --content-type … --content-encoding gzip` |

`gzip = true`일 때 `gsutil`은 `-Z`로 직접 압축합니다. `aws`와 `az`는
hwaro가 같은 이름의 임시 파일로 압축해 그 파일을 업로드합니다.
`--dry-run`은 예정된 업로드를 보여 주고, `--dry-run --json`은 파일마다
`headers` 객체를 담은 `upload` 항목을 추가합니다. 매칭된 파일은 배포할
때마다 다시 업로드됩니다.

### 로컬 디렉터리 대상 (`file://`, `path`)

`gzip = true`이면 매칭된 파일마다 미리 압축한 `<file>.gz`를 옆에
만듭니다(nginx `gzip_static`, Caddy `precompressed`용). `.gz` 파일이 없거나
원본보다 오래된 경우에만 다시 씁니다. 소스에 이미 `<file>.gz`가 있으면 그
파일을 그대로 배포합니다. 원본이 배포되는 동안 `.gz` 파일은 낡은 파일로
삭제되지 않습니다. 페이지가 사라지면 `.gz` 파일도 함께 삭제되며
`max_deletes`에 포함되지 않습니다.

로컬 복사본에는 HTTP 헤더가 없으므로 `cache_control`과 `content_type`을
설정하면 경고가 출력됩니다. 이 헤더는 웹 서버에서 설정합니다.

### 사용자 `command` 대상

`command`를 직접 지정한 대상에는 매처가 적용되지 않으며, 메타데이터 키를
설정하면 경고가 출력됩니다. 헤더는 명령에서 직접 지정합니다.

## 함께 보기

- [CLI](/ko/start/cli/) — 배포 명령줄 옵션 전체
- [배포 명령](/ko/features/deployment/) — 간단한 개요
