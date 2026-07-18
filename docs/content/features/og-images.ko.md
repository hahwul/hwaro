+++
title = "자동 OG 이미지"
description = "페이지 제목으로 Open Graph 미리보기 이미지 자동 생성"
weight = 3
toc = true
+++

Hwaro는 프론트 매터에 커스텀 `image`가 없는 모든 페이지에 1200x630 Open Graph 미리보기 이미지를 자동 생성합니다. 생성된 경로가 `page.image`로 설정되므로 `og:image` 메타 태그가 자동으로 이를 사용합니다 — 템플릿을 고칠 필요가 없습니다.

![자동 OG 이미지 페이지의 자동 생성 OG 이미지](/og-images/features-og-images.png)
*이 페이지의 자동 생성 OG 이미지 (`style = "terminal"`).*

## 빠른 시작

```toml
[og.auto_image]
enabled = true
style = "terminal"
accent_color = "#2ee66b"
logo = "static/logo.png"
```

## 설정

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| enabled | bool | `false` | 자동 OG 이미지 생성 여부 |
| style | string | `"default"` | 구성 프리셋 — [스타일 프리셋](#스타일-프리셋) 참고 |
| background | string | `"#171310"` | 배경색(hex) |
| text_color | string | `"#f4ede4"` | 제목과 설명의 텍스트 색 |
| accent_color | string | `"#ec7a66"` | 룰, 브랜드 마크, 색 블록에 쓰는 액센트 색 |
| secondary_color | string | — | 투톤 스타일(`split`, `brutalist`, `bauhaus`, …)의 두 번째 색. 생략하면 `accent_color`에서 자동 파생 |
| font_size | int | `48` | 제목 폰트 크기(px). 더 큰 값을 지정하지 않으면 각 스타일이 자체 스케일로 자동 확대 |
| logo | string | — | 이미지에 삽입할 로고 파일 경로 (예: `static/logo.png`) |
| logo_position | string | `"bottom-left"` | `bottom-left`, `bottom-right`, `top-left`, `top-right` |
| show_title | bool | `true` | 사이트 이름 표시 (하단 브랜드 행, 또는 스타일별 자리 — 아이브로, 키커, 창 제목 표시줄) |
| output_dir | string | `"og-images"` | 생성 이미지를 담을 디렉터리 |
| format | string | `"png"` | `"png"` 또는 `"svg"`. 소셜 플랫폼은 SVG `og:image`를 렌더링하지 않으므로 PNG가 기본값 |
| font_path | string | — | PNG 출력용 커스텀 `.ttf`/`.otf`. 폰트 체인의 맨 앞에 오고, 없는 글리프는 번들 폰트로 대체 |
| background_image | string | — | 텍스트 뒤에 합성할 배경 사진 |
| overlay_opacity | float | `0.45` | `background` 색이 사진을 덮는 정도 (0.0 = 사진 그대로, 1.0 = 사진 가림) |
| text_panel | float | `0.0` | 0.0–0.6. 복잡한 배경에서 가독성을 높이는 텍스트 뒤 소프트 패널 |
| pattern_opacity | float | `0.35` | 패턴 스타일(`dots`, `grid`, …)의 최대 알파. 각 패턴은 이 값을 정점으로 내부에서 점차 옅어짐 |
| pattern_scale | float | `1.0` | 패턴 스타일의 배율 (최소 0.1) |
| accent_bars | bool | `false` | 패턴 스타일에 클래식한 얇은 상/하단 액센트 바 추가 |
| lazy_generate | bool | `false` | `hwaro serve`에서 일괄 생성을 건너뛰고 첫 요청 때 렌더링. 대규모 사이트에 권장. `hwaro build`에는 영향 없음 |

제목은 Space Grotesk, 설명은 Space Grotesk Medium, `terminal` 스타일은 JetBrains Mono로 렌더링됩니다 — 모두 바이너리에 번들되어 있어 PNG 출력이 어떤 머신에서든 동일합니다. 제목에 필요하면 CJK를 지원하는 시스템 폰트가 체인에 자동으로 추가되고, 그 밖의 모든 경우는 DejaVu Sans Bold가 받쳐 줍니다.

## 스타일 프리셋

`style` 옵션이 구성 전체를 결정합니다. 아래 미리보기를 클릭하면 확대됩니다.

**Signature** — 그 자체로 완결된 구성:

| 스타일 | 설명 |
|-------|-------------|
| `terminal` | 신호등 버튼, `$` 프롬프트, 블록 커서가 있는 코드 에디터 창. 개발 블로그와 문서용 |
| `bauhaus` | 액센트/보조/파생 색으로 구성한 평면 기하학 아트 포스터 도형 |
| `halftone` | 오른쪽 가장자리에서 번져 들어오는 인쇄풍 하프톤 도트 필드 |

**Modern** — 생성된 배경 위의 타이포그래피 중심 구성:

| 스타일 | 설명 |
|-------|-------------|
| `editorial` | 잡지 표지풍: 헤어라인 룰, 대문자 사이트명 키커, 세로 액센트 룰. 무난하고 조화로운 기본 선택지 |
| `artistic` | 필름 그레인을 더한 메시 그라디언트 색 필드. 완성도 높은 풍부한 느낌 |
| `hero` | 스포트라이트 글로우, 제목 첫 단어의 거대한 고스트 에코, 포스터 타이포그래피 |
| `surreal` | 오로라 구체와 흐르는 리본 밴드에 그레인을 더한 구성 |
| `monument` | 극단적 미니멀리즘 — 거대한 타이포, 넓은 여백, 제목 위 액센트 룰, 오른쪽 아래 브랜드 행 |
| `framed` | 초대장 카드: 중립 색 헤어라인 프레임에 액센트 코너 브래킷과 가운데 정렬 타이포 |

**Geometric** — 대담한 평면 색 블로킹:

| 스타일 | 설명 |
|-------|-------------|
| `split` | 왼쪽 대각선 투톤 색 블록, 오른쪽 제목 |
| `band` | 제목을 뚫어낸 전체 폭 색 밴드와 그 위를 받치는 얇은 룰 — 잡지 표지 스타일 |
| `brutalist` | 강한 오프셋 그림자와 거대한 타이포가 있는 두꺼운 프레임 패널 |

**Patterns** — 초점이 있는 구성 (각 패턴은 `pattern_opacity`를 정점으로 내부에서 점차 옅어짐):

| 스타일 | 설명 |
|-------|-------------|
| `default` | 머스트헤드: 상단의 대문자 사이트명 아이브로, 낮은 코너 글로우, 은은한 비네트 |
| `minimal` | 타이포만 — 제목 뒤의 액센트 마침표가 전부 |
| `dots` | 오른쪽 위 모서리에서 번져 들어오는 엇갈린 하프톤 도트 |
| `grid` | 초점 크로스헤어와 레지스트레이션 마크가 있는 가는 청사진 그리드 |
| `diagonal` | 오른쪽 아래 모서리의 45° 스트라이프 쐐기와 빗변의 액센트 룰 |
| `gradient` | 코너 글로우, 비네트, 그레인이 있는 액센트 톤 듀오톤 워시 |
| `waves` | 아래 가장자리에 겹겹이 쌓인 물결 밴드 |

### 미리보기

<div class="og-style-grid">
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-terminal.png" alt="terminal 스타일" loading="lazy" />
    <span class="og-style-label"><code>terminal</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-terminal.png" alt="terminal 스타일" />
        <p><code>terminal</code> — 프롬프트와 커서가 있는 코드 에디터 창</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-bauhaus.png" alt="bauhaus 스타일" loading="lazy" />
    <span class="og-style-label"><code>bauhaus</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-bauhaus.png" alt="bauhaus 스타일" />
        <p><code>bauhaus</code> — 평면 기하학 아트 포스터 도형</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-halftone.png" alt="halftone 스타일" loading="lazy" />
    <span class="og-style-label"><code>halftone</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-halftone.png" alt="halftone 스타일" />
        <p><code>halftone</code> — 인쇄풍 하프톤 도트 페이드</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-editorial.png" alt="editorial 스타일" loading="lazy" />
    <span class="og-style-label"><code>editorial</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-editorial.png" alt="editorial 스타일" />
        <p><code>editorial</code> — 잡지 표지풍: 룰, 키커, 세로 액센트 룰</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-artistic.png" alt="artistic 스타일" loading="lazy" />
    <span class="og-style-label"><code>artistic</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-artistic.png" alt="artistic 스타일" />
        <p><code>artistic</code> — 필름 그레인을 더한 메시 그라디언트 색 필드</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-hero.png" alt="hero 스타일" loading="lazy" />
    <span class="og-style-label"><code>hero</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-hero.png" alt="hero 스타일" />
        <p><code>hero</code> — 고스트 타이포 에코가 있는 스포트라이트 글로우</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-surreal.png" alt="surreal 스타일" loading="lazy" />
    <span class="og-style-label"><code>surreal</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-surreal.png" alt="surreal 스타일" />
        <p><code>surreal</code> — 오로라 구체와 흐르는 리본</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-monument.png" alt="monument 스타일" loading="lazy" />
    <span class="og-style-label"><code>monument</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-monument.png" alt="monument 스타일" />
        <p><code>monument</code> — 제목 위 액센트 룰과 거대한 타이포</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-framed.png" alt="framed 스타일" loading="lazy" />
    <span class="og-style-label"><code>framed</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-framed.png" alt="framed 스타일" />
        <p><code>framed</code> — 액센트 코너 브래킷이 있는 헤어라인 프레임</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-split.png" alt="split 스타일" loading="lazy" />
    <span class="og-style-label"><code>split</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-split.png" alt="split 스타일" />
        <p><code>split</code> — 대각선 투톤 색 블록</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-band.png" alt="band 스타일" loading="lazy" />
    <span class="og-style-label"><code>band</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-band.png" alt="band 스타일" />
        <p><code>band</code> — 뚫어낸 제목 뒤의 잡지풍 색 밴드</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-brutalist.png" alt="brutalist 스타일" loading="lazy" />
    <span class="og-style-label"><code>brutalist</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-brutalist.png" alt="brutalist 스타일" />
        <p><code>brutalist</code> — 강한 오프셋 그림자가 있는 두꺼운 프레임 패널</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-default.png" alt="default 스타일" loading="lazy" />
    <span class="og-style-label"><code>default</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-default.png" alt="default 스타일" />
        <p><code>default</code> — 머스트헤드: 아이브로, 코너 글로우, 비네트</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-minimal.png" alt="minimal 스타일" loading="lazy" />
    <span class="og-style-label"><code>minimal</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-minimal.png" alt="minimal 스타일" />
        <p><code>minimal</code> — 타이포와 액센트 마침표만</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-dots.png" alt="dots 스타일" loading="lazy" />
    <span class="og-style-label"><code>dots</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-dots.png" alt="dots 스타일" />
        <p><code>dots</code> — 오른쪽 위에서 번져 들어오는 하프톤 도트</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-grid.png" alt="grid 스타일" loading="lazy" />
    <span class="og-style-label"><code>grid</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-grid.png" alt="grid 스타일" />
        <p><code>grid</code> — 초점 크로스헤어가 있는 청사진 그리드</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-diagonal.png" alt="diagonal 스타일" loading="lazy" />
    <span class="og-style-label"><code>diagonal</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-diagonal.png" alt="diagonal 스타일" />
        <p><code>diagonal</code> — 액센트 빗변 룰이 있는 스트라이프 쐐기</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-gradient.png" alt="gradient 스타일" loading="lazy" />
    <span class="og-style-label"><code>gradient</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-gradient.png" alt="gradient 스타일" />
        <p><code>gradient</code> — 글로우, 비네트, 그레인이 있는 듀오톤 워시</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/style-waves.png" alt="waves 스타일" loading="lazy" />
    <span class="og-style-label"><code>waves</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/style-waves.png" alt="waves 스타일" />
        <p><code>waves</code> — 아래 가장자리에 겹겹이 쌓인 물결 밴드</p>
      </div>
    </dialog>
  </div>
</div>

<style>
.og-style-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 16px;
  margin: 24px 0;
}
.og-style-card {
  cursor: pointer;
  border-radius: 8px;
  overflow: hidden;
  border: 1px solid var(--border, #1e1e24);
  background: var(--bg-card, #111114);
  transition: transform 0.2s, box-shadow 0.2s;
}
.og-style-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
  border-color: var(--border-light, #2e2e36);
}
.og-style-card > img {
  width: 100%;
  display: block;
}
.og-style-label {
  display: block;
  padding: 8px 12px;
  font-size: 14px;
}
.og-style-card dialog {
  padding: 0;
  border: none;
  background: transparent;
  max-width: 90vw;
  max-height: 90vh;
}
.og-style-card dialog::backdrop {
  background: rgba(0, 0, 0, 0.7);
}
.og-style-dialog {
  position: relative;
  background: var(--bg-elevated, #101014);
  border: 1px solid var(--border, #1e1e24);
  border-radius: 8px;
  overflow: hidden;
}
.og-style-dialog > img {
  display: block;
  max-width: 90vw;
  max-height: 80vh;
  object-fit: contain;
}
.og-style-dialog > button {
  position: absolute;
  top: 8px;
  right: 8px;
  background: rgba(0, 0, 0, 0.6);
  color: #fff;
  border: none;
  border-radius: 50%;
  width: 32px;
  height: 32px;
  font-size: 20px;
  line-height: 1;
  cursor: pointer;
  z-index: 1;
}
.og-style-dialog > p {
  text-align: center;
  padding: 12px;
  margin: 0;
}
</style>

## 배경 이미지

사진을 텍스트 뒤에 합성합니다:

```toml
[og.auto_image]
enabled = true
style = "editorial"
background_image = "static/og-bg.jpg"
overlay_opacity = 0.55
```

렌더링 순서는 배경색 → 사진 → 색 오버레이 → 스타일 구성 → 텍스트/로고입니다. `overlay_opacity`는 배경색이 사진을 얼마나 덮을지 결정합니다. 자체 배경을 생성하는 스타일(`artistic`, `hero`, `surreal`)은 사진이 설정되면 배경 생성을 건너뛰어 사진이 그대로 드러납니다.

### 미리보기

아래 예시는 `overlay_opacity`만 다릅니다 (같은 사진, `style = "editorial"`, 검정에 가까운 `background`). 클릭하면 확대됩니다.

<div class="og-style-grid">
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/bg-image-low.png" alt="오버레이가 낮은 배경 이미지" loading="lazy" />
    <span class="og-style-label"><code>overlay_opacity = 0.3</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/bg-image-low.png" alt="오버레이가 낮은 배경 이미지" />
        <p><code>overlay_opacity = 0.3</code> — 사진이 선명하게 유지됨</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/bg-image-mid.png" alt="오버레이가 중간인 배경 이미지" loading="lazy" />
    <span class="og-style-label"><code>overlay_opacity = 0.55</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/bg-image-mid.png" alt="오버레이가 중간인 배경 이미지" />
        <p><code>overlay_opacity = 0.55</code> — 사진과 텍스트의 균형</p>
      </div>
    </dialog>
  </div>
  <div class="og-style-card" onclick="this.querySelector('dialog').showModal()">
    <img src="/images/og-style-examples/bg-image-high.png" alt="오버레이가 높은 배경 이미지" loading="lazy" />
    <span class="og-style-label"><code>overlay_opacity = 0.8</code></span>
    <dialog onclick="if(event.target===this)this.close()">
      <div class="og-style-dialog">
        <button onclick="event.stopPropagation();this.closest('dialog').close()">&times;</button>
        <img src="/images/og-style-examples/bg-image-high.png" alt="오버레이가 높은 배경 이미지" />
        <p><code>overlay_opacity = 0.8</code> — 사진은 어둡게, 텍스트가 도드라짐</p>
      </div>
    </dialog>
  </div>
</div>

## 출력 포맷

PNG가 기본값입니다 — stb_truetype과 stb_image_write로 자체 렌더링하므로 외부 도구가 필요 없습니다. 시스템 폰트는 자동 감지되며(macOS는 Helvetica/Arial, Linux는 DejaVu/Liberation/Noto), 최후 수단으로 번들된 DejaVu Sans Bold를 사용합니다.

CJK 문자가 들어간 제목에는 CJK를 지원하는 `font_path`(예: Noto Sans CJK)가 필요합니다 — 번들 폰트는 라틴 문자만 지원합니다.

의존성 없는 SVG 출력이 필요하면 `format = "svg"`로 설정합니다. 다만 소셜 플랫폼은 일반적으로 SVG `og:image`를 렌더링하지 않습니다.

## 증분 생성

Hwaro는 생성 이미지 옆에 `.og_manifest.json`을 저장하고 입력이 바뀌지 않은 페이지를 건너뜁니다. 빌드 간에 출력 디렉터리를 유지하면(예: `--cache` 모드) 증분 생성이 자동으로 동작합니다 — `hahwul/hwaro` GitHub Action은 이를 알아서 처리합니다.

| 변경 | 재생성 대상 |
|--------|-------------|
| 페이지 제목, 설명, URL | 해당 페이지만 |
| OG 설정, 또는 로고/배경 이미지의 **파일 내용** | 전체 페이지 |
| 디스크에 이미지 파일이 없음 | 해당 페이지만 |

## 개발 서버 속도 개선

OG 생성은 대규모 사이트에서 가장 비용이 큰 빌드 단계 중 하나입니다. 두 가지 방법이 있습니다:

- `lazy_generate = true` — `hwaro serve`가 일괄 생성을 건너뛰고, 각 이미지는 해당 페이지의 첫 요청 때 렌더링된 뒤 캐시됩니다. `hwaro build`에는 영향이 없습니다. `hwaro serve --fast-start`와 잘 어울립니다.
- `hwaro build --skip-og-image` — OG 이미지를 아예 건너뜁니다.

## 동작

- 프론트 매터에 커스텀 `image`가 있는 페이지는 그대로 유지하고, 초안은 건너뜁니다
- 긴 제목은 자동으로 줄바꿈됩니다 (CJK 인식)
- 로고와 배경 이미지는 한 번만 로드해 전체 페이지에서 재사용합니다

## 출력

`/posts/hello-world/` 페이지는 `public/og-images/posts-hello-world.png`와 다음 태그를 만듭니다:

```html
<meta property="og:image" content="https://example.com/og-images/posts-hello-world.png">
```

특정 페이지에 커스텀 이미지를 쓰려면 프론트 매터에 `image`를 설정합니다:

```toml
+++
title = "My Post"
image = "/images/custom-og.png"
+++
```

## 함께 보기

- [SEO](/ko/features/seo/) — OpenGraph, Twitter 카드, 메타 태그
- [이미지 처리](/ko/features/image-processing/) — 반응형 이미지 리사이징
- [설정](/ko/start/config/) — 전체 설정 레퍼런스
