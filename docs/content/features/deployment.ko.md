+++
title = "배포 명령"
description = "hwaro deploy의 배포 대상 설정"
weight = 26
+++

Hwaro에는 빌드된 사이트를 설정된 대상으로 동기화하는 `hwaro deploy` 명령이 내장되어 있습니다. 로컬 디렉터리, 클라우드 스토리지는 물론 사용자 지정 명령으로 어떤 도구든 연결할 수 있습니다.

```toml
[deployment]
source_dir = "public"

[[deployment.targets]]
name = "prod"
url = "file:///var/www/mysite"

[[deployment.targets]]
name = "s3"
url = "s3://my-bucket"
# command 없이 URL 스킴에서 자동 생성 (aws CLI 필요)

[[deployment.targets]]
name = "gcs"
url = "gs://my-bucket"
# 자동 생성 (gsutil 필요)
```

**지원 URL 스킴:**

| 스킴 | 자동 명령 | 필요 도구 |
|--------|-------------|----------|
| `file://` | 로컬 디렉터리 동기화 | — |
| `s3://` | `aws s3 sync` | AWS CLI |
| `gs://` | `gsutil -m rsync` | Google Cloud SDK |
| `az://` | `az storage blob sync` | Azure CLI |

언제든 `command` 필드에 명령을 직접 지정해 완전히 제어할 수도 있습니다.

```bash
hwaro deploy              # 기본 대상으로 배포
hwaro deploy --target s3  # 특정 대상으로 배포
hwaro deploy --dry-run    # 변경 사항 미리 보기
```

전체 설정(대상, 매처, 옵션)과 플랫폼별 가이드는 [배포](/ko/deploy/) 섹션을 참고합니다.
