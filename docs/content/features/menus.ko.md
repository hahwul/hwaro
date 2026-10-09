+++
title = "메뉴"
description = "설정 또는 프론트 매터로 정의하는 Hugo 스타일의 이름 있는 내비게이션 메뉴"
weight = 11
toc = true
+++

이름 있는 내비게이션 메뉴를 트리로 구성해 `site.menus` / `get_menu()`로 템플릿에 노출합니다. 메뉴는 `config.toml`에서 전부 정의할 수도, 페이지/섹션 프론트 매터로만 구성할 수도, 둘을 동시에 쓸 수도 있습니다. 두 소스의 엔트리는 같은 트리로 병합됩니다. `[menus] auto_sections`로 최상위 섹션에서 메뉴를 채울 수도 있습니다([섹션 메뉴 자동 생성](#섹션-메뉴-자동-생성) 참고).

## 메뉴 설정

```toml
[[menus.main]]
name = "Posts"
url = "/posts/"
weight = 1

[[menus.main]]
name = "About"
url = "/about/"
weight = 2
identifier = "about"
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| name | string | — | **필수.** 표시 라벨. `name`이 없는 엔트리는 경고와 함께 건너뜀 |
| url | string | "" | 루트 상대 경로(`/posts/`) 또는 절대 `http(s)://`/`//` URL |
| weight | int | 0 | 메뉴 내 정렬 순서(오름차순), 이후 `name`, `identifier` 순 |
| identifier | string | `name` | 다른 엔트리가 `parent`로 참조하는 고유 키 |
| parent | string | 없음 | 이 엔트리를 하위로 넣을 다른 엔트리의 `identifier` |

`[[menus.<name>]]` 블록 하나가 이름 있는 메뉴 하나입니다. 두 번째 메뉴가 필요하면 `[[menus.footer]]`를 추가하고 `get_menu(name="footer")`로 렌더링합니다.

## 프론트 매터로 페이지/섹션 등록

페이지나 섹션은 `config.toml`을 건드리지 않고도 메뉴에 합류할 수 있습니다.

```toml
+++
title = "My Post"
menus = ["main"]
+++
```

`menus`(또는 단수형 별칭 `menu`. 둘 다 있으면 `menus`가 우선)는 단일 문자열(`menus = "main"`)도 허용하고, 필드별 오버라이드를 위한 테이블 형태도 허용합니다.

```toml
+++
title = "My Post"

[menus.main]
name = "Featured Post"
weight = 1
parent = "posts"
+++
```

테이블 형태의 모든 필드는 선택 사항이며 페이지 자체 데이터로 대체됩니다. `name`은 `page.title`, `weight`는 `0`, `identifier`는 결정된 `name`, `parent`는 없음(루트 엔트리)이 기본값입니다.

페이지/섹션은 `config.toml`이 선언한 적 없는 이름을 포함해 **어떤** 메뉴 이름에도 등록할 수 있습니다. 프론트 매터로만 정의한 메뉴도 그 자체로 정상적인 지원 구성입니다(`hwaro doctor`는 설정이 다른 곳에 메뉴를 하나라도 선언한 경우에만 선언되지 않은 이름을 지적합니다. `[[menus.*]]` 블록이 하나도 없는 사이트는 의도적으로 프론트 매터에 전부 맡긴 것으로 보기 때문입니다).

## 섹션 메뉴 자동 생성

`auto_sections`에 메뉴 이름을 지정하면 모든 최상위 섹션(`content/` 바로 아래의 섹션)이 `[[menus.*]]` 블록이나 프론트 매터 없이 그 메뉴에 들어갑니다. Hugo의 `sectionPagesMenu`에 해당합니다.

```toml
[menus]
auto_sections = "main"
```

각 섹션은 `identifier` = 디렉터리 이름(`content/posts/_index.md`라면 `posts`), `name` = 섹션 제목, `url` = 섹션 URL, `weight` = 섹션의 `weight`인 엔트리가 됩니다. 목록에서 빠지는 섹션은 제외합니다. 초안, 게시 전(unpublished), 헤드리스(`render = false`), `transparent` 섹션과 `redirect_to`가 외부 사이트를 가리키는 섹션이 여기에 해당합니다. 중첩 섹션은 들어가지 않으며, 제외된 `transparent` 섹션의 하위 섹션도 마찬가지입니다. 섹션에는 `_index.md`가 있어야 합니다. 페이지만 있는 디렉터리는 섹션이 아니므로 엔트리가 생기지 않습니다. 버전 문서 사이트에서는 섹션을 버전 루트 기준으로 해석합니다. `docs/v2`는 `docs`로, 최상위 `v2/` 버전이라면 `v2/guide`는 `guide`로 취급합니다. 버전이 없는 `docs/_index.md`가 버전 루트와 함께 있으면, 각 버전의 페이지는 그 버전의 루트로, 버전이 없는 페이지는 버전이 없는 섹션으로 연결됩니다.

`auto_sections`는 `[menus]` 아래의 예약된 키이며 메뉴 이름이 아닙니다. 문자열이 아니거나 빈 값이면 설정 오류이고, `[languages.<code>.menus]` 아래에 지정하면 경고와 함께 무시합니다.

명시적인 엔트리가 우선합니다. `identifier`가 같은 `[[menus.main]]` 엔트리나 프론트 매터 등록은 자동 엔트리를 대체하고, identifier가 다른 엔트리는 자동 엔트리 옆에 추가됩니다. 메뉴 전체는 `weight`, 그다음 `name` 순으로 정렬합니다. 섹션이 자기 프론트 매터로 같은 메뉴에 등록하면 그 등록만 남습니다.

```toml
[menus]
auto_sections = "main"

# 자동 생성된 "posts" 엔트리의 이름을 바꾸고 맨 뒤로 보냅니다
[[menus.main]]
name = "Journal"
url = "/posts/"
identifier = "posts"
weight = 99
```

다국어 사이트에서는 언어마다 그 언어의 섹션으로 엔트리를 만듭니다(`posts/_index.ko.md`가 한국어 엔트리의 제목과 `/ko/posts/` URL을 정합니다). 번역된 섹션이 없는 언어에는 해당 엔트리가 생기지 않고, 엔트리가 하나도 없는 언어는 `get_menu()`에서 기본 언어의 메뉴로 대체됩니다.

위와 같은 전역 `[[menus.main]]` 재정의는 자체 `[languages.<code>.menus]` 테이블이 없는 모든 언어에 적용되므로, 한국어 페이지도 `/posts/`로 연결됩니다. 다국어 사이트에서는 언어별로 재정의합니다.

```toml
[menus]
auto_sections = "main"

[[menus.main]]
name = "Journal"
url = "/posts/"
identifier = "posts"

[[languages.ko.menus.main]]
name = "저널"
url = "/ko/posts/"
identifier = "posts"
```

## 계층 구조

`parent`가 있는 엔트리는 `identifier`가 일치하는 엔트리의 자식이 됩니다. 중첩 메뉴는 `item.children`을 순회해 렌더링합니다.

```jinja
<ul>
{% for item in get_menu(name="main") %}
  <li>
    <a href="{{ item.href }}">{{ item.name }}</a>
    {% if item.children %}
    <ul>
      {% for child in item.children %}
      <li><a href="{{ child.href }}">{{ child.name }}</a></li>
      {% endfor %}
    </ul>
    {% endif %}
  </li>
{% endfor %}
</ul>
```

같은 메뉴 안의 어떤 `identifier`와도 일치하지 않는 `parent`(오타나 낡은 참조)는 빌드를 실패시키지 않습니다. 대신 해당 엔트리가 루트 레벨로 승격되고 빌드 로그에 경고가 남습니다. `hwaro doctor`는 빌드 전에 `config.toml`에서 이를 미리 지적합니다([doctor](/ko/start/tools/doctor/) 참고). `identifier`가 중복되면 마지막에 선언된 엔트리가 남고 앞의 것은 버려집니다.

## 언어별 메뉴

menus 테이블이 없는 `[languages.<code>]` 블록은 전역 `[[menus.*]]` 집합을 통째로 상속합니다. `[[languages.<code>.menus.<name>]]`을 선언하면 그 언어에서 해당 메뉴가 통째로 **대체**되며, 전역 집합과 병합되지 않습니다. menus 테이블을 하나라도 선언한 언어는 이름을 적지 않은 메뉴까지 포함해 전역 집합 전체를 대체합니다. `footer`만 선언하면 그 언어의 `main`은 프론트 매터와 `auto_sections` 엔트리로만 채워지므로, 전역 `main` 엔트리를 유지하려면 `[[languages.<code>.menus.main]]`에 다시 적으세요.

```toml
[[menus.main]]
name = "Posts"
url = "/posts/"

[languages.ko]
language_name = "한국어"

[[languages.ko.menus.main]]
name = "글"
url = "/ko/posts/"
```

`get_menu()`는 **현재 페이지의** 언어를 기준으로 해석하며, 그 언어에 요청한 메뉴 이름의 엔트리가 없으면 기본 언어로 대체합니다. `site.menus`는 항상 기본 언어의 메뉴이므로, 기본 언어가 아닌 페이지에서 렌더링되는 템플릿에서는 `get_menu()`를 사용합니다.

프론트 매터 등록은 등록한 페이지/섹션 자신의 언어를 따릅니다. 언어별 설정 오버라이드와 무관하게, 자신이 속한 언어의 메뉴 집합에 합쳐집니다.

## 활성 상태 스타일링

`active_path` 필터는 메뉴 엔트리의 `url`을 현재 페이지와 비교합니다.

```jinja
{% for item in get_menu(name="main") %}
<a href="{{ item.href }}"{% if item.url | active_path %} aria-current="page"{% endif %}>{{ item.name }}</a>
{% endfor %}
```

`ancestor=true`를 넘기면 하위 페이지도 일치합니다(섹션 안을 탐색하는 동안 상위 내비게이션 항목을 강조/펼친 상태로 유지할 때 유용).

```jinja
<a href="{{ item.href }}"{% if item.url | active_path(ancestor=true) %} class="open"{% endif %}>{{ item.name }}</a>
```

루트 경로(`/`)는 `ancestor=true`여도 항상 정확히 일치할 때만 매칭됩니다. 그렇지 않으면 홈 내비게이션 항목이 사이트의 모든 페이지에서 활성/펼침으로 보이게 됩니다. 외부 엔트리는 절대 매칭되지 않습니다(외부 URL에는 조상 관계를 따질 "현재 페이지"가 없음). [필터](/ko/templates/filters/#url-필터)의 URL 필터 절을 참고합니다.

## `href`와 `url`

모든 엔트리는 둘 다 노출합니다.

- **`url`** — 설정/등록된 그대로의 루트 상대 경로(외부 URL이면 손대지 않은 원본). `page.url`과 비교 가능한 값으로, `active_path`가 비교하는 대상입니다.
- **`href`** — 실제로 `<a href>`에 넣을 값. 내부 엔트리라면 `url` 앞에 사이트의 `base_path`(`base_url`의 경로 부분, 예: `https://user.github.io/repo/`에 배포된 프로젝트 사이트의 `/repo`)가 붙어, 서브패스 배포에서도 링크가 올바르게 해석됩니다. 외부 엔트리는 그대로이며 `href`와 `url`이 동일합니다.

항상 `item.href`를 렌더링하고, 비교에는 `item.url`을 사용합니다(`active_path`가 내부적으로 하는 방식). 둘을 섞어 쓰면 서브패스 배포가 깨지거나(`href` 자리에 `url` 사용) 현재 페이지와 절대 매칭되지 않습니다(`active_path`식 비교에 `href` 사용).

## 엔트리 레퍼런스

| 필드 | 타입 | 설명 |
|-------|------|--------------|
| name | String | 표시 라벨 |
| url | String | 순수 루트 상대 경로, 또는 손대지 않은 외부 URL |
| href | String | `base_path`가 적용된 `url`(내부) 또는 그대로(외부) — `<a href>`에는 이 값 사용 |
| identifier | String | 메뉴 내 고유 키 |
| weight | Int | 정렬 순서 |
| external | Bool | `http://`, `https://`, `//` URL이면 `true` |
| children | Array\<Entry\> | 중첩 엔트리([계층 구조](#계층-구조) 참고) |
| page | Page? | 엔트리가 프론트 매터에서 왔고 `Page`로 해석될 때 등록한 페이지/섹션의 데이터(설정 전용 엔트리와 `Section`의 `_index.md`에서 등록한 엔트리는 nil) |

## 함께 보기

- [함수](/ko/templates/functions/#get-menu) — `get_menu()` 레퍼런스
- [필터](/ko/templates/filters/#url-필터) — `active_path` 레퍼런스
- [데이터 모델](/ko/templates/data-model/#메뉴) — `site.menus`와 Entry 구조
- [설정](/ko/start/config/#메뉴) — `[[menus.*]]`, `[menus] auto_sections` 설정 레퍼런스
- [doctor](/ko/start/tools/doctor/) — `menu-parent-undefined` / `menu-undeclared` 검사기
