# Backlog

- [2026-07-19] skill listing:上游 `listing.rs` 若干格式断言测试(`single_skill_within_budget`、`format_renders_use_when_line_with_explicit_when_to_use`、`format_no_use_when_line_without_when_to_use`、`tier3_no_overflow_indicator_when_all_names_fit` 等)在 patched tree 下 run 会红。现行契约是「全 lib 可编译 + build.sh 点名测试绿」,它们不在点名列表因此不阻塞;若将来扩大跑测范围,需补 remove/rewrite 规则。(`two_hundred_skills_fit_within_default_budget` 经推演在 pristine upstream 下疑似本来就红。)
- [2026-07-20] otty-kkp:`supports_focus_tracking_known_terminals`(`xai-grok-pager`)未进 build.sh 点名测试列表 —— 该 crate 编译 test harness 太贵(本地 debug 4m46s),而 release 构建不编译 `cfg(test)` 代码,所以这条断言在 CI 完全不被验证,只有 seam 规则保证那一行被改写。本地已实跑通过(108 passed)。若将来该 crate 已因别的原因进了跑测范围,顺手补上。
- [2026-07-20] CI 提速留下的尾巴(三条,都是故意不做):
  1. `cargo test <filter>` 匹配到 0 个测试仍然 exit 0。点名测试从 11 条 invocation 合并成 4 条之后,某条上游被删的测试更难从日志肉眼发现(以前一条一行,现在只看到汇总的 "N passed")。真正的修法是断言实际跑过的测试数等于点名数,暂未做。
  2. `brew install ast-grep dotslash` 仍走 Homebrew(已关 auto-update/cleanup)。改成直接下 GitHub release 二进制还能再省几分钟,代价是自己维护 URL + checksum + 升级。
  3. 二进制 149 MB(`__text` 92M / `__const` 19M / `__LINKEDIT` 27.9M / `__eh_frame` 9.1M)。`strip -x` 能到 129 MB,但会去掉 local symbol、劣化 Rust backtrace 符号化,而上游在 `.cargo/config.toml` 特意开 `force-unwind-tables=yes` 就是为了 backtrace(backtrace-rs#397),故意不做。`release-dist`(thin LTO + codegen-units=1)能真正砍 `__text`,但上游注明约 2.2x 构建时间,与本次目标直接冲突,同样不做。
- [2026-07-19] skill listing tier-3 overflow:names-only 预算裁掉的 skill 只剩 "... and N more skills in {dir}" 一行,既暴露目录(与 never-read_file 指令矛盾)又不含 id,被裁掉的 skill 在 id-only 协议下不可加载。触发条件极端(预算压到 names-only 仍放不下),暂未patch。
