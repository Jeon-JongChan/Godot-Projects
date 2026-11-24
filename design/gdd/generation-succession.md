# Generation Succession (세대 교체 & 저주 계승 시스템)

> **Status**: In Review (2nd Revision Applied — Ready for Re-Review)
> **Author**: User + Antigravity
> **Last Updated**: 2026-11-24
> **Last Verified**: 2026-11-24
> **Implements Pillar**: 혹독한 세대 교체 (강화·자원 유실 + 전대 저주 일부 계승)

## Summary

영주의 총 스트레스가 100에 도달해 쓰러져도 게임이 끝나지 않고, 날짜·자원·용병·건물/장비 강화치·현재 엔드리스 사이클이 초기화된 채 기념관 연대기·최고 봉인 기록과 전대 영주의 착취 낙인에서 비롯된 저주 일부만 물려받아 차기 세대로 이어가는 로그라이트 순환 시스템이다. 몰락 확정 시점에 단일 호출 주체(`GameState._check_game_over()`)가 유품 마감·연대기 Upsert 커밋·저주 추첨·초기화·자동 저장을 원자적으로 완료하고, 기존 `SCENE_GAMEOVER` 화면을 세대 교체 결산(`SUCCESSION_SUMMARY`) 화면으로 재사용해 세이브 스컴을 방지한다.

> **Quick reference** — Category: `Progression` · Layer: `Core` · Priority: `MVP` · Key deps: `GameState`, `SaveManager`, `soul-exploitation`, `memorial-chronicle`, `rift-seal-endless`

## Overview

**세대 교체 & 저주 계승 시스템(Generation Succession)**은 `GameState.game_over` 시그널(총 스트레스 100 도달)을 영구 패배가 아닌 **세대 전환 이벤트**로 변환한다. 현 세대 영주가 몰락하면 `generation_number`가 `+1` 증가하고, 골드·마나석·철광석·날짜·건물 레벨·용병 로스터·장비 강화치·현재 `endless_cycle`은 새 게임 수준으로 초기화된다. 대신 현 세대의 통치 기록과 최고 엔드리스 기록(`max_endless_cycle`, `boss_sealed_count`)은 `memorial-chronicle`에 영구 보존되며, 현 세대가 누적한 착취 낙인(`brand_stacks`)과 통치 기여도(`days_survived`, `expeditions_cleared_this_gen`)에 따라 산출된 **계승 저주(Inherited Curses)**가 다음 세대에 적용되어 이전 세대의 죄책감이 다음 통치에 실질적인 제약으로 남는다.

## Player Fantasy

플레이어는 한 명의 영주가 무너지는 비극 앞에서도 "영지 에라델의 역사는 끝나지 않는다"는 묵직한 계승감을 느낀다. 공들여 올린 건물과 장비가 잿더미로 돌아가는 상실감과 함께, 전대 영주가 원혼을 태워 남긴 저주를 안고 새 세대를 다시 일으켜 세워야 하는 혹독한 다크 판타지 연대기의 주인이 된다.

## Detailed Design

### Core Rules

1. **세대 교체 발동 · 단일 호출 주체 · 재진입 가드 (`begin_succession(rng: RandomNumberGenerator = null)`):**
   - **단일 호출 주체 및 테스트 격리:** `GameState._check_game_over()`가 `total_stress() >= MAX_STRESS(100)`을 감지했을 때 `game_over` 시그널 발행 직전(또는 직후 단일 경로)에 `if auto_succession_enabled and not _in_succession:` 조건으로 `begin_succession()`을 **단 한 번만** 실행한다.
     - `auto_succession_enabled: bool = true` (기본값 `true`; `soul-exploitation.md` AC-7 등 초기화 전 상태를 검증하는 격리 단위 테스트에서만 `false`로 전환 가능).
     - `_in_succession: bool = false` 재진입 가드를 두어 동일 프레임 내 중복 `add_*_stress()` 호출이나 `SUCCESSION_SUMMARY` 상태에서 `begin_succession()`이 2회 실행되는 것을 원천 차단한다.
   - **원자적 처리 및 세이브 스컴 방지:** `begin_succession(rng)`은 아래 2~6단계를 **결산 화면 진입 직전에 원자적으로 완료**하고, `unseen_succession_notice = true`로 설정한 뒤 **`GameState.save_game()`** 래퍼(`SaveManager.auto_save()` 호출, 헤드리스 단위 테스트에서 오토로드 부재 시 안전 폴백)를 즉시 실행한다.
   - **씬 전환 계약 (모든 몰락 경로 통합):**
     - 영지 내 몰락(`exploit_relic()`, `rest_estate_day()`, 영지 칙령 등): `estate.gd`의 단일 `game_over` 리스너가 `get_tree().change_scene_to_file.call_deferred(GameState.SCENE_GAMEOVER)`를 호출하며, `not GameState.pending_succession_summary.is_empty()`인 동안 `estate.gd`의 `rebuild()` 호출을 건너뛰어 1프레임 깜빡임을 방지한다.
     - 원정 귀환 몰락(`dungeon_result.gd:_on_return()`): `return_to_estate()` 완료 후 이미 스트레스가 리셋되어 있으므로 기존 `total_stress() >= MAX_STRESS` 분기를 **`if not GameState.pending_succession_summary.is_empty():`**로 교체해 `SCENE_GAMEOVER`로 진입한다.
   - **결산 화면 재사용:** 기존 `SCENE_GAMEOVER`(`res://scenes/flow/game_over.tscn`)를 **세대 교체 결산(`SUCCESSION_SUMMARY`)** 화면으로 전면 교체해 `pending_succession_summary` 전용 데이터를 표시한다. `[제 N+1대 영지 시작]` 클릭 시 `pending_succession_summary = {}`, `unseen_succession_notice = false`로 정리 후 `GameState.save_game()`을 호출하고 `SCENE_ESTATE`로 복귀한다.

2. **미처리 유품 선행 마감 및 몰락 시점 일수 통일:**
   - **몰락 시점 일수(`days_survived_at_fall`) 통일:** `return_to_estate()` / `rest_estate_day()`의 6단계 배치 정산에서는 4단계에 이미 `day += 1`이 선행되므로, 배치 정산 중 몰락 시에는 **`days_survived_at_fall = maxi(1, day - 1)`**을 사용하고 영지 내 직접 몰락(`exploit_relic()`, 칙령 등) 시에는 **`days_survived_at_fall = day`**를 사용한다. *(4일차 귀환 몰락과 4일차 영지 착취 몰락 간 off-by-one 편차 제거.)*
   - 연대기 스냅샷 기록 직전에 현 세대의 잔여 `UNRESOLVED` 유품을 모두 `EXPIRED_ON_SUCCESSION`(`resolved_day = days_survived_at_fall`) 상태로 마감하고 다음 세대로 이월하지 않는다.

3. **연대기 스냅샷 Upsert 커밋 (`memorial-chronicle` 계약 위임):**
   - `begin_succession()`은 `chronicle_entries`에 직접 `append`하지 않고 `memorial-chronicle`의 커밋 계약 **`commit_chronicle_generation(snapshot: Dictionary)`**를 호출한다.
   - **스냅샷 필드 (모든 배열/딕셔너리는 `duplicate(true)` 깊은 복사 필수):**
     - `generation: int` (현 `generation_number`)
     - `days_survived: int` (`days_survived_at_fall`)
     - `outcome: String` (`"FALLEN"` — 단, 동일 `generation`의 보스 봉인 엔트리가 이미 존재하면 기존 `SEALED_ATONEMENT`/`SEALED_TYRANT`와 `sealed_boss: true`를 보존하고 아래 집계 필드만 갱신하는 Upsert 규칙 적용)
     - `sealed_boss: bool` (기존 봉인 여부 유지, 미봉인 시 `false`)
     - `memorialized_count: int` (현 세대 **정식 추모 `25G`, `state == "MEMORIALIZED"`** 횟수 — 약식 안치 미포함)
     - `pauper_buried_count: int` (현 세대 **약식 안치 `0G`, `state == "PAUPER_BURIED"`** 횟수)
     - `exploited_count: int` (현 세대 `EXPLOITED_SUPPRESS` + `EXPLOITED_BUFF` 횟수)
     - `expired_count: int` (현 세대 `EXPIRED_ON_SUCCESSION` 마감 수)
     - `peak_permanent_stress: int` (현 세대 최고 영구 스트레스)
     - `inherited_curses: Array[String]` (**현 세대가 짊어졌던** `active_curses.duplicate()`)
     - `relic_records: Array[Dictionary]` (현 세대 `soul_relics.duplicate(true)`)
   - `commit_chronicle_generation()`은 커밋 직후 10세대(`max_detailed_generations`) 초과 엔트리의 `relic_records` 압축(`ARCHIVED_COMPACT`)까지 함께 책임진다.

4. **저주 계승 산출 · 저주 세탁 방지(조기 몰락 전량 유지) · 정상 통치 점진 정화:**
   - **사전 정화:** 계산 전 `prev_curses`에서 `CURSE_POOL` 화이트리스트에 속한 비중복 유효 ID만 추출한다.
   - **RNG 주입:** `begin_succession(rng: RandomNumberGenerator = null)` — `rng == null`이면 `GameState._rng` 사용, 외부 `rng` 주입 시 Fisher-Yates 셔플과 무작위 추첨 모두 해당 `rng`만 사용해 결정론적 테스트를 보장한다.
   - **기본 산출 개수:** `base_count = inherited_curse_count(brand_stacks)` (`0` 또는 `1..max_inherited_curses`).
   - **조기 몰락 판정 (`is_early_fall`):**
     - `is_early_fall = (days_survived_at_fall < cleansing_burn_min_days) or (expeditions_cleared_this_gen < cleansing_burn_min_clears)` (기본: `5일 미만` 또는 `원정 클리어 2회 미만`).
   - **분기별 저주 구성 (`kept_curses`와 `newly_drawn_curses` 분리 기록):**
     - **Case A — 조기 몰락 & 기존 저주 보유 (`is_early_fall and not prev_curses.is_empty()`):**
       - **`floor_keep = prev_curses.size()`** (기존 저주 **전량 유지**, 1저주 즉시 세탁 및 연쇄 조기 자살 세탁 원천 차단).
       - `kept_curses = prev_curses.duplicate()`.
       - `target_count = clampi(maxi(base_count, floor_keep), 0, mini(max_inherited_curses, CURSE_POOL.size()))`.
       - `need_new = maxi(0, target_count - kept_curses.size())`.
       - 신규 추첨 풀은 **`CURSE_POOL \ prev_curses`** (`kept_curses == prev_curses`이므로 풀 고갈 없이 항상 신규 저주만 추첨)에서 Fisher-Yates 셔플로 `need_new`개를 뽑아 `newly_drawn_curses`에 기록한다.
     - **Case B — 정상 통치(`not is_early_fall`) & 무착취 몰락(`brand_stacks <= 0`) & 기존 저주 보유:**
       - **세대당 최대 1개 점진 정화:** `floor_keep = maxi(0, prev_curses.size() - 1)`.
       - `prev_curses`를 Fisher-Yates 셔플해 `floor_keep`개를 `kept_curses`로 유지하고 `newly_drawn_curses = []`. *(예: 저주 3개 → 2개, 1개 → 0개. 5일 방치 1회로 3저주 일괄 삭제 불가.)*
     - **Case C — 그 외 정상 통치(`brand_stacks >= 1` 또는 `prev_curses.is_empty()`):**
       - `kept_curses = []`, `CURSE_POOL` 전체에서 `base_count`개를 중복 없이 Fisher-Yates 셔플로 추첨해 `newly_drawn_curses`에 기록한다.
   - 최종 차기 세대 저주: `next_curses = kept_curses + newly_drawn_curses`.

5. **완전 초기화 (강화·자원·엔드리스 사이클 유실, `_suppress_signals = true` 일괄 리셋):**
   - **`_suppress_signals` 가드 계약:** `GameState`의 인라인 프로퍼티 세터 4종(`action_points`, `morale`, `dungeon_activity`, `monster_tier`), `add_*` 메서드 4종, `_check_game_over()` 모두 `if not _suppress_signals:` 가드를 적용한다.
   - **초기화 대상:** `day = 1`, `gold = 300`, `manastone = 2`, `iron_ore = 45`, `max_action_points = 3`, `action_points = max_action_points`, `morale = 50`, `dungeon_activity = 40`, `monster_tier = 0`, `stress_resolvable = 0`, `stress_permanent = 0`, `brand_stacks = 0`, `relic_seq = 0`, `expeditions_cleared_this_gen = 0`, `active_exploit_buff = _default_exploit_buff()`, `buildings = BuildingDb.default_levels()`, `roster`(신규 일반 용병 3명 지급), `party.clear()`, `death_log.clear()`, `soul_relics.clear()`, `last_result = {}`, **`endless_cycle = 0`** *(고사이클 Day 1 소프트락 방지 — 최고 기록은 아래 `max_endless_cycle`로 영구 보존)*.
   - **차기 세대 저주 적용:** `active_curses = next_curses`. `active_curses.has("curse_heavy_crown")`이면 `stress_permanent = 10` 적용 후 **`peak_permanent_stress = stress_permanent`**(왕관 저주 시 `10`, 미보유 시 `0`)로 초기화한다.
   - **보존 대상:** `generation_number` (`+1`), `difficulty_level`, `chronicle_entries`, 누적 엔딩 성향 카운터(`total_exploited_count`, `total_memorialized_count`, `total_pauper_buried_count`), `boss_sealed_count`, **`max_endless_cycle`** (`maxi(max_endless_cycle, prev_endless_cycle)`).
   - **결산 요약 구성 (`pending_succession_summary` 확정 스키마 — 비직렬화 transient):**
     ```gdscript
     {
       "fallen_generation": int,
       "next_generation": int,
       "days_survived": int,
       "fall_cause": String,              # "EXPLOIT" | "EXPEDITION_RETURN" | "REST_SETTLEMENT" | "ESTATE_COMMAND" | "OTHER"
       "memorialized_count": int,
       "pauper_buried_count": int,
       "exploited_count": int,
       "expired_count": int,
       "peak_permanent_stress": int,
       "brand_stacks": int,
       "is_early_fall": bool,
       "kept_curses": Array[String],      # 전대 잔존 저주 ID
       "newly_drawn_curses": Array[String], # 신규 추첨 저주 ID
       "max_building_level": int,         # 유실 요약용 전대 최고 건물 레벨
       "total_fallen_mercs": int          # 전대 사망 용병 수 (death_log.size())
     }
     ```
   - `_suppress_signals = false` 복원 후 `resources_changed`, `stress_changed`, `relics_changed`, `roster_changed`, `party_changed`를 **정확히 1회씩** 발행한다. *(차기 세대 초기 총 스트레스는 최대 `10 < 100`이므로 `_check_game_over()`는 호출하지 않는다.)*

6. **원정 출진 단일 진입점 (`start_expedition()`) · `new_game()` · `SaveManager` 직렬화:**
   - **`GameState.start_expedition() -> bool` 단일화:** 기존 `expedition_prep.gd:183-186`와 `dungeon_popup.gd:52-55`의 이원화된 던전 진입을 `GameState.start_expedition()`으로 통합한다. `party.is_empty()`이면 `false` 반환, 유효 시 파티원 상태를 `ON_EXPEDITION`으로 전환하고 `true`를 반환한다. 원정 승리 시 `expeditions_cleared_this_gen += 1`을 누적한다.
   - **`GameState.new_game()` 완전 초기화:** `iron_ore = 45` 포함 모든 런 필드와 영속 필드를 깨끗이 초기화한다: `generation_number = 1`, `active_curses.clear()`, `expeditions_cleared_this_gen = 0`, `pending_succession_summary = {}`, `unseen_succession_notice = false`, `chronicle_entries.clear()`, `boss_sealed_count = 0`, `endless_cycle = 0`, `max_endless_cycle = 0`, `_in_succession = false`.
   - **`GameState.to_dict()` / `from_dict()` 직렬화:**
     - `generation_number` (부재 또는 `<= 0` 시 `1`): `maxi(1, int(data.get("generation_number", 1)))` (`JSON.parse_string()` `float` → `int` 캐스팅).
     - `active_curses` (부재 시 `[]`): `CURSE_POOL` 화이트리스트 필터링 + **중복 ID 제거(dedup)** + **`max_inherited_curses` 상한 절단** 후 `Array[String]` 복원.
     - `expeditions_cleared_this_gen`: `maxi(0, int(data.get("expeditions_cleared_this_gen", 0)))`.
     - `max_endless_cycle`: `maxi(0, int(data.get("max_endless_cycle", 0)))`.
     - `unseen_succession_notice`: `bool(data.get("unseen_succession_notice", false))`.
     - **`pending_succession_summary = {}`** 및 `_in_succession = false`를 `from_dict()` 진입 시 반드시 초기화한다(타 슬롯 로드 시 이전 메모리 요약 오염 방지).
   - **`SaveManager` 슬롯 메타데이터 확장:** `save_payload`와 `get_slot_meta()`에 `generation_number` (기본 `1`)를 포함해 로드 팝업에서 `제 N대 · D일차`를 구분할 수 있게 한다.
   - *(참고: `difficulty_level`은 `soul-exploitation` 디버프 배율에만 집중 적용하며, 계승 저주 개수/수치에는 의도적으로 별도 배율을 곱하지 않는다.)*

### Inherited Curse Pool (`CURSE_POOL`) — 적용 시점 및 수식 계약

| 저주 ID | 이름 | 적용 시점 | 정확한 수식 / 경계 규칙 |
|---|---|---|---|
| `curse_hollow_coffers` | 빈 금고의 망령 | `return_to_estate()` 1단계 전리품 정산 시 *(일일 기본 수입 `50G` 및 `rest_estate_day()` 비상 구제 `50G`는 면제)* | 원정 전리품 골드 `-15%`: `effective_gold_gain = maxi(0, int(round(float(r.gold_gain) * 0.85)))` |
| `curse_ashen_blood` | 잿빛 혈흔 | `GameState.recruit()` 신규 모집 시 `guild_recruit_hp_bonus()` **합산 후** 적용 *(세대 시작 3명 · 훈련장/대장간 증가 제외)* | `m.max_hp = maxi(1, int(round(float(m.max_hp) * 0.9)))`, `m.hp = m.max_hp` |
| `curse_whispering_rift` | 속삭이는 균열 | `finalize_expedition()` 원정 **클리어** 시 균열 억제량 산출 시 | 클리어 시 균열 활성도 감소량 축소: `-30 → -20` (`activity_delta = -20`, 역저주 골드 버프 차단) |
| `curse_heavy_crown` | 무거운 왕관 | 세대 교체 5단계 초기화 직후 | `stress_permanent = 10`, `peak_permanent_stress = 10` *(스트레스 바 `0..10` 붉은 왕관 잠금 시각화)* |
| `curse_faded_oath` | 바랜 맹세 | `GameState.heal_success_rate()` 조회 시 | `maxi(10, base - brand_heal_penalty_pp - 8)` (최종 하한 `10%`) |

### States and Transitions

| 상태 (State) | 설명 | 허용 전이 |
|---|---|---|
| `ACTIVE_GENERATION` | 정상 통치 중 (`pending_succession_summary.is_empty()`) | → `SUCCESSION_SUMMARY` (`total_stress() >= 100` → `begin_succession()` + `save_game()` 완료 후 `SCENE_GAMEOVER` 진입) |
| `SUCCESSION_SUMMARY` | 몰락 결산 및 계승 저주 공개 (`game_over.tscn`) | → `ACTIVE_GENERATION` (`[제 N+1대 영지 시작]` 클릭 시 요약 소비·저장 후 `SCENE_ESTATE` 복귀) |

## Formulas

### 1. 계승 저주 개수 (`inherited_curse_count`)

The `inherited_curse_count` formula is defined as:

`inherited_curse_count = 0 if brand_stacks <= 0 else clampi(1 + int(floor(float(brand_stacks - 1) / float(maxi(1, stacks_per_curse)))), 1, mini(max_inherited_curses, CURSE_POOL.size()))`

**조기 몰락 / 정상 통치 결합 규칙:**
- `is_early_fall = (days_survived_at_fall < cleansing_burn_min_days) or (expeditions_cleared_this_gen < cleansing_burn_min_clears)`
- `is_early_fall and prev_curses.size() > 0` → `floor_keep = prev_curses.size()`, `target_count = clampi(maxi(inherited_curse_count, floor_keep), 0, mini(max_inherited_curses, CURSE_POOL.size()))` (신규 추첨 풀: `CURSE_POOL \ prev_curses`)
- `not is_early_fall and brand_stacks <= 0 and prev_curses.size() > 0` → `floor_keep = maxi(0, prev_curses.size() - 1)`, `target_count = floor_keep` (세대당 최대 1개 점진 정화)
- 그 외 → `target_count = inherited_curse_count` (신규 추첨 풀: `CURSE_POOL`)

**Variables:**
| Variable | Type | Range | Source | Description |
|---|---|---|---|---|
| `brand_stacks` | int | 0–15 | `soul-exploitation` | 직전 세대 누적 착취 낙인 스택 |
| `stacks_per_curse` | int | 2–4 (기본 3) | data file | 추가 저주 1개당 필요한 착취 스택 구간 |
| `max_inherited_curses` | int | 3 (상수, 탐색 범위 2–4) | constant / data file | 단일 세대에 동시 계승되는 최대 저주 수 (`CURSE_POOL.size()` 이하 클램프) |
| `cleansing_burn_min_days` | int | 3–7 (기본 5) | data file | 조기 몰락 세탁 방지가 해제되는 최소 통치 일수 |
| `cleansing_burn_min_clears` | int | 1–3 (기본 2) | data file | 조기 몰락 세탁 방지가 해제되는 최소 원정 클리어 횟수 |
| `prev_curses` | Array[String] | size 0–3 | calculated | 직전 세대가 보유했던 유효 `active_curses` |

**Output Range:** `0` to `3` (`brand_stacks <= 0` → `0`, `1~3` → `1`, `4~6` → `2`, `7+` → `3`).
**Example:**
- 정상 통치(`day >= 5`, `clears >= 2`) + `prev_curses = []`: 착취 1회(`brand_stacks = 1`) → `1`개, 착취 4회 → `2`개, 착취 7+회 → `3`개.
- 정상 통치 + `prev_curses.size() == 3` + `brand_stacks == 0` → 점진 정화 `2`개 유지 (`1`개 정화).
- 조기 몰락(`day = 3` 또는 `clears = 1`) + `prev_curses.size() == 1` + `brand_stacks == 0` → 기존 `1`개 전량 유지(세탁 불가).
- 조기 몰락 + `prev_curses.size() == 2` + `brand_stacks == 7` → 기존 `2`개 유지 + `CURSE_POOL \ prev_curses`에서 신규 `1`개 추가 = 총 `3`개.

## Tuning Knobs

| 파라미터 | 기본값 | 탐색 범위 | 조정 시 체감 영향 |
|---|---|---|---|
| `stacks_per_curse` | `3` | `2–4` | 착취 몇 회부터 추가 저주가 계승되는지 결정 |
| `max_inherited_curses` | `3` | `2–4` | 차기 세대 초반 난이도 상한선 (`entities.yaml` 상수 `3` 기준) |
| `cleansing_burn_min_days` | `5` | `3–7` | 조기 고의 몰락으로 저주를 정화할 수 없는 최소 통치 일수 |
| `cleansing_burn_min_clears` | `2` | `1–3` | 무행동 방치 세대로 저주를 정화할 수 없는 최소 원정 클리어 수 |

## UI Requirements

- **세대 교체 결산 화면 (`res://scenes/flow/game_over.tscn` 전면 확장):**
  - 기존 영구 패배 문구(`"영지 붕괴"`)를 `"제 N대 영주 몰락 — 에라델의 계승"`으로 교체하고, 라이브 `GameState` 대신 **`pending_succession_summary`**만 읽어 렌더링한다(빈 딕셔너리 진입 시 `SCENE_ESTATE`로 안전 폴백).
  - **전대 통치 요약:** `제 N대 · 통치 D일 · 몰락 원인 · 정식 추모 M회 · 원혼 착취 E회` (+ 0 초과 시 `약식 안치 P회 · 미처리 마감 X건`).
  - **유실 vs 보존 2열 대비 블록:**
    - `유실`: 골드·자원·건물(최고 Lv.K → Lv.1)·용병·장비·현재 엔드리스 사이클 초기화
    - `보존`: 세대 번호(`제 N+1대`), 기념관 연대기, 누적 봉인/최고 엔드리스 기록, 도덕 성향 이력
  - **계승 저주 영역:**
    - `kept_curses` + `newly_drawn_curses`가 모두 비어 있으면 **청정 계승 빈 상태 카드** 표시: *"계승된 저주 없음 — 전대 영주의 통치가 원혼을 더럽히지 않았습니다."*
    - 저주가 1개 이상이면 카드 개별 단위로 `[전대 잔존]` 또는 `[신규 계승 (착취 N스택)]` 배지와 정확한 수치 효과를 표시한다. ("모션/점멸 감소" 설정 시 순차 연출 대신 정적 표시.)
  - **하단 액션 및 입력 가드:**
    - 안내 문구: `"차기 세대 기록이 자동 저장되었습니다."`
    - 주 버튼: **`[제 N+1대 영지 시작]`** (`focus_mode = FOCUS_ALL`, 진입 후 **`0.5s` 입력 잠금**으로 연타 스킵 방지 후 자동 `grab_focus()`).
    - 보조 링크(하단 저강조): `[타이틀로 (저장 완료)]` (기념관 연대기 열람 링크 선택 제공 가능).
    - **ESC 차단:** `game_over.gd`에 `try_handle_cancel() -> bool` 반환 `true`를 구현해 `PauseManager`의 `pause_popup.tscn` 침투를 차단한다.
- **영지 상단 HUD (`soul-exploitation.md` 2행 상태 스트립 연동 & 충돌 해소):**
  - `1280×720` 기준 **2행 슬림 상태 스트립(`y = 48..76`, `28px`)** 좌측에 `[제 N대]` 배지와 최대 3개의 **고정 폭 컴팩트 저주 아이콘 버튼(`24×24px`, `focus_mode = FOCUS_ALL`)**을 배치한다.
  - **물리적 겹침·입력 충돌 해소 계약:** `estate.gd:407` 우측 로스터 덱(`_roster_dock_panel`) 시작 Y를 **`y >= 82px`**로 하향하고, `estate.gd:154` 월드 드래그 판정을 **`event.position.y > 80`**으로 조정한다.
  - **키보드 접근성 팝오버:** Godot 4 기본 `tooltip_text`는 키보드 포커스에서 미표시되므로, 저주 배지의 `mouse_entered` / `focus_entered` 공용 커스텀 팝오버(또는 Enter 토글 카드, `ESC` 닫기)로 저주 이름과 정확한 수치 효과를 표시한다.
- **결산 화면 강제 종료(Alt+F4) 재접속 1회성 배너:**
  - `unseen_succession_notice == true` 상태로 `SCENE_ESTATE`가 로드되면 상단에 1회성 비차단 배너(`"제 N대 시작 · 활성 계승 저주: [목록]"`)를 표시하고 닫기/확인 시 `false`로 갱신 후 저장한다.
- **5종 저주 적용 시점 인라인 귀인 표:**

| 저주 ID | 인라인 귀인 UI 위치 | 표시 계약 |
|---|---|---|
| `curse_hollow_coffers` | `dungeon_result.gd` 전리품 요약 / `preview_return_settlement()` | 전리품 골드 옆 `[빈 금고 -15%]` 병기 |
| `curse_ashen_blood` | `guild_popup.gd` / `guild.gd` 모집 버튼·카드 | 모집 안내에 `[잿빛 혈흔: 신규 최대 HP -10%]` 병기 |
| `curse_whispering_rift` | `dungeon_result.gd` 클리어 요약 / `preview_return_settlement()` | 균열 억제량 `-20% [속삭이는 균열]` 병기 |
| `curse_heavy_crown` | 영지 상단 스트레스 바 | `0..10` 구간 붉은 왕관 잠금 오버레이 + `"영구 잠금 10 (몰락까지 여유 90)"` |
| `curse_faded_oath` | `treatment_popup.gd` / `treatment.gd` | **2줄 구조**(1줄: 최종 성공률, 2줄: `autowrap` 귀인 `[기본 - 낙인 - 바랜 맹세 8%p]`) |

## Edge Cases

- **If `brand_stacks == 0`, `days_survived_at_fall >= 5`, `expeditions_cleared_this_gen >= 2`이고 `prev_curses == []`인 상태로 몰락하면**: `next_curses = []`로 저주 없이 다음 세대를 시작하고 결산 화면에 청정 계승 카드를 표시한다.
- **If 정상 통치(`day >= 5`, `clears >= 2`) 후 `brand_stacks == 0`으로 몰락했으나 `prev_curses.size() == 3`이면**: 일괄 소멸이 아니라 점진 정화로 `2`개가 유지되고 `1`개만 정화된다(`1`개 보유 시 `0`개로 완전 정화).
- **If `day = 3` 또는 `expeditions_cleared_this_gen = 1`인 조기 몰락 상태에서 `prev_curses.size() == 1`, `brand_stacks == 0`이면**: `floor_keep = 1`로 기존 1개가 그대로 유지되어 조기 자살 세탁이 불가능하다.
- **If 조기 몰락(`day = 4, clears = 0`) 상태에서 `prev_curses.size() == 2`, `brand_stacks = 7`이면**: 기존 `2`개(`kept_curses`)를 유지하고 `CURSE_POOL \ prev_curses`(3종)에서 신규 `1`개(`newly_drawn_curses`)를 추첨해 총 `3`개가 된다.
- **If 4일차 원정 귀환 정산(`return_to_estate()`) 중 스트레스 100으로 몰락하면**: 4단계에서 `day`가 `5`로 증가했더라도 `days_survived_at_fall = day - 1 = 4`로 판정해 조기 몰락 규칙을 일관 적용하고, `dungeon_result.gd`는 `not pending_succession_summary.is_empty()`를 감지해 `SCENE_GAMEOVER`로 정상 진입한다.
- **If 동일 세대에서 심층 보스를 봉인(`SEALED_ATONEMENT` / `SEALED_TYRANT`)한 뒤 같은 세대에 스트레스 100으로 몰락하면**: `commit_chronicle_generation()`이 중복 항목을 만들지 않고 기존 세대 엔트리의 `sealed_boss: true`와 봉인 `outcome`을 유지한 채 `days_survived`·유품 집계를 갱신한다.
- **If `endless_cycle == 3`에서 몰락해 세대 교체가 발생하면**: `max_endless_cycle`은 `3`으로 보존되고 차기 세대의 `endless_cycle`은 `0`으로 리셋되어 Day 1 소프트락을 방지한다.
- **If `curse_ashen_blood` 활성 상태에서 모집소 Lv.5(`+20 HP`) 신규 용병을 고용하면**: 보너스 합산 후 `* 0.9` 반올림(`maxi(1, ...)`)이 적용되며, 세대 시작 기본 용병 3명에는 미적용된다.
- **If 세대 교체 결산 화면(`game_over.tscn`)에서 Alt+F4 강제 종료 후 재시작하면**: `begin_succession()`과 `save_game()`이 이미 완료되어 재추첨(세이브 스컴)이 불가능하며, 재접속 시 차기 세대(`N+1`) 영지 1일차에 1회성 계승 저주 알림 배너가 표시된다.
- **If 구버전·오염 세이브(`generation_number <= 0`, 미등록/중복 저주 ID, 4개 이상 저주)를 로드하면**: `from_dict()`가 `generation_number = 1`, 유효·비중복 최대 3개 저주, `pending_succession_summary = {}`로 안전 복원한다.

## Dependencies

| 대상 시스템 | 방향 | 유형 | 데이터 인터페이스 | 상태 |
|---|---|---|---|---|
| `soul-exploitation` | Upstream | Hard | `brand_stacks`, `soul_relics` 마감(`EXPIRED_ON_SUCCESSION`), `total_exploited_count`, `total_memorialized_count`, `total_pauper_buried_count`, `peak_permanent_stress`, `_suppress_signals`, `auto_succession_enabled` | GDD 승인됨 ([soul-exploitation.md](file:///d:/Projects/_Personal/Godot-Projects/design/gdd/soul-exploitation.md)) |
| `GameState` / `SaveManager` / Scenes | Upstream | Hard | `_check_game_over()` → `begin_succession(rng)` → `save_game()`, `start_expedition()`, `dungeon_result.gd`·`estate.gd`·`game_over.gd` 씬 전환 및 HUD 계약, 슬롯 메타 `generation_number` | 기존 코드 구현됨 (확장 필요) |
| `memorial-chronicle` | Downstream | Hard | `commit_chronicle_generation(snapshot)` (동일 세대 Upsert + 10세대 압축, 깊은 복사 스냅샷) | GDD 작성됨 ([memorial-chronicle.md](file:///d:/Projects/_Personal/Godot-Projects/design/gdd/memorial-chronicle.md)) |
| `rift-seal-endless` | Downstream | Soft | 세대 교체 시 `endless_cycle = 0` 리셋 및 `max_endless_cycle`·`boss_sealed_count`·누적 성향 카운터 보존 | GDD 작성됨 ([rift-seal-endless.md](file:///d:/Projects/_Personal/Godot-Projects/design/gdd/rift-seal-endless.md)) |

## Acceptance Criteria

- **AC-1 (자원·강화·엔드리스 사이클 완전 초기화 및 영속 데이터 보존 — Dirty State):**
  - **GIVEN** `generation_number = 1, difficulty_level = 2, day = 12, expeditions_cleared_this_gen = 4, gold = 900, manastone = 25, iron_ore = 10, max_action_points = 5, action_points = 1, morale = 15, dungeon_activity = 95, monster_tier = 3, stress_resolvable = 40, stress_permanent = 60, peak_permanent_stress = 60, brand_stacks = 0, relic_seq = 5, active_curses = [], active_exploit_buff = {"atk": 8, "crit": 12.0}`, 대장간 Lv.4·치료소 Lv.3, 기존 용병 4명(`old_ids`), `party.size() == 2, death_log.size() == 2, last_result = {"victory": true}, total_exploited_count = 3, total_memorialized_count = 2, total_pauper_buried_count = 1, endless_cycle = 2, max_endless_cycle = 1, boss_sealed_count = 2, chronicle_entries.size() == 1`
  - **WHEN** `begin_succession(seeded_rng)` 실행
  - **THEN** 초기화: `generation_number == 2, day == 1, gold == 300, manastone == 2, iron_ore == 45, max_action_points == 3, action_points == 3, morale == 50, dungeon_activity == 40, monster_tier == 0, stress_resolvable == 0, stress_permanent == 0, peak_permanent_stress == 0, brand_stacks == 0, relic_seq == 0, expeditions_cleared_this_gen == 0, endless_cycle == 0, active_exploit_buff == _default_exploit_buff(), buildings == BuildingDb.default_levels(), roster.size() == 3`(전원 `old_ids`와 상이), `party.is_empty(), death_log.is_empty(), soul_relics.is_empty(), last_result.is_empty()`. 보존: `difficulty_level == 2, total_exploited_count == 3, total_memorialized_count == 2, total_pauper_buried_count == 1, max_endless_cycle == 2, boss_sealed_count == 2, chronicle_entries.size() == 2`.

- **AC-2 (착취 낙인 비례 저주 산출 — 구간 경계 & RNG 시드 결정론):**
  - **GIVEN** 정상 통치(`day = 5, expeditions_cleared_this_gen = 2`), `prev_curses = []`, 고정 시드 `rng.seed = 42`
  - **WHEN** `brand_stacks`를 각각 `-1, 0, 1, 3, 4, 6, 7, 15, 20`으로 설정해 `begin_succession(rng)` 실행
  - **THEN** `active_curses.size()`는 각각 `0, 0, 1, 1, 2, 2, 3, 3, 3`이며 중복 ID가 없고, 동일 시드 재실행 시 동일 순열이 재현된다.

- **AC-3 (미처리 유품 선행 마감 · 연대기 스냅샷 전체 필드 · 깊은 복사 격리 · 보스 봉인 Upsert):**
  - **GIVEN** (a) `generation_number = 2, day = 9, peak_permanent_stress = 42, active_curses = ["curse_hollow_coffers"]`, `soul_relics`에 `UNRESOLVED` 2건, `MEMORIALIZED` 1건, `PAUPER_BURIED` 1건, `EXPLOITED_SUPPRESS` 1건, `EXPLOITED_BUFF` 1건 존재
  - **WHEN** `begin_succession(seeded_rng)` 실행
  - **THEN** `chronicle_entries.back()`이 `generation == 2, days_survived == 9, outcome == "FALLEN", sealed_boss == false, memorialized_count == 1, pauper_buried_count == 1, exploited_count == 2, expired_count == 2, peak_permanent_stress == 42, inherited_curses == ["curse_hollow_coffers"]`를 만족하고 미처리 2건은 `EXPIRED_ON_SUCCESSION`(`resolved_day == 9`)로 기록되며, 이후 `active_curses`나 `soul_relics`를 변경해도 스냅샷이 오염되지 않는다.
  - **AND GIVEN** (b) 동일 `generation == 2`에 이미 `outcome == "SEALED_ATONEMENT", sealed_boss == true` 엔트리가 존재할 때 `begin_succession()` 실행 **THEN** `chronicle_entries.size()`는 증가하지 않으며 기존 엔트리의 `sealed_boss == true, outcome == "SEALED_ATONEMENT"`가 유지된 채 `days_survived`와 유품 집계가 갱신된다.

- **AC-4 (저주 세탁 방지 전량 유지 vs 정상 통치 점진 정화 — 정확 경계 검증):**
  - **GIVEN** 고정 시드 `rng.seed = 101`
  - **WHEN / THEN**
    - (i) 조기 몰락(일수 미달): `day = 4, clears = 2, prev_curses = ["curse_hollow_coffers"], brand_stacks = 0` → `active_curses == ["curse_hollow_coffers"]` (1저주 세탁 차단, `kept_curses.size() == 1, newly_drawn_curses.is_empty()`).
    - (ii) 조기 몰락(클리어 미달): `day = 6, clears = 1, prev_curses = ["curse_hollow_coffers", "curse_ashen_blood"], brand_stacks = 0` → `active_curses.size() == 2`, `active_curses == prev_curses` (방치 세대 세탁 차단).
    - (iii) 조기 몰락 + 고착취: `day = 4, clears = 0, prev_curses = ["curse_hollow_coffers", "curse_ashen_blood"], brand_stacks = 7` → `active_curses.size() == 3`, `kept_curses.size() == 2`(기존 2개 유지), `newly_drawn_curses.size() == 1`(`CURSE_POOL \ prev_curses` 소속).
    - (iv) 정상 통치 무착취 점진 정화: `day = 5, clears = 2, prev_curses = ["curse_hollow_coffers", "curse_ashen_blood", "curse_faded_oath"], brand_stacks = 0` → `active_curses.size() == 2`, `active_curses ⊂ prev_curses` (세대당 최대 1개 정화). `prev_curses.size() == 1`이면 `active_curses.is_empty()`.

- **AC-5 (5종 계승 저주 개별 효과 및 경계값):**
  - **AC-5a (`curse_hollow_coffers`):** **GIVEN** `active_curses = ["curse_hollow_coffers"]`, **WHEN** `r.gold_gain = 200` 원정 귀환 시 전리품 골드 `+170G`(`-15%`) + 기본 수입 `+50G` = `+220G`; **AND** `rest_estate_day()` 비상 구제 시 기본 수입은 면제되어 `+50G` 정상 지급.
  - **AC-5b (`curse_ashen_blood`):** **GIVEN** `active_curses = ["curse_ashen_blood"]`, **WHEN** (i) 세대 시작 초기 용병 3명은 100% 정상 HP; (ii) `recruit()`에서 기본 `max_hp = 80` + 모집소 보너스 `+20`(= `100`)이면 최종 `max_hp == 90, hp == 90`; (iii) 합산 `max_hp == 1`이면 하한 클램프로 `max_hp == 1, hp == 1`.
  - **AC-5c (`curse_whispering_rift`):** **GIVEN** `active_curses = ["curse_whispering_rift"]`, `dungeon_activity = 40`, **WHEN** 원정 클리어 후 `finalize_expedition()`/`return_to_estate()` 실행, **THEN** 균열 활성도 감소량이 `-30`이 아닌 `-20`으로 적용되어 `dungeon_activity == 20`(대조군: 저주 미보유 시 `10`)이며 `_base_gold`는 증가하지 않는다.
  - **AC-5d (`curse_heavy_crown`):** **GIVEN** 시드 고정 `begin_succession(rng)` 결과 `active_curses.has("curse_heavy_crown") == true`, **THEN** `stress_permanent == 10, peak_permanent_stress == 10, total_stress() == 10`이며 `game_over` 미발행(대조군: 미포함 시 `0, 0`).
  - **AC-5e (`curse_faded_oath`):** **GIVEN** `active_curses = ["curse_faded_oath"]`, **WHEN** (i) `base = 80, brand_stacks = 0` → `heal_success_rate() == 72`; (ii) `base = 50, brand_heal_penalty_pp = 45` → `heal_success_rate() == 10`(최종 하한 `10%`).

- **AC-6 (JSON 라운드트립 · 오염 정화 · 경계 폴백 · `new_game()` 완전 초기화):**
  - **GIVEN** `generation_number = 3, active_curses = ["curse_hollow_coffers", "curse_heavy_crown"], expeditions_cleared_this_gen = 2, max_endless_cycle = 4`
  - **WHEN** `JSON.parse_string(JSON.stringify(GameState.to_dict()))`를 `from_dict()`로 로드
  - **THEN** `typeof(generation_number) == TYPE_INT`, `generation_number == 3`, 동일 `active_curses`, `expeditions_cleared_this_gen == 2`, `max_endless_cycle == 4`, `pending_succession_summary.is_empty()`.
  - **AND WHEN** 오염 딕셔너리 `{"generation_number": 0, "active_curses": ["curse_hollow_coffers", "curse_invalid", "curse_hollow_coffers", "curse_ashen_blood", "curse_heavy_crown", "curse_faded_oath"]}` 또는 빈 `{}` 로드 **THEN** `generation_number == 1`, `active_curses`는 유효·비중복 최대 3개(빈 딕셔너리는 `[]`).
  - **AND WHEN** `new_game()` 호출 **THEN** `generation_number == 1, iron_ore == 45, active_curses.is_empty(), expeditions_cleared_this_gen == 0, pending_succession_summary.is_empty(), unseen_succession_notice == false, chronicle_entries.is_empty(), boss_sealed_count == 0, endless_cycle == 0, max_endless_cycle == 0`.

- **AC-7 (세이브 스컴 방지 — 원자적 저장 및 강제 종료 복원):**
  - **GIVEN** `generation_number = 1, day = 8, expeditions_cleared_this_gen = 2, brand_stacks = 4, stress_resolvable = 95, auto_succession_enabled = true`
  - **WHEN** 스트레스 `+10`으로 `total_stress() >= 100` 도달
  - **THEN** `SCENE_GAMEOVER` 진입 이전에 `begin_succession()`과 `GameState.save_game()`이 완료되어 디스크 세이브에 `generation_number == 2, day == 1, unseen_succession_notice == true`와 확정 `active_curses`가 기록되며, `[제 2대 영지 시작]`을 누르지 않고 세이브를 즉시 재로드해도 동일한 `generation_number == 2` 및 동일 `active_curses`로 복원된다.

- **AC-8 (재진입 가드 · `_suppress_signals` 단일 발행 · 테스트 격리 `auto_succession_enabled`):**
  - **GIVEN** `generation_number = 1`, 5개 상태 시그널(`resources_changed`, `stress_changed`, `relics_changed`, `roster_changed`, `party_changed`) 및 `game_over` 카운터 연결
  - **WHEN** (a) `begin_succession()` 실행 후 `pending_succession_summary`가 채워진 상태에서 중복 호출 시도 **THEN** `generation_number == 2`(이중 증가 없음), `chronicle_entries` 1건만 추가, 5개 시그널 각 정확히 `1`회 발행, `game_over` 추가 발행 `0`회, `_suppress_signals == false` 복원.
  - **AND WHEN** (b) `auto_succession_enabled = false`에서 `stress_resolvable = 100` 도달 **THEN** `game_over` 1회 발행되나 `begin_succession()` 미실행(초기화 전 상태 유지 — `soul-exploitation.md` AC-7 호환).

- **AC-9 (원정 귀환 몰락 전환 · 결산 화면 바인딩 · ESC 차단):**
  - **GIVEN** 원정 귀환 정산 중 총 스트레스 `>= 100` 도달(`day = 4` → 4단계 `day = 5` → 6단계 `begin_succession()` 완료)
  - **WHEN** `dungeon_result.gd:_on_return()` 실행 후 `game_over.tscn` 로드
  - **THEN** `not pending_succession_summary.is_empty()` 조건으로 `SCENE_GAMEOVER`로 전환되며, `days_survived == 4`(조기 몰락 판정 일치) 및 `kept_curses`/`newly_drawn_curses`가 표시되고, `try_handle_cancel()`이 `true`를 반환해 `ESC` 일시정지 팝업이 열리지 않으며, `[제 N+1대 영지 시작]` 클릭 시 `pending_succession_summary.is_empty() == true`, `unseen_succession_notice == false`로 갱신 후 `SCENE_ESTATE`로 복귀한다.
