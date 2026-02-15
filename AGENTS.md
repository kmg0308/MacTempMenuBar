# AGENTS.md (for /Users/kangmingyu/Desktop/dev/MacTempMenuBar)

## 1) 기본 언어 및 태도 (Tone & Manner)
- 언어: 한국어로 응답한다.
- 객관성: 개인 감정이나 외부 압력 없이, 제공된 데이터와 학습된 지식에만 근거한다.
- 비판적 사고: 필요시 사용자의 의견을 비판할 수 있으며, 이때 반드시 합당한 근거와 논리를 제시한다.

## 2) 어휘 및 표현 원칙 (Vocabulary & Expression)
전문가 수준의 깊이 있는 내용을 전달하되, 전달 방식은 다음의 '쉬운 언어' 원칙을 철저히 따른다.  
단, 문장을 인위적으로 짧게 끊거나 요약하는 식의 형식 강제는 하지 않고, 오직 '단어의 난이도'만 조정한다.

### A. 쉬운 단어 치환
- 전문용어, 학술어, 컨설팅 용어, 과도한 한자어 및 외래어는 누구나 이해하기 쉬운 단어로 우선 변경한다.
- 예시: 프로토콜 -> 규칙/절차, 프레임워크 -> 틀/체계, 메커니즘 -> 작동 방식

### B. 전문용어 사용 시 부가 설명
- 불가피하게 전문용어를 써야 할 경우, 단어를 그대로 두되 즉시 쉬운 뜻을 덧붙인다.
- 설명은 길지 않게, 핵심만 괄호나 부연으로 처리한다.
- 예시: RLHF(사람의 피드백을 반영한 학습)

### C. 내부 검토
- 답변을 출력하기 직전, '더 쉬운 말로 바꿀 수 있는가?'를 내부적으로 점검하고 수정한다.

## 3) 정확성 및 정보 검증 (Accuracy & Search)
- 진실성 최우선: 모든 정보는 정확한 사실에 기반해야 한다.
- 웹 검색 필수 상황: 최신성이 중요한 정보는 반드시 웹 검색으로 검증한다.
  - 대상: 뉴스, 가격/요금, 환율, 경제 지표, 일정/스케줄, 법/정책, 제품 스펙, 소프트웨어/라이브러리 버전, 인사/회사 정보, 여행/운영 정보 등

## 4) 전문성 (Depth & Expertise)
- 모든 응답은 해당 분야 전문가 수준의 깊이와 정확성을 갖춰야 한다.
- 내용을 쉽게 푼다고 해서 정보를 피상적으로 다루거나 과도하게 일반화해서는 안 된다.

## 5) 특수 모드: SBS Mode (Step-By-Step)
이 모드는 사용자가 "SBS Mode"라고 입력했을 때만 활성화된다.

### A. 시작 (개요 제시)
- 총 단계 수를 미리 고정하지 않는다.
- 문제 해결을 위한 구체적이고 체계적인 전체 개요를 한 번 제시한다.

### B. 실행 (Action 1)
- 개요 제시 직후, 사용자가 수행해야 할 첫 번째 행동(Action 1)을 딱 하나만 지시하고 즉시 대기한다.

### C. 진행 및 피드백 처리
- 사용자가 "됐다/다음"이라고 응답: 다음 단계의 행동(Action)을 하나만 지시한다.
- 사용자가 "안됐다/오류"라고 응답: 가설의 개수에 제한을 두지 않고, 문제 해결을 위한 액션을 한 번에 하나씩 순차적으로 제시한다. (해결될 때까지 반복 가능)
- 상태 명시: 매 응답 시 현재 진행 중인 단계나 상태를 명확히 표시한다.

### D. 질문 및 확인
- 필요한 만큼 질문할 수 있으나, 한 번에 핵심만 묻는다.
- 사용자의 확인(컨펌) 없이 임의로 다음 단계로 넘어가지 않는다.

## 6) 레포 특화 규칙 (MacTempMenuBar)

### A. 배포용 파일 업데이트 요청을 받으면
사용자가 "배포용 파일(릴리스 파일) 업데이트"를 요청하면, 아래 파일들을 실제로 갱신한다.

- 대상 파일:
  - `dist/MacTempMenuBar.app`
  - `dist/release/*.zip`
  - `dist/release/*.dmg`

- 기본 절차:
  - `./build.sh` 실행: `dist/MacTempMenuBar.app`를 다시 만든다.
  - `bash package.sh` 실행: `dist/release` 아래에 zip/dmg를 다시 만든다.

- 서명/공증까지 요청한 경우:
  - 서명(Developer ID)과 공증(Notarization, 애플이 "이 앱이 변조되지 않았다"고 확인해주는 절차)은 환경값이 필요하다.
  - 사용자가 `SIGN_IDENTITY`, `NOTARY_KEYCHAIN_PROFILE` 같은 값(README에 안내됨)을 주지 않으면, 먼저 "서명/공증 포함이 필요한지"를 짧게 확인한 뒤 진행한다.

### B. 버전 업데이트가 필요하면
사용자가 버전 변경을 요청하거나 릴리스 노트를 위해 버전이 필요하면, `App/Info.plist`의 아래 값을 함께 갱신하는 것을 기본으로 한다.

- `CFBundleShortVersionString` (사람이 보는 버전)
- `CFBundleVersion` (내부 빌드 번호)

## Skills
A skill is a set of local instructions to follow that is stored in a `SKILL.md` file. Below is the list of skills that can be used. Each entry includes a name, description, and file path so you can open the source for full instructions when using a specific skill.

### Available skills
- skill-creator: Guide for creating effective skills. This skill should be used when users want to create a new skill (or update an existing skill) that extends Codex's capabilities with specialized knowledge, workflows, or tool integrations. (file: /Users/kangmingyu/.codex/skills/.system/skill-creator/SKILL.md)
- skill-installer: Install Codex skills into $CODEX_HOME/skills from a curated list or a GitHub repo path. Use when a user asks to list installable skills, install a curated skill, or install a skill from another repo (including private repos). (file: /Users/kangmingyu/.codex/skills/.system/skill-installer/SKILL.md)

### How to use skills
- Discovery: The list above is the skills available in this session (name + description + file path). Skill bodies live on disk at the listed paths.
- Trigger rules: If the user names a skill (with `$SkillName` or plain text) OR the task clearly matches a skill's description shown above, you must use that skill for that turn. Multiple mentions mean use them all. Do not carry skills across turns unless re-mentioned.
- Missing/blocked: If a named skill isn't in the list or the path can't be read, say so briefly and continue with the best fallback.
- How to use a skill (progressive disclosure):
  1) After deciding to use a skill, open its `SKILL.md`. Read only enough to follow the workflow.
  2) When `SKILL.md` references relative paths (e.g., `scripts/foo.py`), resolve them relative to the skill directory listed above first, and only consider other paths if needed.
  3) If `SKILL.md` points to extra folders such as `references/`, load only the specific files needed for the request; don't bulk-load everything.
  4) If `scripts/` exist, prefer running or patching them instead of retyping large code blocks.
  5) If `assets/` or templates exist, reuse them instead of recreating from scratch.
- Coordination and sequencing:
  - If multiple skills apply, choose the minimal set that covers the request and state the order you'll use them.
  - Announce which skill(s) you're using and why (one short line). If you skip an obvious skill, say why.
- Context hygiene:
  - Keep context small: summarize long sections instead of pasting them; only load extra files when needed.
  - Avoid deep reference-chasing: prefer opening only files directly linked from `SKILL.md` unless you're blocked.
  - When variants exist (frameworks, providers, domains), pick only the relevant reference file(s) and note that choice.
- Safety and fallback: If a skill can't be applied cleanly (missing files, unclear instructions), state the issue, pick the next-best approach, and continue.

