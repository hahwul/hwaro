+++
title = "스트리밍 빌드"
description = "페이지를 배치 단위로 처리해 메모리 사용량을 줄입니다"
weight = 14
toc = true
+++

스트리밍 빌드는 Render 단계에서 페이지를 배치 단위로 처리해 대규모 사이트의 메모리 사용량을 줄입니다. 렌더링된 HTML 전체를 한 번에 메모리에 들고 있는 대신, 배치 하나를 렌더링해 디스크에 쓰고 해제한 뒤 다음 배치로 넘어갑니다.

```bash
hwaro build --stream
```

## 사용 시점

대부분의 사이트는 기본 빌드 모드로 충분합니다. 스트리밍 빌드는 다음 상황에서 유용합니다.

- 페이지가 수천 개인 사이트
- 빌드 과정의 메모리 사용량이 너무 큰 경우
- 메모리가 제한된 환경(CI, 컨테이너, 작은 VM)에서 빌드하는 경우

## 사용 방법

### `--stream` 플래그

기본 배치 크기 500페이지로 스트리밍을 활성화합니다.

```bash
hwaro build --stream
```

### `--memory-limit` 플래그

메모리 한도를 지정하면 Hwaro가 최적의 배치 크기를 자동으로 계산합니다.

```bash
hwaro build --memory-limit 512M
hwaro build --memory-limit 2G
```

`G`(기가바이트), `M`(메가바이트), `K`(킬로바이트) 접미사를 사용할 수 있습니다. 배치 크기는 페이지당 약 50KB로 잡는 휴리스틱으로 계산합니다.

### 환경 변수

CLI 플래그가 없을 때의 대체값으로 `HWARO_MEMORYLIMIT`을 설정할 수 있습니다.

```bash
export HWARO_MEMORYLIMIT=1G
hwaro build
```

CLI `--memory-limit` 플래그가 항상 환경 변수보다 우선합니다.

둘 중 하나라도 설정하면 `hwaro build`가 평소에 적용하는 GC 힙 사전 확보(`GC_INITIAL_HEAP_SIZE=256M`)도 함께 꺼집니다. 미리 확보한 힙은 그 하한 아래로 다시 줄어들지 않기 때문에, 지정한 메모리 한도와 반대로 작용하기 때문입니다.

### 플래그 조합

`--stream`과 `--memory-limit`은 함께 쓸 수 있습니다. `--memory-limit`이 지정되면 `--stream` 여부와 관계없이 배치 크기는 이 값으로 결정됩니다.

```bash
hwaro build --stream --memory-limit 512M
```

## 플래그 상호작용

| `--stream` | `--memory-limit` | `HWARO_MEMORYLIMIT` | 결과 |
|---|---|---|---|
| - | - | - | 일반 빌드 |
| 예 | - | - | 스트리밍, batch=500 |
| - | 2G | - | 스트리밍, batch≈20000 |
| - | - | 1G | 스트리밍, batch≈10000 |
| 예 | 512M | - | 스트리밍, batch≈5000 |
| - | 2G | 1G | CLI 우선(2G) |

## 동작 방식

1. Render 단계에서 페이지를 배치로 나눕니다
2. 각 배치는 일반 빌드와 동일한 병렬/순차 로직으로 렌더링됩니다
3. 배치를 디스크에 쓴 뒤 `page.content`를 비워 메모리를 해제합니다 — 단, 이후 단계에서 다시 읽지 않을 때만 그렇습니다(아래 참고)
4. 가비지 컬렉터를 호출해 해제된 메모리를 회수합니다
5. Generate 단계(피드, 사이트맵, 검색 인덱스)가 끝나면 `page.raw_content`도 비웁니다

### `page.content`를 유지하는 경우

검색 인덱스와 모든 피드는 Generate 단계에서 각 페이지의 렌더링된 본문을 다시
읽습니다. 이때 본문을 이미 해제했다면 생성기는 `raw_content`를 마크다운으로만
다시 렌더링한 결과를 쓰게 되고 — 숏코드 확장도, `@/` 링크 해석도, 앵커 링크도,
`base_path` 접두사도 없습니다 — `search.json`과 `rss.xml`에 날것의
`{% shortcode %}` 마크업과 깨진 링크가 실립니다.

그래서 다음 중 하나라도 켜져 있으면 3번 단계를 건너뜁니다.

- `[search] enabled`
- `[feeds] enabled`
- `feed = true`인 `[[taxonomies]]`
- `_index.md`에 `generate_feeds`를 설정한 섹션

모두 꺼져 있으면 기존처럼 배치마다 해제합니다. 어느 쪽이든 렌더링 자체는 여전히
배치 단위로 진행되므로 배치별 최대 사용량(워커 템플릿 출력, Crinja 값 캐시)은
계속 제한됩니다.

## 출력

빌드 출력은 스트리밍 사용 여부와 관계없이 **동일**합니다. 스트리밍은 빌드 중 메모리 사용량에만 영향을 줍니다.

> v0.20.1까지의 릴리스에서는 그렇지 않았습니다. 검색 인덱스나 피드를 쓰는
> 사이트에서 `--stream`은 확장되지 않은 숏코드와 해석되지 않은 `@/` 링크를
> `search.json`과 모든 피드에 실었습니다. 해당 사이트는 업그레이드 후 한 번 다시
> 빌드해 주세요.

`--verbose`를 붙이면 배치 진행 상황을 볼 수 있습니다.

```bash
hwaro build --stream --verbose
```

```
Building site...
  Streaming mode enabled (batch size: 500)
  ...
  Streaming batch 1 (500 pages)
  Streaming batch 2 (500 pages)
  Streaming batch 3 (234 pages)
  ...
```

## 함께 보기

- [CLI](/ko/start/cli/) — 빌드 플래그 전체 목록
- [빌드 훅](/ko/features/build-hooks/) — 빌드 전후 사용자 정의 명령 실행
