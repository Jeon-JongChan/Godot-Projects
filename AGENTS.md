# AGENTS.md — Godot-Projects 멀티 에이전트(Antigravity & Codex) 통합 지침

본 저장소(`Godot-Projects`)는 **Antigravity**와 **OpenAI Codex** 양쪽에서 `Claude-Code-Game-Studios` 78종 + Godot/VFX/Sprite 22종(총 100종) 스킬과 49종 전문 에이전트, 14종 규칙을 동일하게 사용할 수 있도록 구성되어 있습니다.

---

## 1. 스킬·에이전트·문서 경로

- **스킬 (총 100종):**
  - Antigravity: `.agent/skills/<skill-name>/SKILL.md`
  - Codex: `.agents/skills/<skill-name>/SKILL.md` (`.agent/skills`와 디렉터리 정션으로 동기화됨)
- **전문 에이전트 (49종):** `.agent/agents/<agent-name>.md`
- **개발 규칙 (14종):** `.agent/rules/<rule-name>.md`
- **프레임워크 내부 문서·템플릿:** `.agent/docs/`
- **엔진 레퍼런스 및 협업 원칙:** `docs/engine-reference/`, `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md`, `docs/WORKFLOW-GUIDE.md`
- **실제 Godot 게임 프로젝트:** `eradel/` (`eradel/app/project.godot`)

---

## 2. Claude Code 전용 표기 변환 규칙 (Antigravity / Codex 공통)

`Claude-Code-Game-Studios` 원본 스킬 본문에 남아 있는 Claude Code 전용 표기는 아래와 같이 현재 에이전트 도구의 네이티브 기능으로 매핑하여 실행합니다.

| 스킬 내 표기 (CCGS 원문) | Antigravity 매핑 | Codex 매핑 |
|---|---|---|
| `AskUserQuestion` | `ask_question` (또는 번호 목록으로 질문 후 대기) | `request_user_input` (또는 번호 목록으로 질문 후 대기) |
| `Agent` / `subagent_type` | `invoke_subagent` 또는 해당 `.agent/agents/<name>.md` 역할 로드 | `spawn_agent` 또는 해당 `.agent/agents/<name>.md` 역할 로드 |
| `Skill(<name>)` | `.agent/skills/<name>/SKILL.md`를 직접 읽어 실행 | `.agents/skills/<name>/SKILL.md`를 직접 읽어 실행 |
| `Read`, `Glob`, `Grep`, `Write`, `Edit` | `read_file`, `run_command`/`grep`, `write_file`, `edit_file` | 파일 읽기/검색 도구, `apply_patch` / 셸 |
| `bash .agent/.../*.sh` (Windows) | `C:\Program Files\Git\bin\bash.exe`로 실행 (`System32\bash.exe` WSL 릴레이 회피) | `C:\Program Files\Git\bin\bash.exe`로 실행 |

---

## 3. 협업 및 프로젝트 기본 원칙

- **질문 및 승인:** 설계·파일 수정 전 사용자에게 옵션과 대상 경로를 명확히 알리고 승인을 받습니다.
- **Godot 4.x 표준:** 정적 타입 GDScript, 시그널 기반 느슨한 결합, `docs/engine-reference/godot/`의 버전·Deprecated API 검증을 준수합니다.
- **작업 보고서:** 모든 작업 완료 시 `.docs/`에 `YYYY-MM-DD_HHMM_<topic>_report.md` 형식의 보고서를 작성합니다.
