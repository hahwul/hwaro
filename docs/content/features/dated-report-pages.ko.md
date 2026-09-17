+++
title = "날짜별 리포트 페이지"
description = "실전 예제: 하나의 JSON API로 /reports/2026/09/ 차트 페이지 만들기"
weight = 24
toc = true
+++

세 가지 기능을 함께 쓰는 실전 예제입니다. JSON API 하나가 월별 페이지가 되고,
`/reports/2026/09/` 같은 주소로 공개되며, 각 페이지는 자기 달의 차트를
렌더링합니다. 데이터 파일은 커밋하지 않고, `config.toml`은 한 번만 작성합니다.
새 달이 생기는 이유는 API가 레코드를 하나 더 반환했기 때문이지, 누군가 사이트를
수정했기 때문이 아닙니다.

구성 요소는 [원격 데이터](/ko/features/remote-data/)(페이로드 가져오기),
[콘텐츠 생성](/ko/features/content-generation/)(레코드를 페이지로 만들기),
그리고 `[permalinks]` 토큰 패턴(URL 모양 정하기) 세 가지입니다. 각각은 자체
문서가 있고, 이 문서는 셋을 함께 연결하는 방법을 보여 줍니다.

## 소스 하나, 배열 하나

엔드포인트가 월별 레코드 하나씩 담긴 배열 하나를 반환하게 하세요. 각 레코드는
식별자, 표시용 레이블, 날짜, 그리고 자기 데이터 포인트를 가집니다.

```json
[
  {
    "id": "2026-09",
    "label": "September 2026",
    "date": "2026-09-01",
    "summary_md": "가입은 유지되고 이탈은 세 달째 줄었습니다.",
    "datapoints": [
      {"day": "2026-09-01", "signups": 412, "churn": 18},
      {"day": "2026-09-08", "signups": 455, "churn": 15},
      {"day": "2026-09-15", "signups": 501, "churn": 12}
    ]
  },
  {
    "id": "2026-08",
    "label": "August 2026",
    "date": "2026-08-01",
    "summary_md": "출시 직후의 급등이 가라앉은 조용한 달이었습니다.",
    "datapoints": [{"day": "2026-08-04", "signups": 380, "churn": 22}]
  }
]
```

중첩은 키가 아니라 **페이로드 안에** 둡니다. 의도적인 선택입니다.
`[[data.remote]]`의 `key`에는 영문자, 숫자, `_`, `-`만 쓸 수 있어서
`data/reports/2026/09.json` 같은 트리에 대응하는 원격 키가 존재하지 않습니다.

```toml
[[data.remote]]
key = "reports.2026"   # Error [HWARO_E_CONFIG]: key may contain only
                       # letters, digits, '_' and '-'
```

로컬 `data/` 하위 디렉터리는 중첩되지만(`data/reports/2026.json` →
`site.data.reports.2026`), 원격 키는 캐시 파일 이름이기도 하므로 평평합니다.
API를 `reports_2026_09`, `reports_2026_10` …으로 나눠도 동작은 하지만, 그러면
매달 `[[data.remote]]` 항목 하나와 `[[content.generate]]` 규칙 하나를 새로
추가해야 합니다. 이 구성이 피하려는 바로 그 매달의 설정 수정입니다. 배열 하나,
키 하나, 규칙 하나로 충분합니다.

## config.toml

한 번만 쓰는 세 블록입니다.

```toml
[[data.remote]]
key = "reports"                        # site.data.reports
url = "https://api.example.com/reports"
cache = "1h"                           # 신선한 페이로드는 빌드 간 재사용
on_error = "warn-and-use-cache"        # 불안정한 API가 빌드를 깨뜨리지 않도록

[[content.generate]]
source = "reports"                     # 배열 전체
section = "reports"                    # reports 섹션으로 페이지 생성
slug = "id"                            # "2026-09"
title = "label"                        # "September 2026"
date = "date"                          # "2026-09-01" — 패턴이 요구함
body = "summary_md"                    # 선택: 마크다운 본문

[permalinks]
"reports" = "/reports/:year/:month/"   # /reports/2026/09/
```

몇 가지는 짚고 넘어갈 만합니다.

- `source = "reports"`는 배열 자체를 가리킵니다. 중첩된 배열은 점 표기 경로를
  씁니다(`"reports.months"`). 배열이 아니면 빌드가 실패합니다.
- `slug = "id"`는 슬러그화되며(`2026-09`은 그대로), 페이지의 **콘텐츠 경로**
  `content/reports/2026-09.md`만 결정합니다. 공개 URL은 퍼머링크 패턴이
  정합니다.
- 여기서 `date`는 선택이 아닙니다. `:year`와 `:month`는 페이지 날짜에서
  확장되며, 날짜 없는 레코드는 이름을 지목하며 빌드를 실패시킵니다.

  ```
  Error [HWARO_E_CONTENT]: reports/2026-09.md matches [permalinks] rule
  "reports" (pattern '/reports/:year/:month/') which requires a date, but the
  page has none.
  ```

- 생성 페이지도 작성 페이지와 같은 게시 규칙을 따릅니다. 미래 날짜 레코드는 그
  날짜가 될 때까지 빌드에 들어오지 않습니다. 각 레코드를 그 달 1일로 잡아 두면
  달이 시작되는 순간 공개됩니다.

`:year`, `:month`, `:day`는 0을 채우는 날짜 토큰입니다. 전체 토큰 목록은
[설정 › 토큰 패턴](/ko/start/config/#토큰-패턴)에 있습니다. 토큰은 경로 세그먼트
하나 전체여야 하므로 `/reports/:year-:month/`는 패턴이 아니라 설정 오류입니다.

## 한 달에 레코드 하나

`/reports/:year/:month/`에는 `:slug` 세그먼트가 없으므로 달 자체가 페이지의
정체성입니다. 같은 달에 들어가는 레코드가 둘이면 URL이 같아지고, Hwaro는
경고한 뒤 하나만 씁니다.

```
[WARN] Duplicate output path '/reports/2026/09/' — 'reports/2026-09.md'
collides with 'reports/2026-09-late.md' and is not written
```

API가 한 달에 여러 레코드를 낼 수 있다면 API 쪽에서 집계하거나, 패턴에
`:slug`를 다시 넣으세요(아래 [변형](#변형) 참고).

## 차트 템플릿

섹션에 템플릿을 지정하면 그 섹션의 생성 페이지가 모두 그 템플릿으로
렌더링됩니다.

```toml
# content/reports/_index.md
+++
title = "월간 리포트"
description = "가입과 이탈, 달마다 한 페이지"
sort_by = "date"
page_template = "report"
+++

리포트는 매달 1일에 공개됩니다.
```

`templates/report.html`은 그 달의 데이터 포인트를 `page.extra.item`에서
읽습니다. 소스 레코드 전체가 그대로 들어오므로 규칙에서 필드를 하나씩 매핑할
필요가 없습니다.

```jinja
<h1>{{ page.title | e }}</h1>

{% if page.synthesized %}
<script id="report-data" type="application/json">
  {{ page.extra.item.datapoints | jsonify }}
</script>
<canvas id="report-chart"></canvas>
<script>
  const points = JSON.parse(document.getElementById("report-data").textContent);
  new Chart(document.getElementById("report-chart"), {
    type: "line",
    data: {
      labels: points.map(p => p.day),
      datasets: [{ label: "Signups", data: points.map(p => p.signups) }]
    }
  });
</script>
{% endif %}

{{ content }}
```

두 가지가 이 템플릿을 안전하게 만듭니다.

- `page.synthesized`는 생성 페이지에서만 `true`입니다. `page_template`은 섹션의
  모든 페이지에 적용되고, 여기에는 `item`이 없는 작성 페이지
  `content/reports/notes.md`도 포함되므로 `page.extra.item` 접근은 이 값으로
  감싸세요.
- `jsonify`는 실제 값 트리를 직렬화하고 `</`를 이스케이프하므로, 데이터가
  `<script>` 요소를 벗어날 수 없습니다.

차트 라이브러리는 무엇을 쓰든 방식이 같습니다. Hwaro의 몫은 각 페이지에 자기
행을 건네주는 데서 끝납니다. 배열 전체는 `site.data.reports`로도 남아 있으므로,
같은 한 번의 요청으로 전체 기간 개요 차트도 그릴 수 있습니다.

## 빌드 결과

```
$ hwaro build
  Generated 2 page(s) from data.reports
  ...
  built: 3 content pages

public/reports/index.html            # 섹션 목록
public/reports/2026/08/index.html
public/reports/2026/09/index.html
```

섹션 인덱스가 달 목록을 보여 주는 이유는 생성 페이지가 일급 콘텐츠이기
때문입니다. `sort_by = "date"`는 최신순으로 정렬하고, `reverse = true`를 주면
오래된 순이 됩니다. 택소노미, 피드, 검색 인덱스, 사이트맵, OG 이미지, 출력
포맷에도 작성 페이지와 똑같이 참여합니다.

## 변형

### 하루에 한 페이지

하루 단위 레코드를 반환하고 월 토큰을 일 토큰으로 바꾸면 됩니다.

```toml
[permalinks]
"reports" = "/reports/:year/:month/:day/"   # /reports/2026/09/08/
```

나머지는 그대로입니다. `id`가 `"2026-09-08"`이 되고 `date`가 그날이 되면 같은
규칙이 페이지를 만듭니다. 하루에 이름이 다른 리포트가 여럿 필요하다면 `:day`
대신 `:slug`를 쓰세요(`/reports/:year/:month/:slug/`). 이때 URL에는 슬러그화된
`id`가 들어가므로 레코드는 하루에 하나가 아니라 서로 고유하기만 하면 됩니다.

### 한 번에 한 달만 주는 API

`[[data.remote]]`는 URL 하나, 요청 하나입니다. 데이터가 달 단위로 나뉘어 올
때(페이지네이션 엔드포인트, 달마다 다른 URL, 여러 응답을 합쳐야 하는 경우)에는
빌드 전 훅으로 가져와 `data/` 아래 파일 하나로 합치고, `source`가 그 파일을
가리키게 하세요.

```toml
[build]
hooks.pre = ["./scripts/fetch-reports.sh"]   # data/reports.json을 씀

[[content.generate]]
source = "reports"                           # 이제 data/에서 온 site.data.reports
section = "reports"
slug = "id"
title = "label"
date = "date"
```

규칙도, 템플릿도, 퍼머링크 패턴도 그대로이고 `site.data.reports`의 출처만
바뀝니다. 훅의 계약과 `curl -f`가 중요한 이유는
[빌드 훅 › API에서 데이터 가져오기](/ko/features/build-hooks/#api에서-데이터-가져오기)를
참고하세요.

## 함께 보기

- [원격 데이터 소스](/ko/features/remote-data/) — 가져오기, 캐시, 오류 정책
- [콘텐츠 생성](/ko/features/content-generation/) — `[[content.generate]]` 전체 레퍼런스
- [설정 › 퍼머링크](/ko/start/config/#퍼머링크) — 토큰 패턴과 규칙 순서
- [섹션](/ko/writing/sections/) — `sort_by`, `page_template`, 섹션 목록
- [빌드 훅](/ko/features/build-hooks/) — 여러 요청이나 GET 이외의 데이터 수집
