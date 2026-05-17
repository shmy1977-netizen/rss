param(
  [Parameter(Mandatory = $true)]
  [string]$TextFile,

  [string]$Photo,

  [string]$EnvFile = ".env"
)

$ErrorActionPreference = "Stop"

function Load-DotEnv {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  Get-Content -LiteralPath $Path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) {
      return
    }

    $parts = $line.Split("=", 2)
    if ($parts.Count -ne 2) {
      return
    }

    $name = $parts[0].Trim()
    $value = $parts[1].Trim().Trim('"').Trim("'")
    if ($name) {
      [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
  }
}

function Send-Text {
  param(
    [string]$Token,
    [string]$ChannelId,
    [string]$Text
  )

  $uri = "https://api.telegram.org/bot$Token/sendMessage"
  Invoke-RestMethod -Method Post -Uri $uri -Body @{
    chat_id = $ChannelId
    text = $Text
    parse_mode = "HTML"
    disable_web_page_preview = $false
  } | Out-Null
}

function Send-PhotoUrl {
  param(
    [string]$Token,
    [string]$ChannelId,
    [string]$PhotoUrl,
    [string]$Caption
  )

  $uri = "https://api.telegram.org/bot$Token/sendPhoto"
  Invoke-RestMethod -Method Post -Uri $uri -Body @{
    chat_id = $ChannelId
    photo = $PhotoUrl
    caption = $Caption
    parse_mode = "HTML"
  } | Out-Null
}

function Send-PhotoFile {
  param(
    [string]$Token,
    [string]$ChannelId,
    [string]$PhotoPath,
    [string]$Caption
  )

  Add-Type -AssemblyName System.Net.Http

  $client = [System.Net.Http.HttpClient]::new()
  $content = [System.Net.Http.MultipartFormDataContent]::new()
  $stream = $null

  try {
    $content.Add([System.Net.Http.StringContent]::new($ChannelId), "chat_id")
    $content.Add([System.Net.Http.StringContent]::new($Caption), "caption")
    $content.Add([System.Net.Http.StringContent]::new("HTML"), "parse_mode")

    $stream = [System.IO.File]::OpenRead((Resolve-Path -LiteralPath $PhotoPath))
    $fileContent = [System.Net.Http.StreamContent]::new($stream)
    $content.Add($fileContent, "photo", [System.IO.Path]::GetFileName($PhotoPath))

    $uri = "https://api.telegram.org/bot$Token/sendPhoto"
    $response = $client.PostAsync($uri, $content).GetAwaiter().GetResult()
    $response.EnsureSuccessStatusCode() | Out-Null
  }
  finally {
    if ($stream) {
      $stream.Dispose()
    }
    $content.Dispose()
    $client.Dispose()
  }
}

Load-DotEnv -Path $EnvFile

$token = [Environment]::GetEnvironmentVariable("TELEGRAM_BOT_TOKEN", "Process")
$channelId = [Environment]::GetEnvironmentVariable("TELEGRAM_CHANNEL_ID", "Process")

if (-not $token) {
  throw "TELEGRAM_BOT_TOKEN is not set."
}

if (-not $channelId) {
  throw "TELEGRAM_CHANNEL_ID is not set."
}

if (-not (Test-Path -LiteralPath $TextFile)) {
  throw "Text file not found: $TextFile"
}

$text = Get-Content -LiteralPath $TextFile -Raw -Encoding UTF8
$text = $text.Trim()

if (-not $text) {
  throw "Text file is empty."
}

if ($Photo) {
  if ($Photo -match "^https?://") {
    Send-PhotoUrl -Token $token -ChannelId $channelId -PhotoUrl $Photo -Caption $text
  }
  else {
    if (-not (Test-Path -LiteralPath $Photo)) {
      throw "Photo file not found: $Photo"
    }
    Send-PhotoFile -Token $token -ChannelId $channelId -PhotoPath $Photo -Caption $text
  }
}
else {
  Send-Text -Token $token -ChannelId $channelId -Text $text
}

Write-Host "Published to Telegram channel $channelId"
