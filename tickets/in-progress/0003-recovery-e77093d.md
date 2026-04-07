# Recovery: Fix Failing Tests on Main Branch

**Area:** recovery

The main branch tests are failing at commit e77093d. Diagnose the failure from the test output below and fix the root cause. Keep the fix minimal and targeted.

## Test Failure Output

```
--- tests/test_cli_args.nim ---
Hint: used config file '/usr/lib/nim/config/nim.cfg' [Conf]
Hint: used config file '/usr/lib/nim/config/config.nims' [Conf]
Hint: used config file '/mnt/steel-chest/Monolab/Home/racha/src/Typos/config.nims' [Conf]
Hint: used config file '/mnt/steel-chest/Monolab/Home/racha/src/Typos/tests/config.nims' [Conf]
.....................................................................................................................................
/mnt/steel-chest/Monolab/Home/racha/src/Typos/src/Typos/common.nim(4, 3) Error: cannot open file: chroma
make: *** [Makefile:14: test] Error 1

```

**Worktree:** /mnt/steel-chest/Monolab/Home/racha/src/Typos/.scriptorium/worktrees/tickets/0003-recovery-e77093d

## Agent Run
- Model: claude-sonnet-4-6\n- Backend: claude-code\n- Exit Code: 0\n- Attempt: 1\n- Attempt Count: 1\n- Timeout: none\n- Log File: /mnt/steel-chest/Monolab/Home/racha/src/Typos/.scriptorium/logs/coder/0003/attempt-01.jsonl\n- Last Message File: /mnt/steel-chest/Monolab/Home/racha/src/Typos/.scriptorium/logs/coder/0003/attempt-01.last_message.txt\n
### Agent Last Message
```text
Done. Here's a summary of the fix:

**Root cause:** `common.nim` mixed provider string constants with UI types that require `chroma` and `bumpy`. When `cli_args.nim` imported `common` just for `OpenAiProviderName`, it transitively required `chroma` — which broke test compilation when that package wasn't in the search path.

**Fix (3 files):**
1. **New `src/Typos/providers.nim`** — provider types (`ProviderKind`, `ProviderConfig`) and all provider constants, with zero external dependencies
2. **`src/Typos/common.nim`** — now imports and `export`s `providers`, so existing consumers are unaffected
3. **`src/Typoi/cli_args.nim`** — imports `providers` instead of `common`, breaking the unnecessary `chroma`/`bumpy` dependency

All tests that were previously blocked now compile and pass. The build also succeeds.
```

### Agent Stdout Tail
```text
and all provider constants, with zero external dependencies\n2. **`src/Typos/common.nim`** — now imports and `export`s `providers`, so existing consumers are unaffected\n3. **`src/Typoi/cli_args.nim`** — imports `providers` instead of `common`, breaking the unnecessary `chroma`/`bumpy` dependency\n\nAll tests that were previously blocked now compile and pass. The build also succeeds.","stop_reason":"end_turn","session_id":"9ab5afaa-ca36-4b1c-ad62-29ae7f887865","total_cost_usd":2.228537750000001,"usage":{"input_tokens":136,"cache_creation_input_tokens":75573,"cache_read_input_tokens":2770403,"output_tokens":14813,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":75573},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"us.anthropic.claude-opus-4-6-v1":{"inputTokens":136,"outputTokens":14813,"cacheReadInputTokens":2770403,"cacheCreationInputTokens":75573,"webSearchRequests":0,"costUSD":2.228537750000001,"contextWindow":200000,"maxOutputTokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"aa74be35-3fd4-4164-8d6e-39deef9a634e"}
```
