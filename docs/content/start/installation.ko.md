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

## 사전 빌드 바이너리

macOS와 Linux용 사전 빌드 바이너리를 [GitHub Releases](https://github.com/hahwul/hwaro/releases) 페이지에서 받을 수 있습니다.

1. [최신 릴리스](https://github.com/hahwul/hwaro/releases/latest)에서 플랫폼에 맞는 바이너리를 내려받습니다.
2. PATH에 포함된 디렉터리로 바이너리를 옮깁니다.

```bash
# Linux(amd64) 예시
chmod +x hwaro-v*-linux-x86_64
sudo mv hwaro-v*-linux-x86_64 /usr/local/bin/hwaro
```

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
