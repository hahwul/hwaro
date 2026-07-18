+++
title = "관련 글"
description = "공유하는 택소노미 항목 기반 관련 콘텐츠 추천"
weight = 10
+++

공유하는 택소노미 항목(태그, 카테고리 등)을 기반으로 관련 콘텐츠를 자동 추천합니다.

## 설정

`config.toml`에서 활성화합니다.

```toml
[related]
enabled = true
limit = 5
taxonomies = ["tags"]
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| enabled | bool | false | 관련 글 계산 활성화 |
| limit | int | 5 | 페이지당 관련 글 최대 개수 |
| taxonomies | array | ["tags"] | 유사도 계산에 쓰는 택소노미 이름 |

## 동작 방식

1. Hwaro가 택소노미 항목 → 페이지의 역색인을 만듭니다
2. 각 페이지마다 다른 페이지와 공유하는 택소노미 항목 수를 셉니다
3. 공유 항목이 많은 페이지가 더 높은 순위를 받습니다
4. 결과는 언어별로 필터링됩니다(다국어 사이트는 같은 언어의 글만 보여줌)
5. 상위 N개(`limit`까지)가 관련 글로 지정됩니다

초안 페이지, 인덱스 페이지, 생성된 페이지는 관련 글 계산에서 제외됩니다.

## 템플릿 변수

각 페이지는 관련 페이지를 관련도 순으로 담은 `related_posts` 배열을 갖습니다.

| 변수 | 타입 | 설명 |
|----------|------|-------------|
| related_posts | array | 현재 페이지와 관련된 페이지들, 공유 항목 수 순 정렬 |

`related_posts`의 각 항목은 완전한 페이지 객체이므로 모든 페이지 변수(`title`, `url`, `description`, `date`, `tags` 등)에 접근할 수 있습니다.

## 템플릿에서 사용

### 기본 관련 글

```jinja
{% if related_posts | length > 0 %}
<section class="related-posts">
  <h2>Related Posts</h2>
  <ul>
    {% for post in related_posts %}
    <li>
      <a href="{{ post.url }}">{{ post.title }}</a>
      {% if post.description %}
        <p>{{ post.description }}</p>
      {% endif %}
    </li>
    {% endfor %}
  </ul>
</section>
{% endif %}
```

### 태그와 함께 표시

```jinja
{% if related_posts | length > 0 %}
<aside class="related">
  <h3>You might also like</h3>
  {% for post in related_posts %}
  <article>
    <a href="{{ post.url }}">{{ post.title }}</a>
    <div class="tags">
      {% for tag in post.tags %}
        <span class="tag">{{ tag }}</span>
      {% endfor %}
    </div>
  </article>
  {% endfor %}
</aside>
{% endif %}
```

## 여러 택소노미 사용

관련도를 높이기 위해 여러 택소노미를 기준으로 삼을 수 있습니다.

```toml
[related]
enabled = true
limit = 5
taxonomies = ["tags", "categories"]
```

여러 택소노미에서 항목을 공유하는 글이 더 높은 순위를 받습니다. 예를 들어 어떤 글과 태그 2개, 카테고리 1개를 공유하는 글은 3점, 태그 1개만 공유하는 글은 1점입니다.

## 함께 보기

- [택소노미](/ko/writing/taxonomies/) — 점수 계산에 쓰이는 태그와 카테고리
- [시리즈](/ko/features/series/) — 순서 있는 콘텐츠 묶기
- [설정](/ko/start/config/) — 관련 글 설정 레퍼런스
