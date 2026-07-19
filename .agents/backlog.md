# Backlog

- [2026-07-19] skill listing:上游 `listing.rs` 若干格式断言测试(`single_skill_within_budget`、`format_renders_use_when_line_with_explicit_when_to_use`、`format_no_use_when_line_without_when_to_use`、`tier3_no_overflow_indicator_when_all_names_fit` 等)在 patched tree 下 run 会红。现行契约是「全 lib 可编译 + build.sh 点名测试绿」,它们不在点名列表因此不阻塞;若将来扩大跑测范围,需补 remove/rewrite 规则。(`two_hundred_skills_fit_within_default_budget` 经推演在 pristine upstream 下疑似本来就红。)
- [2026-07-19] skill listing tier-3 overflow:names-only 预算裁掉的 skill 只剩 "... and N more skills in {dir}" 一行,既暴露目录(与 never-read_file 指令矛盾)又不含 id,被裁掉的 skill 在 id-only 协议下不可加载。触发条件极端(预算压到 names-only 仍放不下),暂未patch。
