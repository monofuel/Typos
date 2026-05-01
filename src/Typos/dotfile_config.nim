import
  std/[json, os, tables]


type
  ProfileConfig* = object
    provider*: string
    model*: string
    apiKeyEnv*: string
    baseUrl*: string
    region*: string
    reasoningEffort*: string

  DotfileConfig* = object
    defaultProfile*: string
    profiles*: Table[string, ProfileConfig]


proc parseDotfileConfig*(jsonStr: string): DotfileConfig =
  ## Parse a JSON string into a DotfileConfig.
  let node = parseJson(jsonStr)

  if node.hasKey("defaultProfile"):
    result.defaultProfile = node["defaultProfile"].getStr

  if node.hasKey("profiles"):
    for key, val in node["profiles"].pairs:
      var profile: ProfileConfig
      if val.hasKey("provider"):
        profile.provider = val["provider"].getStr
      if val.hasKey("model"):
        profile.model = val["model"].getStr
      if val.hasKey("apiKeyEnv"):
        profile.apiKeyEnv = val["apiKeyEnv"].getStr
      if val.hasKey("baseUrl"):
        profile.baseUrl = val["baseUrl"].getStr
      if val.hasKey("region"):
        profile.region = val["region"].getStr
      if val.hasKey("reasoningEffort"):
        profile.reasoningEffort = val["reasoningEffort"].getStr
      result.profiles[key] = profile


proc loadDotfileConfig*(): DotfileConfig =
  ## Load config from ~/.typos/config.json. Returns empty default if missing.
  let configPath = getHomeDir() / ".typos" / "config.json"
  if not fileExists(configPath):
    return
  try:
    result = parseDotfileConfig(readFile(configPath))
  except:
    return


proc loadProjectConfig*(): DotfileConfig =
  ## Load config from .typos.json in cwd. Returns empty default if missing.
  let configPath = getCurrentDir() / ".typos.json"
  if not fileExists(configPath):
    return
  try:
    result = parseDotfileConfig(readFile(configPath))
  except:
    return


proc mergeConfigs*(dotfile, project: DotfileConfig): DotfileConfig =
  ## Merge two configs, project overrides dotfile at the profile level.
  result = dotfile

  if project.defaultProfile.len > 0:
    result.defaultProfile = project.defaultProfile

  for key, profile in project.profiles.pairs:
    result.profiles[key] = profile


proc resolveProfile*(config: DotfileConfig, profileName: string): ProfileConfig =
  ## Look up named profile, fall back to defaultProfile, fall back to empty.
  if profileName.len > 0 and config.profiles.hasKey(profileName):
    return config.profiles[profileName]
  if config.defaultProfile.len > 0 and config.profiles.hasKey(config.defaultProfile):
    return config.profiles[config.defaultProfile]
  return ProfileConfig()
