import
  std/strutils,
  ./common


proc providerName*(provider: ProviderKind): string =
  ## Return the canonical provider name for a provider kind.
  case provider
  of ProviderLmStudio:
    result = LmStudioProviderName
  of ProviderOpenAi:
    result = OpenAiProviderName
  of ProviderBedrock:
    result = BedrockProviderName


proc parseProviderKind*(name: string): ProviderKind =
  ## Parse a provider name into a provider kind.
  let normalized = name.toLowerAscii().replace("-", "_")
  case normalized
  of "lm_studio", "lmstudio", "local":
    result = ProviderLmStudio
  of "openai":
    result = ProviderOpenAi
  of "bedrock":
    result = ProviderBedrock
  else:
    raise newException(
      ValueError,
      "Unknown provider: " & name & ". Expected lm_studio, openai, or bedrock."
    )


proc defaultProviderConfig*(provider: ProviderKind): ProviderConfig =
  ## Build default provider configuration for the given provider.
  case provider
  of ProviderLmStudio:
    result = ProviderConfig(
      provider: ProviderLmStudio,
      model: LmStudioDefaultModel,
      baseUrl: LmStudioBaseUrl,
      apiEnvVar: ""
    )
  of ProviderOpenAi:
    result = ProviderConfig(
      provider: ProviderOpenAi,
      model: OpenAiDefaultModel,
      baseUrl: OpenAiBaseUrl,
      apiEnvVar: OpenAiApiEnvVar
    )
  of ProviderBedrock:
    result = ProviderConfig(
      provider: ProviderBedrock,
      model: BedrockDefaultModel,
      baseUrl: BedrockBaseUrl,
      apiEnvVar: BedrockApiEnvVar
    )


proc resolveProviderConfig*(
  providerName: string,
  modelOverride: string,
  baseUrlOverride: string,
  apiEnvVarOverride: string
): ProviderConfig =
  ## Resolve provider configuration from defaults plus CLI overrides.
  let provider = parseProviderKind(providerName)
  result = defaultProviderConfig(provider)

  if modelOverride.len > 0:
    result.model = modelOverride
  if baseUrlOverride.len > 0:
    result.baseUrl = baseUrlOverride
  if apiEnvVarOverride.len > 0:
    result.apiEnvVar = apiEnvVarOverride
