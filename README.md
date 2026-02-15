# MacTempMenuBar

Apple Silicon Mac에서 SMC(AppleSMCKeysEndpoint) 온도 센서 값을 읽어서 메뉴바에 `NN` 형태(숫자 only)로 표시하는 최소 메뉴바 앱.

- 요구사항:
  - macOS 13 이상 (MenuBarExtra 사용)
  - Apple Silicon(M1/M2/M3...)에서 동작 확인

- 표시값: 온도 키들 중 가장 뜨거운 센서(자동 선택)
- 메뉴바 표시: 숫자 only (예: `77`)
- 색상 경고: 사용자 조정 임계치 기반(기본 85도/95도)
- 급상승 알림: 10초 내 +8도 상승 감지
- 스파크라인: 최근 10분 추세 텍스트 그래프
- 설정 메뉴:
  - 로그인 시 자동 실행
  - 갱신 주기 (1초 / 2초 / 5초)
  - CSV 로그 저장 토글(일별 파일 로테이션)
  - 로그 폴더 열기

## 다운로드/설치 (비개발자)

1) GitHub Releases에서 최신 버전 다운로드:
- https://github.com/kmg0308/MacTempMenuBar/releases/latest

2) `*.dmg`를 받았다면:
- DMG 열기
- `MacTempMenuBar.app`을 `/Applications`로 드래그(복사)

3) `*.zip`을 받았다면:
- 압축 풀기
- `MacTempMenuBar.app`을 `/Applications`로 옮기기

4) 실행:
- `/Applications/MacTempMenuBar.app` 실행
- Dock 아이콘은 안 보일 수 있고(메뉴바 앱), 상단바에 숫자가 나타납니다.

참고(처음 실행 경고):
- "확인되지 않은 개발자" 경고가 뜨면 Finder에서 앱을 우클릭 -> "열기"를 한 번 해주면 통과되는 경우가 많습니다.
- 공증(Notarization, 애플 확인 절차)이 된 앱이면 이런 경고가 거의 안 뜹니다.

## 업데이트

- GitHub Releases에서 새 버전을 다시 다운로드
- 기존 `/Applications/MacTempMenuBar.app`을 새 파일로 교체

## 빌드

```bash
cd /Users/kangmingyu/Desktop/dev/MacTempMenuBar
./build.sh
```

출력:

```
Built: /Users/kangmingyu/Desktop/dev/MacTempMenuBar/dist/MacTempMenuBar.app
```

## 실행

Finder에서 `/Users/kangmingyu/Desktop/dev/MacTempMenuBar/dist/MacTempMenuBar.app` 더블클릭.

또는:

```bash
open /Users/kangmingyu/Desktop/dev/MacTempMenuBar/dist/MacTempMenuBar.app
```

## 패키징(zip + dmg)

```bash
cd /Users/kangmingyu/Desktop/dev/MacTempMenuBar
bash package.sh
```

출력:

```text
/Users/kangmingyu/Desktop/dev/MacTempMenuBar/dist/release/*.zip
/Users/kangmingyu/Desktop/dev/MacTempMenuBar/dist/release/*.dmg
```

## 배포(릴리스 만들기)

방법 A) 수동 업로드(가장 단순):
- `bash package.sh` 실행해서 `dist/release/*.zip`, `dist/release/*.dmg` 생성
- GitHub 웹에서 Releases 페이지에서 새 릴리스 만들고 파일 업로드

방법 B) 태그로 자동 릴리스(GitHub Actions):
- `v0.3.3` 같은 태그를 push하면 GitHub Actions가 zip/dmg를 만들고 GitHub Release에 자동 업로드합니다.
- 예시:
  - `git tag v0.3.4`
  - `git push origin v0.3.4`
- GitHub Desktop만으로 태그 작업이 불편하면, 위 2줄만 터미널에서 실행하는 게 제일 빠릅니다.

## Developer ID 서명 + 공증(Notarization)

1) Developer ID 인증서 확인

```bash
security find-identity -v -p codesigning
```

2) 공증 인증정보(키체인 프로파일) 저장

```bash
cd /Users/kangmingyu/Desktop/dev/MacTempMenuBar
NOTARY_PROFILE="mactemp-notary" ./notary-setup.sh
```

Apple ID 모드:

```bash
APPLE_ID="you@example.com" \
APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
TEAM_ID="ABCDE12345" \
NOTARY_PROFILE="mactemp-notary" \
./notary-setup.sh
```

API Key 모드:

```bash
ASC_KEY_PATH="/absolute/path/AuthKey_XXXXXX.p8" \
ASC_KEY_ID="XXXXXX1234" \
ASC_ISSUER="00000000-0000-0000-0000-000000000000" \
NOTARY_PROFILE="mactemp-notary" \
./notary-setup.sh
```

3) 서명 + 공증 포함 패키징

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_KEYCHAIN_PROFILE="mactemp-notary" \
bash package.sh
```

옵션:
- `NOTARIZE_DMG=1` (기본값): dmg도 추가 공증/스테이플
- `NOTARY_TIMEOUT=20m` (기본값)

### GitHub Actions로 자동 서명/공증(선택)

이 레포는 `v0.3.4` 같은 태그를 push하면 GitHub Actions가 zip/dmg를 만들어 Releases에 올립니다.  
기본은 "서명/공증 없이" 빌드합니다(처음 실행 경고가 뜰 수 있음).

서명/공증까지 자동으로 하려면 GitHub Repository Secrets에 아래 값을 넣으면 됩니다(전부 필요):
- `MACOS_CERT_P12_BASE64`: Developer ID 인증서(.p12) 내용을 base64로 인코딩한 값
- `MACOS_CERT_P12_PASSWORD`: 위 p12 비밀번호
- `MACOS_SIGN_IDENTITY`: 코드서명에 쓸 이름(예: `Developer ID Application: Your Name (TEAMID)`)
- `ASC_KEY_P8_BASE64`: App Store Connect API Key(.p8) 내용을 base64로 인코딩한 값
- `ASC_KEY_ID`: API Key ID
- `ASC_ISSUER`: Issuer ID

base64 만들기 예시(macOS):

```bash
base64 -i /absolute/path/to/cert.p12 | pbcopy
base64 -i /absolute/path/to/AuthKey_XXXXXX.p8 | pbcopy
```

## 구현 메모

- 온도 값은 `flt ` 타입의 경우 little-endian float로 해석합니다(예: `TC33`).
