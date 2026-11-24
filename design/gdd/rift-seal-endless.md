# Rift Seal & Endless Chronicle (심층 보스 봉인 & 속죄/폭군 엔딩 → 엔드리스)

> **Status**: Draft Complete
> **Author**: User + Antigravity
> **Last Updated**: 2026-11-24
> **Last Verified**: 2026-11-24
> **Implements Pillar**: 봉인 이후의 끝없는 연대기 (완결성과 무한 생존 순환)

## Summary

어둠의 균열 심층 보스를 격파해 1차 승리 목표(균열 봉인)를 달성하면 누적 착취/추모 비율과 영구 스트레스 이력에 따라 **속죄(Atonement)** 또는 **폭군(Tyrant)** 엔딩을 분기 연출하고, 엔딩 후에도 런을 닫지 않고 강화된 심연 단계(`endless_cycle + 1`)의 무한 세대 생존으로 이어지는 엔드게임 시스템이다.

> **Quick reference** — Category: `Progression / Endgame` · Layer: `Feature` · Priority: `MVP` · Key deps: `GameState`, `soul-exploitation`, `generation-succession`, `memorial-chronicle`

## Overview

**심층 보스 봉인 & 엔드리스 시스템(Rift Seal & Endless)**은 에라델의 명확한 1차 완결 지점과 장기 반복 플레이를 동시에 제공한다. 플레이어가 어둠의 균열 최종 회랑의 심층 보스를 격파하면, 지금까지의 원혼 착취·추모 이력을 바탕으로 **속죄 엔딩** 또는 **폭군 엔딩**이 판정되어 짧은 연대기 텍스트 연출이 재생된다. 이후 "연대기 계속하기"를 선택하면 게임이 종료되지 않고 `endless_cycle`이 `+1` 증가해 더 거센 균열 압박 속에서 기록 갱신과 세대 계승을 이어간다.

## Player Fantasy

플레이어는 수많은 희생 끝에 마침내 어둠의 균열을 봉인하는 성취감을 맛보되, 자신이 선택한 방식(추모로 버틴 속죄의 영주 vs 원혼을 태워 승리한 폭군)에 대한 냉정한 평가를 받는다. 그리고 봉인 이후에도 끝나지 않는 어둠 속에서 자신의 영지 역사를 어디까지 이어갈 수 있는지 시험한다.

## Detailed Design

### Core Rules

1. **심층 보스 해금 조건:** `dungeon_activity <= 30` 이거나 영지 통치 `day >= 10` 도달 시 최종 회랑(심층 보스 원정)에 출진할 수 있다.
2. **엔딩 분기 판정 (심층 보스 격파 시):**
   - `soul-exploitation`의 누적 데이터(`total_exploited_count`, `total_memorialized_count`, `total_pauper_buried_count`, 현 세대 `brand_stacks`)를 사용해 `tyranny_ratio`를 산출한다.
   - **속죄 엔딩 (`ATONEMENT`):** `(total_exploited_count == 0 and (total_pauper_buried_count == 0 or total_memorialized_count >= 1))` 이거나 `tyranny_ratio < tyranny_threshold` (기본 `0.40`)이고 현 세대 `brand_stacks <= 3`이며 `(total_pauper_buried_count == 0 or total_memorialized_count >= 1)`. *(전사자가 발생했음에도 정식 추모 `0`회로 약식 안치만 반복한 무예우 런은 속죄 무임승차를 차단한다.)*
   - **폭군 엔딩 (`TYRANT`):** `tyranny_ratio >= tyranny_threshold` (기본 `0.40`), 또는 현 세대 `brand_stacks >= 4`, 또는 `(total_pauper_buried_count > 0 and total_memorialized_count == 0)`.
3. **엔드리스 전환 (런 유지):**
   - 엔딩 연출 팝업에서 `[연대기 계속하기]` 선택 시 `boss_sealed_count += 1`, `endless_cycle += 1`, `max_endless_cycle = maxi(max_endless_cycle, endless_cycle)`을 기록하고 영지로 복귀한다.
   - `endless_cycle`이 1 오를 때마다 몬스터 기본 스탯 배율(`endless_monster_mult`)이 상승해 무한 스펙 인플레 없이 긴장감을 유지한다.
   - 엔딩 이후 스트레스 100 도달로 `generation-succession`이 발동하면 고사이클 Day 1 소프트락 방지를 위해 현재 `endless_cycle`은 `0`으로 리셋되고, 최고 도달 기록(`max_endless_cycle`)과 누적 `boss_sealed_count`는 영구 보존된다.

### States and Transitions

| 상태 | 설명 | 허용 전이 |
|---|---|---|
| `PRE_SEAL` | 1차 심층 보스 미격파 | → `ENDING_VIEW` (심층 보스 격파) |
| `ENDING_VIEW` | 속죄/폭군 엔딩 연출 및 연대기 기록 | → `ENDLESS_ACTIVE` (`연대기 계속하기` 선택) |
| `ENDLESS_ACTIVE` | 무한 세대 생존 모드 (`endless_cycle >= 1`) | → `ENDING_VIEW` (다음 사이클 심층 보스 재격파 시) |

## Formulas

### 1. 폭군 성향 비율 (`tyranny_ratio`)

The `tyranny_ratio` formula is defined as:

`tyranny_ratio = total_exploited_count / max(1, total_exploited_count + total_memorialized_count)`

**Variables:**
| Variable | Type | Range | Source | Description |
|---|---|---|---|---|
| `total_exploited_count` | int | 0–999 | `soul-exploitation` | 전 세대 누적 원혼 착취 횟수 |
| `total_memorialized_count` | int | 0–999 | `soul-exploitation` | 전 세대 누적 원혼 추모 횟수 |
| `tyranny_threshold` | float | 0.30–0.60 (기본 `0.40`) | data file | 폭군 엔딩 분기 임계 비율 |

**Output Range:** `0.0` to `1.0` (`0/0`일 때 분모 `max(1, 0) = 1`로 0 나눗셈 방지 → `0.0`, 속죄 엔딩).

### 2. 엔드리스 몬스터 스케일링 (`endless_monster_mult`)

The `endless_monster_mult` formula is defined as:

`endless_monster_mult = 1.0 + endless_cycle * endless_scale_per_cycle`

**Variables:**
| Variable | Type | Range | Source | Description |
|---|---|---|---|---|
| `endless_cycle` | int | 0–99 | calculated | 심층 보스 봉인 누적 횟수 |
| `endless_scale_per_cycle` | float | 0.15–0.30 (기본 `0.20`) | data file | 사이클당 몬스터 HP/ATK 추가 배율 |

**Output Range:** `1.0` (1차 봉인 전) → `1.2` (1사이클) → `1.4` (2사이클) ...

## Tuning Knobs

| 파라미터 | 기본값 | 탐색 범위 | 조정 시 체감 영향 |
|---|---|---|---|
| `tyranny_threshold` | `0.40` | `0.30–0.60` | 폭군 엔딩으로 판정되는 착취 비중 엄격도 |
| `endless_scale_per_cycle` | `0.20` | `0.15–0.30` | 엔드리스 사이클별 난이도 상승 곡선 |

## Edge Cases

- **If 단 한 명의 용병도 사망하지 않아 `total_exploited_count == 0 && total_memorialized_count == 0`인 상태로 보스를 격파하면**: `tyranny_ratio = 0.0`으로 0 나눗셈 없이 **속죄 엔딩(`ATONEMENT`)**으로 판정한다.
- **If `tyranny_ratio < 0.40`이지만 현 세대 `brand_stacks >= 4`인 경우**: 직전 세대의 집중 착취를 반영해 **폭군 엔딩(`TYRANT`)**으로 판정한다.
- **If 엔드리스 모드에서 영주가 몰락해 세대 교체가 발생하면**: 고사이클 Day 1 소프트락 방지를 위해 현재 `endless_cycle`은 `0`으로 리셋되며, `max_endless_cycle`과 `boss_sealed_count`는 영구 보존된다.

## Dependencies

| 대상 시스템 | 방향 | 유형 | 데이터 인터페이스 | 상태 |
|---|---|---|---|---|
| `soul-exploitation` | Upstream | Soft | `total_exploited_count`, `total_memorialized_count`, `total_pauper_buried_count`, `brand_stacks` | GDD 승인됨 ([soul-exploitation.md](file:///d:/Projects/_Personal/Godot-Projects/design/gdd/soul-exploitation.md)) |
| `generation-succession` | Upstream | Soft | 엔드리스 중 세대 교체 시 `endless_cycle = 0` 리셋, `max_endless_cycle`·`boss_sealed_count` 보존 | GDD 리뷰 중 ([generation-succession.md](file:///d:/Projects/_Personal/Godot-Projects/design/gdd/generation-succession.md)) |
| `memorial-chronicle` | Downstream | Soft | 엔딩 유형(`SEALED_ATONEMENT`/`SEALED_TYRANT`) 및 봉인 횟수 기록 | GDD 작성됨 ([memorial-chronicle.md](file:///d:/Projects/_Personal/Godot-Projects/design/gdd/memorial-chronicle.md)) |

## Acceptance Criteria

- **AC-1 (속죄 vs 폭군 분기 · 0 나눗셈 방어 · 약식 안치 무임승차 차단):** **GIVEN** `(exploited=0, memorialized=0, pauper_buried=0, brand=0)`, `(exploited=4, memorialized=6, pauper_buried=0, brand=2)`, `(exploited=0, memorialized=0, pauper_buried=2, brand=0)` 조건에서 심층 보스를 격파할 때, **WHEN** 엔딩 판정이 실행되면, **THEN** 첫 번째는 `ATONEMENT`(`tyranny_ratio=0.0`), 두 번째는 `TYRANT`(`tyranny_ratio=0.40 >= 0.40`), 세 번째는 `TYRANT`(전사자 발생 후 정식 추모 `0`회 약식 안치 무임승차 차단)로 판정된다.
- **AC-2 (엔드리스 전환 및 배율 증가):** **GIVEN** `endless_cycle == 0`에서 심층 보스를 격파하고 `[연대기 계속하기]`를 선택할 때, **WHEN** 영지로 복귀하면, **THEN** `endless_cycle == 1`, `boss_sealed_count == 1`, `endless_monster_mult == 1.2`가 적용되며 런이 종료되지 않는다.
