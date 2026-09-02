+++
title = "설치"
description = "소스 또는 사전 빌드 바이너리로 Hwaro 설치"
weight = 1
toc = true
+++

Hwaro는 Crystal로 작성되었습니다. 소스에서 직접 빌드하거나 사전 빌드된 바이너리로 설치하면 됩니다.

## Homebrew

```bash
brew tap hahwul/hwaro
brew install hwaro
```

## Snapcraft

```bash
sudo snap install hwaro
```

## APK (Alpine Linux)

[최신 릴리스](https://github.com/hahwul/hwaro/releases/latest)에서 `.apk` 패키지를 내려받아 설치합니다:

```bash
apk add --allow-untrusted hwaro-*.apk
```

## DEB (Debian/Ubuntu)

[최신 릴리스](https://github.com/hahwul/hwaro/releases/latest)에서 `.deb` 패키지를 내려받아 설치합니다:

```bash
sudo dpkg -i hwaro_*_amd64.deb
```

## RPM (Fedora/RHEL/CentOS)

[최신 릴리스](https://github.com/hahwul/hwaro/releases/latest)에서 `.rpm` 패키지를 내려받아 설치합니다:

```bash
sudo rpm -i hwaro-*.x86_64.rpm
```

## AUR (Arch Linux)

```bash
yay -S hwaro
```

## Nix

### 설치

```bash
nix profile install github:hahwul/hwaro
```

### 설치 없이 실행

```bash
nix run github:hahwul/hwaro -- --version
```

### 개발 셸

```bash
nix develop github:hahwul/hwaro
```

개발 셸에는 Crystal, `shards`, `just`, `crystal2nix`가 함께 들어 있어 다른 것을
설치하지 않아도 `just build`와 `just test`를 바로 실행할 수 있습니다.

### 플레이크 입력으로 사용하기

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.hwaro.url = "github:hahwul/hwaro";

  outputs = { nixpkgs, hwaro, ... }: {
    # `hwaro.packages.<system>.hwaro`를 쓰거나, `hwaro.overlays.default`를
    # nixpkgs 오버레이에 추가한 뒤 `pkgs.hwaro`로 사용하세요.
  };
}
```

지원 시스템은 `x86_64-linux`, `aarch64-linux`, `aarch64-darwin`입니다
(nixpkgs-unstable가 Intel macOS 지원을 중단했습니다). 플레이크가 공식 Crystal
툴체인을 고정해 두므로 컴파일러를 소스에서 빌드할 필요가 없습니다.

## 사전 빌드 바이너리

macOS와 Linux용 사전 빌드 바이너리를 [GitHub Releases](https://github.com/hahwul/hwaro/releases) 페이지에서 받을 수 있습니다.

1. [최신 릴리스](https://github.com/hahwul/hwaro/releases/latest)에서 플랫폼에 맞는 바이너리를 내려받습니다.
2. PATH에 포함된 디렉터리로 바이너리를 옮깁니다.

```bash
# Linux(amd64) 예시
chmod +x hwaro-v*-linux-x86_64
sudo mv hwaro-v*-linux-x86_64 /usr/local/bin/hwaro
```

### macOS

macOS 배포물은 단일 바이너리가 아니라 tarball입니다. 압축을 풀면 `hwaro`와
번들된 OpenSSL이 담긴 `lib/` 디렉터리가 나오고, 바이너리는 이 dylib들을
`@executable_path/lib` 경로로 읽습니다. 따라서 **`lib/`를 항상 바이너리와 함께
옮겨야 합니다.** 바이너리만 떼어 옮기면 실행되지 않습니다.

```bash
tar -xzf hwaro-v*-osx-arm64.tar.gz
sudo mkdir -p /usr/local/libexec/hwaro
sudo cp -R hwaro lib /usr/local/libexec/hwaro/
sudo ln -sf /usr/local/libexec/hwaro/hwaro /usr/local/bin/hwaro
```

심볼릭 링크는 안전합니다. macOS가 `@executable_path`를 계산하기 전에 링크를
먼저 해석하므로 dylib을 그대로 찾습니다. Homebrew도 같은 방식으로 설치합니다.

> **v0.20.0 한정.** 이 릴리스의 macOS tarball은 코드 서명이 깨진 상태로
> 배포되어, Apple Silicon에서는 실행 즉시 프로세스가 종료됩니다
> (`zsh: killed hwaro`). Gatekeeper가 아니라 서명 검증 문제라 quarantine
> 속성을 지워도 해결되지 않습니다. 상위 릴리스로 올리거나, 압축을 푼 자리에서
> 직접 다시 서명하세요: `codesign --force --sign - lib/*.dylib hwaro`

## 소스 빌드

### 사전 요구 사항

- [Crystal](https://crystal-lang.org/install/) 1.19+
- Git

### 빌드

```bash
git clone https://github.com/hahwul/hwaro
cd hwaro
shards install
shards build --release --no-debug
```

바이너리는 `./bin/hwaro`에 생성됩니다.

> Crystal **1.21 이상**이 필요합니다. 병렬 페이지 렌더링은 `src/main.cr`에서
> Crystal 기본 실행 컨텍스트 크기를 조정해 켜지므로 별도 빌드 플래그가
> 필요 없습니다. 워커 수는 `CRYSTAL_WORKERS=N`으로 조정할 수 있습니다(기본값은
> CPU 코어 수). 예전 `-Dpreview_mt` 플래그는 넣지 마세요. Crystal 1.21에서
> deprecated 되었고, 해당 스케줄러는 프로세스 종료 시 멈출 수 있습니다.
>
> `hwaro build` 실행 시(소스 빌드뿐 아니라 모든 설치 방식에서) Hwaro는
> Boehm GC를 함께 튜닝합니다(`GC_MARKERS=1`, `GC_INITIAL_HEAP_SIZE=256M`).
> 할당이 많은 사이트에서 빌드가 3~5배 빨라지는 것을 측정했으며, 대신
> 빌드 중 피크 메모리 사용량이 늘어납니다. 두 환경 변수를 직접
> export하면 내장 기본값보다 우선하고, `--memory-limit` 사용 시 힙
> 프리사이즈는 자동으로 비활성화됩니다. 자세한 내용은
> [전역 플래그 표](@/start/cli.md)를 참고하세요.

### PATH 등록 (선택)

```bash
# PATH에 포함된 디렉터리로 복사
sudo cp ./bin/hwaro /usr/local/bin/

# 또는 bin 디렉터리를 PATH에 추가
export PATH="$PATH:$(pwd)/bin"
```

## 설치 확인

```bash
hwaro --version
```

## 다음 단계

- [첫 사이트 만들기 →](/ko/start/first-site/)
