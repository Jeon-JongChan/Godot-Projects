# Memorial Chronicle (기념관 연대기 시스템)

> **Status**: Draft Complete
> **Author**: User + Antigravity
> **Last Updated**: 2026-11-24
> **Last Verified**: 2026-11-24
> **Implements Pillar**: 세대 계승의 서사적 체감 (영구 기록 연대기)

## Summary

역대 영주들의 통치 기간, 전사 용병들의 유품 최종 처리 상태(`추모` vs `착취` vs `마감`), 계승된 저주, 심층 보스 봉인 기록을 세대를 넘어 영구 보존하고 기념관 UI에서 열람할 수 있게 하는 서사 기록 시스템이다.

> **Quick reference** — Category: `UI / Narrative` · Layer: `Feature` · Priority: `MVP` · Key deps: `GameState`, `SaveManager`, `soul-exploitation`, `generation-succession`, `rift-seal-endless`

## Overview

**기념관 연대기(Memorial Chronicle)**는 세대 교체로 자원·건물·용병이 모두 사라져도 **영지 에라델의 역사만큼은 지워지지 않음**을 보여주는 영속 데이터 및 UI 시스템이다. 플레이어는 기념관의 연대기 탭에서 역대 영주별 통치 요약과 전사 용병 한 명 한 명의 이름·직업·처리 결과(안치됨 / 균열에 바쳐짐 / 축복으로 태워짐)를 열람하며 자신의 도덕적 선택이 남긴 흔적을 대면한다.

## Player Fantasy

플레이어는 새 세대를 시작해 잿빛 기념관을 열었을 때, 전대 영주가 몇 명의 용병을 태워 버텼는지 차가운 연대기 목록으로 마주하며 "이번 세대는 다르게 통치할 것인가"라는 서사적 동기부여를 얻는다.

## Detailed Design

### Core Rules

1. **세대별 스냅샷 영구 기록 (`chronicle_entries: Array[Dictionary]`, `commit_chronicle_generation(snapshot)`):**
   - `generation-succession` 발동 시 또는 `rift-seal-endless` 심층 보스 격파 시 `commit_chronicle_generation(snapshot)`으로 현재 세대의 요약 레코드를 Upsert한다(동일 `generation` 엔트리가 이미 존재하면 `sealed_boss: true`와 봉인 `outcome`을 보존한 채 집계·`days_survived`·`relic_records`를 갱신).
   - 스냅샷 필드: `generation: int`, `days_survived: int`, `outcome: String` (`"FALLEN"` / `"SEALED_ATONEMENT"` / `"SEALED_TYRANT"`), `sealed_boss: bool`, `memorialized_count: int` *(정식 추모 `25G`, `state == "MEMORIALIZED"` 횟수)*, `pauper_buried_count: int` *(약식 안치 `0G`, `state == "PAUPER_BURIED"` 횟수)*, `exploited_count: int`, `expired_count: int`, `peak_permanent_stress: int`, `inherited_curses: Array[String]` *(해당 세대가 짊어졌던 저주 목록, 깊은 복사)*, `relic_records: Array[Dictionary]` *(깊은 복사)*.
2. **현 세대 실시간 열람:**
   - 현재 진행 중인 세대의 처리 완료 유품(`MEMORIALIZED`, `PAUPER_BURIED`, `EXPLOITED_*`)도 기념관 연대기 상단("현재 세대")에 즉시 표시한다.
3. **용량 및 성능 상한:**
   - 무한 세대(`rift-seal-endless`) 진행 시 세이브 파일 비대화를 막기 위해 상세 `relic_records`는 최근 **10세대**까지만 개별 용병 단위로 보관하고, 그 이전 세대는 집계 수치(`days_survived`, `memorialized_count`, `pauper_buried_count`, `exploited_count`, `expired_count`, `outcome`, `sealed_boss`)만 압축 유지한다.

### States and Transitions

| 상태 | 설명 | 허용 전이 |
|---|---|---|
| `CURRENT_GEN_LIVE` | 현 세대 진행 중 (실시간 유품 이력 표시) | → `ARCHIVED_FULL` (세대 종료 시 상세 기록 확정) |
| `ARCHIVED_FULL` | 최근 10세대 이내 영구 상세 기록 | → `ARCHIVED_COMPACT` (10세대 초과 시 집계 압축) |
| `ARCHIVED_COMPACT` | 10세대 초과 압축 요약 기록 | 없음 (영구 보존) |

## Formulas

이 시스템은 별도의 전투/경제 공식이 없으며 단순 합산 카운트(`memorialized_count`, `exploited_count`, `expired_count`)와 보관 윈도우(`max_detailed_generations = 10`)만 사용한다.

## Tuning Knobs

| 파라미터 | 기본값 | 탐색 범위 | 조정 시 체감 영향 |
|---|---|---|---|
| `max_detailed_generations` | `10` | `5–20` | 무한 세대 플레이 시 세이브 파일 크기와 상세 회고 범위 균형 |

## Edge Cases

- **If 1세대 첫날에 아직 전사 용병이 없을 때 기념관 연대기를 열면**: 빈 목록 크래시 대신 "아직 에라델의 잿빛 돌비에 새겨진 이름이 없습니다." 안내 문구를 표시한다.
- **If 동일 세대에서 심층 보스를 봉인한 뒤 계속 플레이하다가 이후 스트레스 100으로 몰락하면**: 보스 봉인 기록은 해당 세대 엔트리의 `sealed_boss: true` 플래그로 갱신하고, 몰락 시 최종 `days_survived`를 업데이트해 중복 세대 항목이 생기지 않게 한다.
- **If 구버전 세이브에 `chronicle_entries` 키가 없으면**: `GameState.from_dict()`가 빈 배열 `[]`로 초기화한다.

## Dependencies

| 대상 시스템 | 방향 | 유형 | 데이터 인터페이스 | 상태 |
|---|---|---|---|---|
| `soul-exploitation` | Upstream | Soft | `soul_relics` 최종 상태 및 카운트 | GDD 작성됨 ([soul-exploitation.md](file:///d:/Projects/_Personal/Godot-Projects/design/gdd/soul-exploitation.md)) |
| `generation-succession` | Upstream | Hard | 세대 교체 시 스냅샷 커밋 | GDD 작성됨 ([generation-succession.md](file:///d:/Projects/_Personal/Godot-Projects/design/gdd/generation-succession.md)) |
| `rift-seal-endless` | Upstream | Soft | 심층 보스 봉인 및 엔딩 유형 기록 | GDD 작성됨 ([rift-seal-endless.md](file:///d:/Projects/_Personal/Godot-Projects/design/gdd/rift-seal-endless.md)) |
| `SaveManager` | Upstream | Hard | `chronicle_entries` 직렬화/역직렬화 | 기존 코드 구현됨 (확장 필요) |

## Acceptance Criteria

- **AC-1 (세대 스냅샷 보존):** **GIVEN** 1세대에서 추모 2회·착취 3회를 수행한 뒤 세대 교체가 발생했을 때, **WHEN** 2세대 기념관 연대기를 조회하면, **THEN** 1세대 엔트리에 `memorialized_count == 2`, `exploited_count == 3`, `outcome == "FALLEN"`이 정확히 보존되어 있다.
- **AC-2 (10세대 초과 압축):** **GIVEN** 12세대까지 진행되어 `chronicle_entries.size() == 12`일 때, **WHEN** 1세대·2세대 엔트리를 조회하면, **THEN** 집계 수치는 유지되고 상세 `relic_records`는 비워져 세이브 크기가 상한 내로 유지된다.
- **AC-3 (빈 연대기 안전 처리):** **GIVEN** `chronicle_entries`와 `soul_relics`가 모두 비어 있을 때, **WHEN** 기념관 연대기 탭을 열면, **THEN** 오류 없이 빈 상태 안내 문구가 표시된다.
