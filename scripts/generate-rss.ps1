param(
  [string]$PostsFile = ".\data\posts.json",
  [string]$FeedFile = ".\data\feed.json",
  [string]$OutputFile = ".\public\rss.xml"
)

$ErrorActionPreference = "Stop"

function Convert-ToRfc822Date {
  param([string]$DateText)

  $date = [DateTimeOffset]::Parse($DateText)
  return $date.ToString("r")
}

function Escape-XmlText {
  param([string]$Value)

  if ($null -eq $Value) {
    return ""
  }

  return [System.Security.SecurityElement]::Escape($Value)
}

if (-not (Test-Path -LiteralPath $PostsFile)) {
  throw "Posts file not found: $PostsFile"
}

if (-not (Test-Path -LiteralPath $FeedFile)) {
  throw "Feed file not found: $FeedFile"
}

$posts = Get-Content -LiteralPath $PostsFile -Raw -Encoding UTF8 | ConvertFrom-Json
$feed = Get-Content -LiteralPath $FeedFile -Raw -Encoding UTF8 | ConvertFrom-Json

$outputDir = Split-Path -Parent $OutputFile
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
  New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$latestDate = if ($posts.Count -gt 0) {
  Convert-ToRfc822Date -DateText (($posts | Sort-Object published -Descending | Select-Object -First 1).published)
}
else {
  [DateTimeOffset]::Now.ToString("r")
}

$items = foreach ($post in ($posts | Sort-Object published -Descending)) {
  $title = Escape-XmlText -Value $post.title
  $link = Escape-XmlText -Value $post.link
  $date = Convert-ToRfc822Date -DateText $post.published
  $guid = if ($post.guid) { Escape-XmlText -Value $post.guid } else { $link }
  $description = $post.description

  if ($post.image) {
    $description = "$description`n`nImage: $($post.image)"
  }

  @"
    <item>
      <title>$title</title>
      <link>$link</link>
      <guid isPermaLink="false">$guid</guid>
      <pubDate>$date</pubDate>
      <description><![CDATA[$description]]></description>
    </item>
"@
}

$channelTitle = Escape-XmlText -Value $feed.title
$channelLink = Escape-XmlText -Value $feed.link
$channelDescription = Escape-XmlText -Value $feed.description

$rss = @"
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>$channelTitle</title>
    <link>$channelLink</link>
    <description>$channelDescription</description>
    <language>ru</language>
    <lastBuildDate>$latestDate</lastBuildDate>
$($items -join "`n")
  </channel>
</rss>
"@

$fullOutputPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputFile))
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($fullOutputPath, $rss, $utf8NoBom)

Write-Host "RSS generated: $OutputFile"
