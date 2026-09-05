+++
title = "첫 사이트 만들기"
description = "5분 만에 첫 Hwaro 사이트 만들기"
weight = 2
toc = true
+++

5분 만에 첫 Hwaro 사이트를 만듭니다.

## 1. 프로젝트 생성

```bash
hwaro init my-site --scaffold blog
cd my-site
```

내장 스캐폴드:

| 스캐폴드 | 설명 |
|----------|-------------|
| `simple` | 랜딩 페이지, 소규모 사이트 (기본값) |
| `bare` | 시맨틱 HTML만 있는 최소 구조 |
| `blog` | 태그, 읽기 시간, 이전/다음 글 이동이 있는 포스트 |
| `docs` | 사이드바와 이전/다음 페이지 이동이 있는 문서 |
| `book` | 챕터, 이전/다음 이동, 키보드 단축키가 있는 책 |

모든 스캐폴드는 CSS `light-dark()` 쌍 위에 만든 하나의 디자인 토큰 시스템을
공유하므로, 별도 설정 없이 읽는 사람의 OS 색상 모드(라이트/다크)를 그대로 따라갑니다. 스타일이 있는 스캐폴드에는 헤더에 테마 전환
버튼도 들어 있습니다. auto → light → dark 순으로 순환하고, 선택을
`localStorage`에 저장하며, 첫 페인트 전에 적용하기 때문에 화면이 번쩍이지
않습니다. 한 가지 모드로 고정하려면(다크 전용 사이트 등) 생성된
`css/style.css` 끝에 `:root { color-scheme: dark; }`를 추가합니다.

스캐폴드에는 몇 가지 모던한 요소도 들어 있습니다. 반투명 고정 헤더, 페이지
사이의 네이티브 크로스 문서 뷰 전환, 그리고 (블로그 글과 책 페이지의) CSS
전용 읽기 진행 표시선입니다. 모두 구형 브라우저에서는 자연스럽게 꺼지고,
모든 애니메이션은 `prefers-reduced-motion`을 존중합니다.

{% preview_gallery() %}
<a class="preview-item" href="/images/scaffolds/scaffold-simple.png" target="_blank" rel="noopener"><img src="/images/scaffolds/scaffold-simple.png" alt="simple 스캐폴드" width="1280" height="800" loading="lazy"><div class="preview-label"><code>simple</code> — 랜딩 페이지, 소규모 사이트</div></a>
<a class="preview-item" href="/images/scaffolds/scaffold-bare.png" target="_blank" rel="noopener"><img src="/images/scaffolds/scaffold-bare.png" alt="bare 스캐폴드" width="1280" height="800" loading="lazy"><div class="preview-label"><code>bare</code> — 시맨틱 HTML만 있는 최소 구조</div></a>
<a class="preview-item" href="/images/scaffolds/scaffold-blog.png" target="_blank" rel="noopener"><img src="/images/scaffolds/scaffold-blog.png" alt="blog 스캐폴드" width="1280" height="800" loading="lazy"><div class="preview-label"><code>blog</code> — 태그와 카테고리가 있는 포스트</div></a>
<a class="preview-item" href="/images/scaffolds/scaffold-docs.png" target="_blank" rel="noopener"><img src="/images/scaffolds/scaffold-docs.png" alt="docs 스캐폴드" width="1280" height="800" loading="lazy"><div class="preview-label"><code>docs</code> — 사이드바가 있는 문서</div></a>
<a class="preview-item" href="/images/scaffolds/scaffold-book.png" target="_blank" rel="noopener"><img src="/images/scaffolds/scaffold-book.png" alt="book 스캐폴드" width="1280" height="800" loading="lazy"><div class="preview-label"><code>book</code> — 챕터가 있는 책</div></a>
{% end %}

> **팁:** 더 완성된 출발점이 필요하면 바로 쓸 수 있는 보일러플레이트 모음인 [Hwaro Examples](https://examples.hwaro.hahwul.com/)를 살펴보세요.

## 2. 개발 서버 시작

```bash
hwaro serve
```

`http://localhost:3000`을 엽니다. 변경 사항은 자동으로 다시 로드됩니다.

## 3. 프로젝트 구조

```
my-site/
├── config.toml      # Site configuration
├── content/         # Markdown content
│   ├── index.md     # Homepage
│   └── blog/        # Blog section
│       ├── _index.md
│       └── hello.md
├── templates/       # Jinja2 templates
├── static/          # Static files (CSS, JS, images)
├── data/            # 선택: site.data로 노출되는 JSON/YAML/TOML/CSV
└── public/          # Generated output
```

### 파일을 어디에 둘까

두 가지만 기억하면 됩니다.

**`data/`는 프로젝트 루트에 둡니다.** `content/` 안이 아니라 `config.toml` 옆입니다. 이 디렉터리의 파일은 자동으로 로드되고 파일 이름이 키가 되므로, `data/team.json`은 어느 템플릿에서든 `site.data.team`으로 쓸 수 있습니다.

```jinja
{% for member in site.data.team %}
  <li>{{ member.name }}</li>
{% endfor %}
```

하위 디렉터리는 중첩됩니다(`data/users/alice.yml` → `site.data.users.alice`). `hwaro init`은 이 디렉터리를 만들지 않으니 필요할 때 직접 추가하세요. 자세한 규칙은 [데이터 모델](/ko/templates/data-model/)을 참고하세요.

**이미지 같은 정적 파일은 `static/`에 둡니다.** `static/images/photo.jpg`는 출력물에서 `/images/photo.jpg`로 복사되므로, 앞에 슬래시를 붙여 참조합니다.

```
{{ figure(src="/images/photo.jpg", caption="A photo") }}
```

`example.com/my-site/`처럼 하위 경로에 배포할 때도 앞의 `/`를 그대로 두세요. Hwaro가 빌드 시점에 루트 상대 `src`와 `href`에 `base_url`의 하위 경로를 붙여 주기 때문에, 같은 콘텐츠가 양쪽에서 모두 동작합니다.

에셋을 그 파일을 쓰는 페이지 옆, 즉 `content/` 안에 두는 것도 가능하지만 이는 선택 기능입니다. 먼저 [콘텐츠 파일](/ko/features/content-files/)을 활성화하세요.

```toml
[content.files]
allow_extensions = ["jpg", "png", "svg", "pdf"]
```

## 4. 설정 수정

`config.toml`을 엽니다:

```toml
title = "My Site"
description = "A site built with Hwaro"
base_url = "https://example.com"
```

## 5. 페이지 만들기

```bash
hwaro new content/about.md
```

> **팁:** 인자 없이 `hwaro new`를 실행하면 대화형 위저드가 열립니다.
> 경로를 추천해 주고 제목, 설명, 태그 등을 대신 받아 줍니다.

`content/about.md`를 수정합니다:

```markdown
+++
title = "About"
+++

Welcome to my site!
```

`http://localhost:3000/about/`에서 확인합니다.

## 6. 섹션 만들기

섹션은 관련 콘텐츠를 묶는 단위입니다. 블로그 섹션을 만들어 봅니다:

```bash
mkdir -p content/blog
```

`content/blog/_index.md`를 만듭니다:

```markdown
+++
title = "Blog"
sort_by = "date"
+++

My blog posts.
```

`content/blog/first-post.md`를 만듭니다:

```markdown
+++
title = "My First Post"
date = "2024-01-15"
tags = ["hello"]
+++

Hello, world!
```

`http://localhost:3000/blog/`에서 확인합니다.

## 7. 프로덕션 빌드

```bash
hwaro build
```

`public/` 디렉터리를 아무 정적 호스트에나 배포하면 됩니다. 간단한 설정 방법은 [GitHub Pages](/ko/deploy/github-pages/) 배포 가이드에 있습니다.

## 선택: AI 에이전트와 함께 만들기

Claude Code, Cursor, Codex 같은 스킬 지원 에이전트를 쓴다면, Hwaro가 제공하는
두 개의 [에이전트 스킬](/ko/integrations/skills/)로 방금 만든 프로젝트를 다루는
방법을 에이전트에게 가르칠 수 있습니다:

| 스킬 | 하는 일 |
|-------|--------------|
| `hwaro` | `init`, `new`, `serve`, `build`, `doctor`와 콘텐츠 도구를 제대로 실행합니다. 텍스트 출력을 추측하는 대신 `--json` 출력 규약과 `HWARO_E_*` 종료 코드를 사용합니다. |
| `hwaro-design` | Hwaro의 Crinja 템플릿과 `light-dark()` 디자인 토큰 안에서 사이트를 디자인하고 리테마합니다. 전형적인 AI 느낌의 레이아웃을 피하는 안티슬롭 원칙을 따릅니다. |

명령 하나로 둘 다 설치합니다:

```bash
npx skills add hahwul/hwaro
```

이후 *"이 Hwaro 사이트에 projects 섹션을 추가해 줘"* 나 *"이 블로그를 따뜻한
다크 팔레트로 리테마해 줘"* 처럼 요청하면 에이전트가 알아서 맞는 스킬을
불러옵니다. 수동 설치 경로와 에이전트별 디렉터리는
[에이전트 스킬](/ko/integrations/skills/)을, 에이전트가 먼저 따라야 할
프로젝트별 규칙을 기록해 두려면 [agents-md](/ko/start/tools/agents-md/)를
참고합니다.

## 다음 단계

- [CLI](/ko/start/cli/) — 사용 가능한 모든 명령
- [설정](/ko/start/config/) — 전체 설정 레퍼런스
- [콘텐츠 작성](/ko/writing/) — 페이지, 섹션, 택소노미
- [에이전트 스킬](/ko/integrations/skills/) — AI 에이전트에게 사이트 제작과 디자인 맡기기
- [배포](/ko/deploy/) — 호스팅과 배포 가이드
