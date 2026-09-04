+++
title = "원격 데이터 소스"
description = "빌드 시 HTTP(S) 데이터를 site.data로 가져오기"
weight = 22
toc = true
+++

`[[data.remote]]`는 템플릿을 렌더링하기 전에 HTTP(S) 페이로드를
`site.data`로 가져옵니다. JSON API, 간단한 헤드리스 CMS 엔드포인트처럼 요청
하나로 끝나는 데이터 소스에 알맞습니다. 템플릿은 네트워크에 접근하지 않고,
모든 외부 의존성은 `config.toml` 한곳에 선언됩니다.

사이트와 함께 커밋하는 데이터는 `data/` 파일을 사용하세요. 원격 데이터와
로컬 데이터는 템플릿에서 같은 방식으로 접근하므로, 둘 사이에서 키를 옮겨도
템플릿을 바꿀 필요가 없습니다.

## 빠른 시작

```toml
[[data.remote]]
key = "team"                # site.data.team으로 노출
url = "https://api.example.com/team"
format = "json"             # 응답이 포맷을 알려 주면 생략 가능
headers = { Authorization = "Bearer ${API_TOKEN}" }
cache = "1h"                # 신선한 캐시 페이로드 재사용
on_error = "fail"           # fail | warn-and-use-cache | warn-and-skip
```

```jinja
{% for person in site.data.team %}
  <h2>{{ person.name }}</h2>
  <p>{{ person.role }}</p>
{% endfor %}
```

## 설정 레퍼런스

| 필드 | 필수 | 의미 |
|-------|----------|---------|
| `key` | 예 | `site.data` 아래 이름. 영문자, 숫자, `_`, `-`를 쓸 수 있고 대소문자를 구분하지 않고 고유해야 합니다. |
| `url` | 예 | 절대 `http://` 또는 `https://` URL. 다른 스킴은 설정 로딩 시 거부됩니다. |
| `format` | 아니오 | `json`, `toml`, `yaml`, `csv`. 생략하면 응답의 `Content-Type`, 그다음 리다이렉트 뒤 최종 URL 확장자로 판단합니다. 둘 다 알 수 없으면 명시하세요. |
| `headers` | 아니오 | 추가 요청 헤더. 자격 증명으로 취급하여 로그에 남기지 않으며, 리다이렉트가 원래 origin을 벗어나면 제거합니다. |
| `cache` | 아니오 | `"90s"`, `"30m"`, `"1h"`, `"7d"`, `"1h30m"` 같은 디스크 캐시 TTL. 캐시가 신선하면 요청하지 않습니다. |
| `on_error` | 아니오 | 가져오기/파싱 실패 정책: `fail`(기본값), `warn-and-use-cache`, `warn-and-skip`. |

CSV 데이터는 행 배열이 되며, 각 행은 공백을 제거한 문자열 배열입니다. 로컬
CSV에서 `load_data()`가 만드는 모양과 같습니다.

## 환경 변수

`url`, `headers`의 `${VAR}` 플레이스홀더는 환경 변수로 치환됩니다. 일반 설정
치환과 달리 여기서 없는 변수는 빌드를 실패시키고 변수 이름을 알려 줍니다. 빈
토큰으로 요청하는 실수를 막기 위해서입니다. 안전한 기본값이 있으면
`${VAR:-default}`를 사용하세요. 치환은 빌드가 소스를 가져올 때만 일어나므로
`hwaro deploy`, `hwaro new`, `hwaro tool ...`에는 변수가 필요하지 않습니다.

## 캐시, 오프라인 빌드, Serve

페이로드는 `hwaro serve`가 감시하지 않는 `.hwaro/remote_data/`에 저장됩니다.
캐시는 `hwaro build --full` 후에도 남고 Git에서 무시됩니다.

- `cache`를 설정하면 TTL이 남아 있는 동안 캐시를 재사용합니다. 설정하지 않은
  경우 새 `hwaro build`마다 다시 가져오지만, `warn-and-use-cache`용 마지막
  성공 페이로드는 보관합니다.
- `warn-and-use-cache`는 가져오기나 파싱이 실패하면 경고 후 저장된 페이로드를
  사용합니다. `warn-and-skip`은 경고 후 `site.data.<key>`를 이번 빌드에서
  비웁니다. 이 키는 템플릿에서 조건으로 감싸세요. `fail`은 빌드를 멈춥니다.
- 한 번의 `hwaro serve` 세션에서는 변하지 않은 소스를 메모리에 유지합니다.
  TTL이 있는 소스는 만료 뒤 첫 전체 리빌드에서 다시 시도합니다. 갱신이
  실패하면 편집을 오프라인에서도 계속할 수 있게 이전 페이로드를 유지합니다.
- 페이로드가 바뀌면 로컬 `data/` 파일을 고친 것처럼 캐시된 페이지를 무효화합니다.

각 소스는 연결에 10초, 읽기마다 30초, 리다이렉트와 응답 본문 전체에는 총
120초가 주어집니다. 타임아웃도 선택한 `on_error` 정책을 따릅니다.

## 범위와 충돌

원격 소스는 의도적으로 설정에서만 선언합니다. `load_data()`와 숏코드는 URL을
가져올 수 없습니다. 페이지네이션, POST 요청, 인증 흐름, 여러 응답의 변형이
필요하면 [빌드 전 훅](/ko/features/build-hooks/#api에서-데이터-가져오기)으로
`data/` 아래에 로컬 파일을 쓰세요.

원격 키는 로컬 데이터 파일과 이름을 공유할 수 없습니다. 예를 들어
`data/team.json`과 `key = "team"`은 설정 오류이며, Hwaro는 조용히 하나를 고르는
대신 두 소스를 모두 알려 줍니다.

원격 배열을 페이지로 만들려면 [콘텐츠 생성](/ko/features/content-generation/)과
함께 사용하세요. 생성된 페이지는 작성한 콘텐츠와 똑같이 목록, 택소노미, 피드,
검색, 사이트맵, 출력 포맷에 포함됩니다.

## 함께 보기

- [데이터 모델](/ko/templates/data-model/#데이터-파일) — 로컬 `data/` 파일과 템플릿 접근
- [콘텐츠 생성](/ko/features/content-generation/) — 데이터 레코드를 페이지로 만들기
- [빌드 훅](/ko/features/build-hooks/) — 여러 단계 또는 GET 이외의 연동
