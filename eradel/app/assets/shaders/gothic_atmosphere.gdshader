shader_type canvas_item;

// 다키스트 던전 풍 고딕 비네팅 · 횃불 온기 파동 · 위기 맥동 오버레이 셰이더.
// 도트 아트 선명도를 유지하기 위해 화면 중앙부는 투명하게 두고 가장자리 중심으로 분위기와 조명을 합성한다.

uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.42;
uniform float vignette_softness : hint_range(0.1, 1.0) = 0.48;
uniform vec4 vignette_color : source_color = vec4(0.03, 0.02, 0.04, 1.0);
uniform vec4 torch_tint : source_color = vec4(1.0, 0.62, 0.22, 1.0);
uniform float torch_warmth : hint_range(0.0, 0.5) = 0.14;
uniform float danger_pulse : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered * vec2(1.15, 0.95));

	// 화면 가장자리 비네팅 마스크
	float edge = smoothstep(0.32, 0.32 + vignette_softness, dist);
	float vig_alpha = clamp(edge * vignette_intensity, 0.0, 0.85);

	// 횃불 온기 파동 (중앙~중간 가장자리에 은은한 호박빛 호흡)
	float flicker = 0.85 + 0.15 * sin(TIME * 3.2) * cos(TIME * 1.9);
	float warm_ring = smoothstep(0.75, 0.18, dist) * torch_warmth * flicker;

	// 위기(스트레스 임계/저광원/전멸) 시 가장자리 핏빛 맥동
	float heartbeat = 0.55 + 0.45 * sin(TIME * 4.8);
	float danger_edge = smoothstep(0.28, 0.78, dist) * danger_pulse * heartbeat * 0.48;

	vec3 col = vignette_color.rgb * vig_alpha;
	col += torch_tint.rgb * warm_ring;
	col += vec3(0.78, 0.08, 0.12) * danger_edge;

	float final_alpha = clamp(vig_alpha + warm_ring * 0.35 + danger_edge, 0.0, 0.88);
	COLOR = vec4(col, final_alpha);
}
