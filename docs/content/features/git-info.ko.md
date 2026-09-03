+++
title = "Git 메타데이터"
description = "각 페이지의 커밋 이력을 page.git으로 노출하고 lastmod를 유도"
weight = 12
+++

빌드마다 각 콘텐츠 파일의 커밋 이력을 한 번 읽어 템플릿과 SEO 출력에 노출합니다. Hugo의 `enableGitInfo`와 같은 기능입니다. `[git]`을 켜면 프론트 매터에 `updated`가 없는 페이지는 최신 커밋 시각을 받으므로 사이트맵 `<lastmod>`, 피드 `<updated>`, JSON-LD `dateModified`가 파일이 실제로 바뀐 시점을 반영합니다.

## 설정

`config.toml`에서 옵트인합니다.

```toml
[git]
enabled = true
use_lastmod = true   # 프론트 매터에 updated가 없으면 page.updated ← 최신 커밋
use_date = false     # 프론트 매터에 date가 없으면 page.date ← 첫 커밋
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| enabled | bool | false | `content/` 파일의 git 메타데이터 수집 |
| use_lastmod | bool | true | 프론트 매터에 `updated`가 없으면 파일의 최신 커밋으로 `page.updated` 설정 |
| use_date | bool | false | 프론트 매터에 `date`가 없으면 파일의 첫 커밋으로 `page.date` 설정 |

프론트 매터가 항상 우선합니다. 폴백은 파일이 비워 둔 필드만 채웁니다.

## 동작 방식

1. 빌드가 `content/` 전체에 대해 `git log`를 **한 번** 실행하고(페이지마다 프로세스를 띄우지 않음) 모든 경로를 커밋에 매핑합니다. 5,200페이지 테스트 저장소에서 수집 단계 전체가 약 50ms 걸렸습니다.
2. 소스 파일에 비병합 커밋이 하나라도 있는 페이지는 `page.git` 객체를 갖습니다.
3. `use_lastmod` / `use_date`가 비어 있는 `updated` / `date`를 채우면 사이트맵, 피드, JSON-LD, OpenGraph, `sort_by = "date"` 등 하위 모든 곳이 템플릿 수정 없이 git에서 유도한 값을 봅니다.

`hwaro serve`는 파일을 저장할 때마다가 아니라 전체 재빌드마다 한 번 이력을 수집합니다. `hwaro build --cache`는 각 페이지의 커밋 ID와 타임스탬프를 캐시 키에 포함하므로, 새 커밋 후의 웜 재빌드는 그 커밋이 건드린 페이지(와 이를 보여주는 목록)만 정확히 다시 렌더링합니다.

## 템플릿 변수

| 변수 | 타입 | 설명 |
|----------|------|-------------|
| page.git | Object? | 페이지에 이력이 없으면 `nil`(아래 참고) |
| page.git.hash | String | 파일을 건드린 최신 비병합 커밋의 전체 커밋 ID |
| page.git.short_hash | String | `hash`의 앞 7자 |
| page.git.lastmod | Time | 최신 커밋의 작성자 날짜 |
| page.git.first_commit | Time | 파일을 건드린 모든 커밋 중 가장 이른 작성자 날짜 |
| page.git.author_name | String | 최신 커밋의 작성자 이름 |
| page.git.author_email | String | 최신 커밋의 작성자 이메일 |

`lastmod`와 `first_commit`은 실제 시간 값(작성자의 UTC 오프셋 유지)이므로 `date` 필터로 바로 포맷할 수 있습니다. 목록에서 순회하는 페이지(`section.pages`, `site.pages`, 택소노미 항목)에서도 같은 객체를 쓸 수 있습니다.

```jinja
{% if page.git %}
<p class="meta">
  Last updated {{ page.git.lastmod | date(format="%Y-%m-%d") }}
  by {{ page.git.author_name }}
  (<a href="https://github.com/you/site/commit/{{ page.git.hash }}">{{ page.git.short_hash }}</a>)
</p>
{% endif %}
```

다음 경우에는 `page.git`이 `nil`이고 폴백도 적용되지 않습니다.

- 아직 커밋되지 않은(새로 만든 또는 추적되지 않는) 파일
- `[[content.generate]]`로 생성된 페이지
- 생성된 택소노미 및 목록 페이지
- 사이트가 git 저장소 안에 있지 않은 경우의 모든 페이지

## 번들, 번역, 이름 변경

- 페이지 번들(`posts/hello/index.md` + 에셋)은 Markdown 파일 기준이므로 에셋만 커밋해도 `lastmod`는 움직이지 않습니다.
- 각 번역본(`hello.md`, `hello.ko.md`)은 별도 파일이며 이력도 별도입니다.
- 이름 변경은 **따라가지 않습니다**. 이름을 바꾼 파일의 이력은 이름 변경 커밋에서 다시 시작하므로 `first_commit`(그리고 `use_date`일 때 `page.date`)은 이름 변경 날짜가 됩니다.

## 우아한 성능 저하

이 기능은 빌드를 중단시키지 않습니다. 아래 상황은 각각 경고 한 번을 남기고 `page.git`을 비워 둡니다.

| 상황 | 결과 |
|-----------|--------|
| `PATH`에 `git` 바이너리가 없음 | 경고, git 메타데이터 없음 |
| `content/`가 저장소 안에 없음 | 경고, git 메타데이터 없음 |
| 얕은 클론(`--depth N`) | 클론 깊이보다 오래된 파일의 `lastmod`/`first_commit`이 틀릴 수 있다는 경고, 메타데이터는 계속 사용 |

대부분의 CI 체크아웃은 기본이 얕은 클론입니다. 날짜가 정확하도록 전체 이력을 가져오세요.

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0
```

## 함께 보기

- [데이터 모델](/ko/templates/data-model/) — 전체 `page` 객체
- [SEO](/ko/features/seo/), [구조화 데이터](/ko/features/structured-data/) — `page.updated`가 출력되는 곳
- [증분 빌드](/ko/features/incremental-build/) — `--cache`가 재렌더링 대상을 정하는 방식
