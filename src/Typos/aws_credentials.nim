import
  std/[os, osproc, strutils, times]

const
  TokenDurationSeconds = 43200
  ExpirationBufferSeconds = 60
  TokenScript = """
import boto3, base64
from botocore.auth import SigV4QueryAuth
from botocore.awsrequest import AWSRequest
session = boto3.Session()
creds = session.get_credentials().get_frozen_credentials()
req = AWSRequest(method="POST", url="https://bedrock.amazonaws.com/",
  headers={"host": "bedrock.amazonaws.com"},
  params={"Action": "CallWithBearerToken"})
auth = SigV4QueryAuth(creds, "bedrock", "$REGION", expires=$EXPIRES)
auth.add_auth(req)
url = req.url.replace("https://", "") + "&Version=1"
print("bedrock-api-key-" + base64.b64encode(url.encode()).decode())
"""

var
  cachedToken: string
  cachedExpiration: Time


proc getBedrockToken*(region: string = "us-east-1"): string =
  ## Generate a Bedrock Mantle bearer token via AWS SigV4 presigning.
  if cachedToken.len > 0 and getTime() < cachedExpiration:
    return cachedToken

  let script = TokenScript
    .replace("$REGION", region)
    .replace("$EXPIRES", $TokenDurationSeconds)

  let (output, exitCode) = execCmdEx("python3 -c " & quoteShell(script))
  if exitCode != 0:
    raise newException(IOError, "Bedrock token generation failed: " & output)

  cachedToken = output.strip()
  cachedExpiration = getTime() + initDuration(
    seconds = TokenDurationSeconds - ExpirationBufferSeconds)

  return cachedToken
