# MacTempMenuBar

Apple Silicon Mac에서 SMC(AppleSMCKeysEndpoint) 온도 센서 값을 읽어서 메뉴바에 `NN` 형태(숫자 only)로 표시하는 최소 메뉴바 앱.

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

## 구현 메모

- 온도 값은 `flt ` 타입의 경우 little-endian float로 해석합니다(예: `TC33`).
