# 프로젝트 코드 그래프 리포트 (eradel)

- 생성 시각: 2026-10-30T14:40:09.233Z (UTC)
- Git 커밋(built_at_commit): `0bc406d79b5c530a74d0453dc902654a592258de`

## 요약
- 전체 노드: 168개 (심볼 144개, 파일 9개)
- 전체 관계(링크): 163개
  - EXTRACTED (구문 직접 추출): 159개 (98%)
  - INFERRED (파일·임포트·수신자·이름 기반 해석): 4개 (2%)
  - AMBIGUOUS (미해결·다중 후보): 0개 (0%)
- 평균 관계 신뢰도 점수(confidence_score): 0.99
- 탐지된 커뮤니티: 5개
- 구문 오류 또는 부분 지원 문법 파일: 1개

## 핵심 추상화 (God Nodes)
1. `create_hit_crit` (function, `assets/audio/generate_sfx.py:L51-L94`) — 연결 1개 (유입 1, 유출 0) · 커뮤니티: create_hit_crit
2. `create_hit_normal` (function, `assets/audio/generate_sfx.py:L9-L49`) — 연결 1개 (유입 1, 유출 0) · 커뮤니티: create_hit_crit
3. `기획 문서` (module, `docs/design/README.md:L1-L36`) — 연결 0개 (유입 0, 유출 0) · 커뮤니티: 기획 문서
4. `1. 세계관` (module, `docs/old/영지의군주_기획문서_v0.4.md:L10-L47`) — 연결 0개 (유입 0, 유출 0) · 커뮤니티: 2.3 화면 스크립트
5. `10. 치료소` (module, `docs/old/영지의군주_기획문서_v0.4.md:L225-L244`) — 연결 0개 (유입 0, 유출 0) · 커뮤니티: 2.3 화면 스크립트
6. `11. 페널티 시스템` (module, `docs/old/영지의군주_기획문서_v0.4.md:L244-L254`) — 연결 0개 (유입 0, 유출 0) · 커뮤니티: 2.3 화면 스크립트
7. `12. 직업 체계` (module, `docs/old/영지의군주_기획문서_v0.4.md:L254-L287`) — 연결 0개 (유입 0, 유출 0) · 커뮤니티: 2.3 화면 스크립트
8. `13. 파티 관계` (module, `docs/old/영지의군주_기획문서_v0.4.md:L287-L307`) — 연결 0개 (유입 0, 유출 0) · 커뮤니티: 2.3 화면 스크립트
9. `14. 레벨업` (module, `docs/old/영지의군주_기획문서_v0.4.md:L307-L327`) — 연결 0개 (유입 0, 유출 0) · 커뮤니티: 2.3 화면 스크립트
10. `15. 마나석` (module, `docs/old/영지의군주_기획문서_v0.4.md:L327-L338`) — 연결 0개 (유입 0, 유출 0) · 커뮤니티: 2.3 화면 스크립트

## 의외의 연결 (Surprising Connections)
- 파일·커뮤니티 경계를 넘는 특이 연결이 없습니다.

## 순환 임포트 (Import Cycles)
- `docs/old/overview.md` → `docs/old/overview_detail.md` → `docs/old/overview.md`

## 커뮤니티 (Communities)
### 커뮤니티 #0: 2.3 화면 스크립트
- 노드 수: 142개 · 응집도(Cohesion): 0.01
- 주요 파일: docs/old/assets_plan.md, docs/old/game_design_document_template.md, docs/old/overview.md, docs/old/overview_detail.md, docs/old/영지의군주_기획문서_v0.4.md
- 대표 노드: 2.3 화면 스크립트, Eradel 씬 흐름 Overview, 4. 씬 전환 목록 (트리거 → 코드 위치), Eradel 씬·스크립트 Detail, 1. 프로젝트 개요, 1. 세계관, 1. 통신 모델, 12. 직업 체계
### 커뮤니티 #1: 1차 수정제안서.md
- 노드 수: 10개 · 응집도(Cohesion): 0.2
- 주요 파일: docs/1차 수정제안서.md
- 대표 노드: 1차 수정제안서.md, docs/스크린샷_30-10-2026_222328_claude.ai.jpeg, docs/스크린샷_30-10-2026_222412_claude.ai.jpeg, docs/스크린샷_30-10-2026_222423_claude.ai.jpeg, docs/스크린샷_30-10-2026_222448_claude.ai.jpeg, docs/스크린샷_30-10-2026_222526_claude.ai.jpeg, docs/스크린샷_30-10-2026_222546_claude.ai.jpeg, docs/스크린샷_30-10-2026_222557_claude.ai.jpeg
### 커뮤니티 #2: create_hit_crit
- 노드 수: 9개 · 응집도(Cohesion): 0.28
- 주요 파일: assets/audio/generate_sfx.py
- 대표 노드: create_hit_crit, create_hit_normal
### 커뮤니티 #3: 기획 문서
- 노드 수: 5개 · 응집도(Cohesion): 0.4
- 주요 파일: docs/design/README.md
- 대표 노드: 기획 문서, 넣기 좋은 문서, 파일 형식, 폴더 예시 (PDF + HTML UI)
### 커뮤니티 #4: godotTools.editorPath.godot4
- 노드 수: 2개 · 응집도(Cohesion): 1
- 주요 파일: .vscode/settings.json
- 대표 노드: godotTools.editorPath.godot4, settings.json

## 확인이 필요한 관계 (Ambiguous Edges)
- 미해결(AMBIGUOUS) 관계가 없습니다.

## 지식 공백 (Knowledge Gaps)
- 모든 심볼이 최소 1개 이상의 의미 관계로 연결되어 있습니다.

## 추천 질문 (Suggested Questions)
- 가장 연결이 집중된 핵심 추상화 `create_hit_crit` (1개 연결, 커뮤니티 `create_hit_crit`)의 역할과 하위 의존성은 적절히 분리되어 있습니까?
- 응집도가 가장 낮은 커뮤니티 `2.3 화면 스크립트` (Cohesion 0.01, 노드 142개)를 더 작은 모듈로 분리할 수 있습니까?
