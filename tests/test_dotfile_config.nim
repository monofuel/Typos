import
  std/[unittest, tables],
  Typos/dotfile_config


suite "dotfile config":
  test "parse valid config with multiple profiles":
    let config = parseDotfileConfig("""
    {
      "defaultProfile": "dev",
      "profiles": {
        "dev": {
          "provider": "lm_studio",
          "model": "qwen3-coder",
          "baseUrl": "http://localhost:1234/v1"
        },
        "prod": {
          "provider": "openai",
          "model": "gpt-5.1-codex-mini",
          "apiKeyEnv": "OPENAI_API_KEY"
        }
      }
    }
    """)
    check config.defaultProfile == "dev"
    check config.profiles.len == 2
    check config.profiles["dev"].provider == "lm_studio"
    check config.profiles["dev"].model == "qwen3-coder"
    check config.profiles["prod"].provider == "openai"
    check config.profiles["prod"].apiKeyEnv == "OPENAI_API_KEY"

  test "select profile by name":
    let config = parseDotfileConfig("""
    {
      "defaultProfile": "dev",
      "profiles": {
        "dev": {"provider": "lm_studio"},
        "prod": {"provider": "openai"}
      }
    }
    """)
    let profile = resolveProfile(config, "prod")
    check profile.provider == "openai"

  test "fall back to defaultProfile when name not found":
    let config = parseDotfileConfig("""
    {
      "defaultProfile": "dev",
      "profiles": {
        "dev": {"provider": "lm_studio"}
      }
    }
    """)
    let profile = resolveProfile(config, "nonexistent")
    check profile.provider == "lm_studio"

  test "fall back to empty when no default and no match":
    let config = parseDotfileConfig("""
    {
      "profiles": {
        "dev": {"provider": "lm_studio"}
      }
    }
    """)
    let profile = resolveProfile(config, "nonexistent")
    check profile.provider == ""

  test "empty string profile name falls back to default":
    let config = parseDotfileConfig("""
    {
      "defaultProfile": "dev",
      "profiles": {
        "dev": {"provider": "anthropic", "model": "claude-sonnet-4-6"}
      }
    }
    """)
    let profile = resolveProfile(config, "")
    check profile.provider == "anthropic"
    check profile.model == "claude-sonnet-4-6"

  test "project config overrides dotfile config":
    let dotfile = parseDotfileConfig("""
    {
      "defaultProfile": "dev",
      "profiles": {
        "dev": {"provider": "lm_studio", "model": "qwen3"},
        "prod": {"provider": "openai"}
      }
    }
    """)
    let project = parseDotfileConfig("""
    {
      "defaultProfile": "prod",
      "profiles": {
        "dev": {"provider": "anthropic", "model": "claude-sonnet-4-6"}
      }
    }
    """)
    let merged = mergeConfigs(dotfile, project)
    check merged.defaultProfile == "prod"
    check merged.profiles["dev"].provider == "anthropic"
    check merged.profiles["prod"].provider == "openai"

  test "missing file returns empty config":
    # loadDotfileConfig and loadProjectConfig handle missing files gracefully
    # We test parseDotfileConfig with minimal valid JSON
    let config = parseDotfileConfig("{}")
    check config.defaultProfile == ""
    check config.profiles.len == 0

  test "all profile fields are parsed":
    let config = parseDotfileConfig("""
    {
      "profiles": {
        "full": {
          "provider": "bedrock",
          "model": "openai.gpt-oss-20b",
          "apiKeyEnv": "AWS_BEDROCK_TOKEN",
          "baseUrl": "https://bedrock.example.com/v1",
          "reasoningEffort": "high"
        }
      }
    }
    """)
    let profile = config.profiles["full"]
    check profile.provider == "bedrock"
    check profile.model == "openai.gpt-oss-20b"
    check profile.apiKeyEnv == "AWS_BEDROCK_TOKEN"
    check profile.baseUrl == "https://bedrock.example.com/v1"
    check profile.reasoningEffort == "high"
