# Consistency Failure Log

<!-- Auto-maintained by /consistency-check. Do not edit manually. -->
<!-- One entry per detected conflict, in chronological order. -->

| Date | GDD A | GDD B | Conflict Type | Status |
|------|-------|-------|---------------|--------|
| 2026-11-24 | `design/gdd/soul-exploitation.md` | `design/gdd/generation-succession.md`, `design/gdd/rift-seal-endless.md` | 🔴 CONFLICT (`total_pauper_buried_count` 보존·의존성 누락) | Resolved |

### 2026-11-24 — /consistency-check — 🔴 CONFLICT
**Domain**: Gameplay / Progression / Endgame (`soul-exploitation`, `generation-succession`, `rift-seal-endless`)
**Documents involved**: `design/gdd/soul-exploitation.md` vs `design/gdd/generation-succession.md`, `design/gdd/rift-seal-endless.md`
**What happened**: `soul-exploitation.md`와 `rift-seal-endless.md`에 전 세대 누적 영속 카운터 `total_pauper_buried_count`를 도입했으나, `generation-succession.md`의 보존 대상·의존성·AC-1과 `rift-seal-endless.md`의 의존성·AC-1에 누락됨.
**Resolution**: `generation-succession.md`(L55, L133, AC-1)와 `rift-seal-endless.md`(L93, AC-1)에 `total_pauper_buried_count`를 추가 동기화하고 `entities.yaml`의 `memorial_restore`·`tyranny_ratio`도 최신화함.
**Pattern**: 상위 GDD 개정 시 신규 영속 카운터를 추가하면 반드시 `generation-succession` 보존 목록과 `entities.yaml`을 함께 점검해야 한다.
