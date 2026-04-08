# Recovery: Fix Failing Tests on Main Branch

**Area:** recovery

The main branch tests are failing at commit d1ca356. Diagnose the failure from the test output below and fix the root cause. Keep the fix minimal and targeted.

## Test Failure Output

```
--- tests/test_cli_args.nim ---
Hint: used config file '/usr/lib/nim/config/nim.cfg' [Conf]
Hint: used config file '/usr/lib/nim/config/config.nims' [Conf]
Hint: used config file '/mnt/steel-chest/Monolab/Home/racha/src/Typos/config.nims' [Conf]
Hint: used config file '/mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/config.nims' [Conf]
Hint: mm: orc; threads: on; opt: speed; options: -d:release
51079 lines; 0.014s; 60.246MiB peakmem; proj: /mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/test_cli_args.nim; out: /home/scriptorium/.cache/nim/test_cli_args_r/test_cli_args_4602042F798320474EBFCD66F387B385BF9F0BDB [SuccessX]
Hint: /home/scriptorium/.cache/nim/test_cli_args_r/test_cli_args_4602042F798320474EBFCD66F387B385BF9F0BDB [Exec]

[Suite] typoi cli args
  [OK] defaults use openai codex and no tools
  [OK] read tools can be selected
  [OK] json stream can be selected
  [OK] yolo takes precedence over read tools
  [OK] prompt option maps to one shot prompt
  [OK] output last message path can be selected
  [OK] help option sets showHelp
  [OK] unknown option fails
  [OK] prompt arg prefers one shot in tty
  [OK] tty without prompt selects repl
  [OK] piped stdin without prompt selects one shot
  [OK] empty piped stdin fails
  [OK] anthropic provider can be selected
--- tests/test_diff.nim ---
Hint: used config file '/usr/lib/nim/config/nim.cfg' [Conf]
Hint: used config file '/usr/lib/nim/config/config.nims' [Conf]
Hint: used config file '/mnt/steel-chest/Monolab/Home/racha/src/Typos/config.nims' [Conf]
Hint: used config file '/mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/config.nims' [Conf]
Hint: mm: orc; threads: on; opt: speed; options: -d:release
51079 lines; 0.014s; 60.246MiB peakmem; proj: /mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/test_diff.nim; out: /home/scriptorium/.cache/nim/test_diff_r/test_diff_7030BF85CFA9410EF7DAD8B0256730CD4D3F8E85 [SuccessX]
Hint: /home/scriptorium/.cache/nim/test_diff_r/test_diff_7030BF85CFA9410EF7DAD8B0256730CD4D3F8E85 [Exec]

[Suite] git diff helpers
  [OK] parseDiffLines classifies each major line type
  [OK] diffStatusText returns empty status when no diff
  [OK] diffStatusText summarizes files and line counts
  [OK] readGitDiff reads unstaged diff from a real git repo
--- tests/test_dotfile_config.nim ---
Hint: used config file '/usr/lib/nim/config/nim.cfg' [Conf]
Hint: used config file '/usr/lib/nim/config/config.nims' [Conf]
Hint: used config file '/mnt/steel-chest/Monolab/Home/racha/src/Typos/config.nims' [Conf]
Hint: used config file '/mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/config.nims' [Conf]
Hint: mm: orc; threads: on; opt: speed; options: -d:release
51079 lines; 0.013s; 60.246MiB peakmem; proj: /mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/test_dotfile_config.nim; out: /home/scriptorium/.cache/nim/test_dotfile_config_r/test_dotfile_config_82BDBDD3D3E628E1F40B9FBD49200266E8BA49DF [SuccessX]
Hint: /home/scriptorium/.cache/nim/test_dotfile_config_r/test_dotfile_config_82BDBDD3D3E628E1F40B9FBD49200266E8BA49DF [Exec]

[Suite] dotfile config
  [OK] parse valid config with multiple profiles
  [OK] select profile by name
  [OK] fall back to defaultProfile when name not found
  [OK] fall back to empty when no default and no match
  [OK] empty string profile name falls back to default
  [OK] project config overrides dotfile config
  [OK] missing file returns empty config
  [OK] all profile fields are parsed
--- tests/test_git_tools.nim ---
Hint: used config file '/usr/lib/nim/config/nim.cfg' [Conf]
Hint: used config file '/usr/lib/nim/config/config.nims' [Conf]
Hint: used config file '/mnt/steel-chest/Monolab/Home/racha/src/Typos/config.nims' [Conf]
Hint: used config file '/mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/config.nims' [Conf]
Hint: mm: orc; threads: on; opt: speed; options: -d:release
51079 lines; 0.014s; 60.246MiB peakmem; proj: /mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/test_git_tools.nim; out: /home/scriptorium/.cache/nim/test_git_tools_r/test_git_tools_221374885A35E90BEBC85E56AD6C1A93A9923739 [SuccessX]
Hint: /home/scriptorium/.cache/nim/test_git_tools_r/test_git_tools_221374885A35E90BEBC85E56AD6C1A93A9923739 [Exec]

[Suite] git read tools
  [OK] registry contains new git read tools
  [OK] git_log returns recent commits
  [OK] git_log with file_path filters
  [OK] git_diff_staged shows staged changes
  [OK] git_diff_staged empty when nothing staged
  [OK] git_show displays commit at HEAD
  [OK] git_show with file_path shows file content at ref
  [OK] git_show missing ref returns validation error
  [OK] git_branch lists branches

[Suite] git write tools
  [OK] registry contains git write tools
  [OK] git_add stages files
  [OK] git_add missing paths returns validation error
  [OK] git_commit creates commit with message
  [OK] git_commit empty message refused
  [OK] git_restore with staged=true unstages a file
  [OK] git_restore discards working tree changes
--- tests/test_mcp_tools.nim ---
Hint: used config file '/usr/lib/nim/config/nim.cfg' [Conf]
Hint: used config file '/usr/lib/nim/config/config.nims' [Conf]
Hint: used config file '/mnt/steel-chest/Monolab/Home/racha/src/Typos/config.nims' [Conf]
Hint: used config file '/mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/config.nims' [Conf]
Hint: mm: orc; threads: on; opt: speed; options: -d:release
51079 lines; 0.015s; 60.246MiB peakmem; proj: /mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/test_mcp_tools.nim; out: /home/scriptorium/.cache/nim/test_mcp_tools_r/test_mcp_tools_216DF98BFBE937B35DF582F9147D799A99A3BC60 [SuccessX]
Hint: /home/scriptorium/.cache/nim/test_mcp_tools_r/test_mcp_tools_216DF98BFBE937B35DF582F9147D799A99A3BC60 [Exec]

[Suite] mcp tools
  [OK] convert McpTool to ToolFunction
  [OK] MCP tools merge without colliding with native tools
  [OK] McpTool with nil inputSchema gets default parameters
--- tests/test_read_tools.nim ---
Hint: used config file '/usr/lib/nim/config/nim.cfg' [Conf]
Hint: used config file '/usr/lib/nim/config/config.nims' [Conf]
Hint: used config file '/mnt/steel-chest/Monolab/Home/racha/src/Typos/config.nims' [Conf]
Hint: used config file '/mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/config.nims' [Conf]
Hint: mm: orc; threads: on; opt: speed; options: -d:release
51079 lines; 0.015s; 60.246MiB peakmem; proj: /mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/test_read_tools.nim; out: /home/scriptorium/.cache/nim/test_read_tools_r/test_read_tools_3DC3A1A7C7B519B13EE0A0BD4576F07A4376CFA1 [SuccessX]
Hint: /home/scriptorium/.cache/nim/test_read_tools_r/test_read_tools_3DC3A1A7C7B519B13EE0A0BD4576F07A4376CFA1 [Exec]

[Suite] read tools
  [OK] registry contains all read tools
  [OK] system_pwd
  [OK] system_ls
  [OK] nim_check
    /mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/test_read_tools.nim(86, 40): Check failed: output.toLowerAscii().contains("ok")
  [FAILED] nimble_test
  [OK] nim_version
  [OK] find_files
  [OK] read_file
  [OK] awk
  [OK] ripgrep
  [OK] git_status
  [OK] git_diff

[Suite] read+write tools
  [OK] registry includes write tools
  [OK] create_issue
Error: execution of an external program failed: '/home/scriptorium/.cache/nim/test_read_tools_r/test_read_tools_3DC3A1A7C7B519B13EE0A0BD4576F07A4376CFA1'
make: *** [Makefile:14: test] Error 1

```
