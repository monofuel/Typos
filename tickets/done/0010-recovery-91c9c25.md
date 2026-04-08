# Recovery: Fix Failing Tests on Main Branch

**Area:** recovery

The main branch tests are failing at commit 91c9c25. Diagnose the failure from the test output below and fix the root cause. Keep the fix minimal and targeted.

## Test Failure Output

```
--- tests/test_cli_args.nim ---
Hint: used config file '/usr/lib/nim/config/nim.cfg' [Conf]
Hint: used config file '/usr/lib/nim/config/config.nims' [Conf]
Hint: used config file '/mnt/steel-chest/Monolab/Home/racha/src/Typos/config.nims' [Conf]
Hint: used config file '/mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/config.nims' [Conf]
..................................................................................................................................................
CC: system/exceptions.nim
CC: std/private/digitsutils.nim
CC: std/assertions.nim
CC: system/dollars.nim
CC: std/syncio.nim
CC: system.nim
CC: std/exitprocs.nim
CC: math.nim
CC: unicode.nim
CC: strutils.nim
CC: streams.nim
CC: times.nim
CC: hashes.nim
CC: sets.nim
CC: std/envvars.nim
CC: std/cmdline.nim
CC: strformat.nim
CC: terminal.nim
CC: unittest.nim
CC: parseopt.nim
CC: Typoi/cli_args.nim
CC: test_cli_args.nim
Hint:  [Link]
Hint: mm: orc; threads: on; opt: speed; options: -d:release
112863 lines; 1.659s; 179.32MiB peakmem; proj: /mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/test_cli_args.nim; out: /home/scriptorium/.cache/nim/test_cli_args_r/test_cli_args_4602042F798320474EBFCD66F387B385BF9F0BDB [SuccessX]
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
...........................................................................................................................................
CC: system/exceptions.nim
CC: std/private/digitsutils.nim
CC: std/assertions.nim
CC: system/dollars.nim
CC: std/syncio.nim
CC: system.nim
CC: math.nim
CC: algorithm.nim
CC: unicode.nim
CC: strutils.nim
CC: pathnorm.nim
CC: std/oserrors.nim
CC: posix.nim
CC: std/private/oscommon.nim
CC: std/private/ospaths2.nim
CC: times.nim
CC: std/private/osfiles.nim
CC: std/private/osdirs.nim
CC: std/envvars.nim
CC: std/private/osappdirs.nim
CC: std/cmdline.nim
CC: os.nim
CC: hashes.nim
CC: strtabs.nim
CC: streams.nim
CC: std/monotimes.nim
CC: osproc.nim
CC: std/exitprocs.nim
CC: sets.nim
CC: strformat.nim
CC: terminal.nim
CC: unittest.nim
CC: Typos/git_diff.nim
CC: test_diff.nim
Hint:  [Link]
Hint: mm: orc; threads: on; opt: speed; options: -d:release
105539 lines; 1.662s; 144.191MiB peakmem; proj: /mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/test_diff.nim; out: /home/scriptorium/.cache/nim/test_diff_r/test_diff_7030BF85CFA9410EF7DAD8B0256730CD4D3F8E85 [SuccessX]
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
.........................................................................................................................................
CC: system/exceptions.nim
CC: std/private/digitsutils.nim
CC: std/assertions.nim
CC: system/dollars.nim
CC: std/syncio.nim
CC: system.nim
CC: std/exitprocs.nim
CC: parseutils.nim
CC: math.nim
CC: unicode.nim
CC: strutils.nim
CC: streams.nim
CC: times.nim
CC: hashes.nim
CC: sets.nim
CC: std/envvars.nim
CC: std/cmdline.nim
CC: strformat.nim
CC: terminal.nim
CC: unittest.nim
CC: tables.nim
CC: lexbase.nim
CC: parsejson.nim
CC: json.nim
CC: Typos/dotfile_config.nim
CC: test_dotfile_config.nim
Hint:  [Link]
Hint: mm: orc; threads: on; opt: speed; options: -d:release
108003 lines; 2.343s; 144.156MiB peakmem; proj: /mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/test_dotfile_config.nim; out: /home/scriptorium/.cache/nim/test_dotfile_config_r/test_dotfile_config_82BDBDD3D3E628E1F40B9FBD49200266E8BA49DF [SuccessX]
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
..........................................................................................................................................................................................
CC: system/exceptions.nim
CC: std/private/digitsutils.nim
CC: std/assertions.nim
CC: system/dollars.nim
CC: std/syncio.nim
CC: system.nim
CC: hashes.nim
CC: math.nim
CC: algorithm.nim
CC: tables.nim
CC: unicode.nim
CC: strutils.nim
CC: streams.nim
CC: json.nim
CC: pathnorm.nim
CC: std/oserrors.nim
CC: posix.nim
CC: std/private/oscommon.nim
CC: std/private/ospaths2.nim
CC: std/private/ossymlinks.nim
CC: times.nim
CC: std/private/osfiles.nim
CC: std/private/osdirs.nim
CC: std/envvars.nim
CC: std/private/osappdirs.nim
CC: std/cmdline.nim
CC: os.nim
CC: strtabs.nim
CC: std/monotimes.nim
CC: osproc.nim
CC: std/exitprocs.nim
CC: sets.nim
CC: strformat.nim
CC: terminal.nim
CC: unittest.nim
CC: random.nim
CC: libcurl.nim
CC: curly.nim
CC: openai_leap/common.nim
CC: openai_leap/responses.nim
CC: pcre.nim
CC: rtarrays.nim
CC: re.nim
CC: Typos/tools/registry.nim
CC: test_git_tools.nim
Hint:  [Link]
Hint: mm: orc; threads: on; opt: speed; options: -d:release
124009 lines; 5.452s; 277.301MiB peakmem; proj: /mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/test_git_tools.nim; out: /home/scriptorium/.cache/nim/test_git_tools_r/test_git_tools_221374885A35E90BEBC85E56AD6C1A93A9923739 [SuccessX]
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
 

(output truncated)
```
