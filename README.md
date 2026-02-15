# MacTempMenuBar

**한국어 | English**

메뉴바에 현재 온도를 `77` 같은 **숫자 하나**로 보여주는 작은 macOS 앱입니다.  
A tiny macOS menu bar app that shows your current temperature as a **single number**.

가볍게 동작하도록 만들었습니다.
Built to stay lightweight.

- 용량: 앱 번들 약 **1.5MB** (빌드/버전에 따라 조금 달라질 수 있음)
- 기본 갱신: **5초**(1/2/5초로 변경 가능)

[![Download DMG](https://img.shields.io/badge/Download-DMG-0A84FF?style=for-the-badge&logo=apple)](https://github.com/kmg0308/MacTempMenuBar/releases/latest/download/MacTempMenuBar.dmg)
[![Download ZIP](https://img.shields.io/badge/Download-ZIP-0A84FF?style=for-the-badge&logo=apple)](https://github.com/kmg0308/MacTempMenuBar/releases/latest/download/MacTempMenuBar.zip)

- More downloads: [Releases (latest)](https://github.com/kmg0308/MacTempMenuBar/releases/latest)
- Requirements: macOS 13+ (MenuBarExtra). Tested on Apple Silicon (Intel not tested).

---

## 한국어

### 기능
- 메뉴바 숫자 표시(가장 뜨거운 센서를 자동으로 선택)
- 급상승 알림(10초 내 +8도, 선택)
- 최근 10분 추세(텍스트 그래프)
- CSV 로그 저장(선택)
- 로그인 시 자동 실행(선택)
- 앱 업데이트 확인(메뉴에서 `앱 업데이트 확인…`)

### 설치(비개발자)
1. [Releases](https://github.com/kmg0308/MacTempMenuBar/releases/latest)에서 `*.dmg` 또는 `*.zip` 다운로드
2. `MacTempMenuBar.app`을 `/Applications`로 옮기기
3. 앱 실행하면 메뉴바에 숫자가 뜹니다

### 업데이트
- 메뉴에서 `앱 업데이트 확인…`을 누르면 새 버전이 있는지 확인하고, 있으면 업데이트를 안내합니다.

### 처음 실행이 막힐 때
- "확인되지 않은 개발자" 경고가 뜨면 Finder에서 앱 우클릭 -> `열기`를 한 번 선택해보세요.
- 서명/공증(애플이 "이 앱이 변조되지 않았다"고 확인해주는 절차)이 된 빌드는 이런 경고가 덜 뜹니다.

<details>
<summary>개발자용: 소스에서 빌드</summary>

```bash
./build.sh
open dist/MacTempMenuBar.app
```
</details>

<details>
<summary>유지보수용: 릴리스(배포)</summary>

이 레포는 `v0.3.4` 같은 태그를 push하면 GitHub Actions가 zip/dmg를 만들어 Releases에 올립니다.

```bash
git tag v0.3.5
git push origin v0.3.5
```

- 공증까지 자동으로 하고 싶다면 `notary-setup.sh` / `package.sh`와 GitHub Secrets 설정이 필요합니다.
- 앱 안에서 업데이트 알림/설치를 하려면(Sparkle, 업데이트 확인 기능) `SPARKLE_ED_KEY`(업데이트 서명용 개인키) Secret도 설정해야 합니다.
</details>

---

## English

### Features
- Shows a single number in the menu bar (auto-picks the hottest sensor)
- Rapid rise alert (+8C within 10 seconds, optional)
- 10-minute trend (text sparkline)
- CSV logging (optional)
- Launch at login (optional)
- Update check (use the `앱 업데이트 확인…` menu item)

### Install (non-developers)
1. Download `*.dmg` or `*.zip` from [Releases](https://github.com/kmg0308/MacTempMenuBar/releases/latest)
2. Move `MacTempMenuBar.app` to `/Applications`
3. Run it and you'll see the number in the menu bar

### Update
- Use the `앱 업데이트 확인…` menu item to check for updates and install when available.

### If macOS blocks the first launch
- In Finder, right click the app -> `Open` (usually fixes the Gatekeeper prompt).
- Notarized builds (Apple verified) show fewer prompts.

<details>
<summary>For developers: build from source</summary>

```bash
./build.sh
open dist/MacTempMenuBar.app
```
</details>

<details>
<summary>For maintainers: releases</summary>

This repo can publish a release automatically via GitHub Actions when you push a tag like `v0.3.4`.

```bash
git tag v0.3.5
git push origin v0.3.5
```

- For code signing + notarization, see `notary-setup.sh` / `package.sh` and the GitHub Secrets mentioned in those scripts.
- For in-app update prompts (Sparkle), set the `SPARKLE_ED_KEY` (private signing key) GitHub Actions secret too.
</details>
