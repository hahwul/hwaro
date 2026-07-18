+++
title = "시작하기"
description = "Hwaro 설치부터 첫 실행까지"
weight = 1
sort_by = "weight"
+++

## Hwaro란?

Hwaro는 [Crystal](https://crystal-lang.org)로 작성한 가볍고 빠른 정적 사이트 생성기(SSG)입니다. TOML·YAML·JSON 프론트 매터가 붙은 마크다운 콘텐츠와 Jinja2 호환 템플릿(Crinja)을 처리해 고성능 정적 사이트를 만듭니다.

Hwaro는 **기성 테마에 기대지 않고 자기만의 웹사이트를 만들도록** 설계했습니다. 테마를 골라 손보는 대신 템플릿과 스타일을 처음부터 직접 만들기 때문에 사이트의 모든 부분을 원하는 대로 다룰 수 있습니다. 병렬 빌드, 증분 캐시, 라이브 리로드가 있는 개발 서버 덕분에 개발 경험도 빠르고 매끄럽습니다.

## 빠른 시작

```bash
# 설치 (전체 방법은 설치 문서 참고)
brew tap hahwul/hwaro && brew install hwaro

# 새 사이트 생성
hwaro init my-site --scaffold blog
cd my-site

# 라이브 리로드가 켜진 개발 서버 시작
hwaro serve
```

`http://localhost:3000`을 열어 사이트를 확인합니다.

## 왜 "Hwaro"인가?

Hwaro(화로)는 **Furnace**를 뜻하는 우리말로, 마인크래프트 한국어판에서도 같은 이름을 씁니다. 게임 속 화로는 원재료를 유용한 아이템으로 바꿔 주는 필수 도구입니다. Hwaro도 정적 사이트에서 같은 역할을 지향합니다 — 콘텐츠를 넣으면 완성된 웹사이트가 나옵니다.

![마인크래프트의 화로](/images/hwaro-minecraft.webp)
