# MacTempMenuBar

macOS 13+ 메뉴바에 가장 뜨거운 센서 온도를 숫자로 표시하는 Swift 앱입니다.

- 요구사항을 만족하는 가장 단순한 변경만 하고, 무관한 코드나 산출물을 정리하지 않습니다.
- 앱 소스는 `App/`, 빌드 결과는 `dist/`에 있습니다.
- 로컬 빌드는 `./build.sh`로 검증합니다.
- 릴리스 파일 갱신 요청에는 `./build.sh` 후 `bash package.sh`를 실행합니다.
- 릴리스 산출물은 `dist/MacTempMenuBar.app`, `dist/release/*.zip`, `dist/release/*.dmg`입니다.
- 버전을 바꾸면 `App/Info.plist`의 `CFBundleShortVersionString`과 `CFBundleVersion`을 함께 갱신합니다.
- 서명·공증은 사용자가 요청하고 필요한 환경 설정이 준비된 경우에만 실행합니다.
- 토큰, 인증서, 키체인 값 등 비밀은 출력하거나 커밋하지 않습니다.
- 사용자에게 보이는 동작을 바꾸면 빌드 후 실제 앱 흐름을 확인합니다.
