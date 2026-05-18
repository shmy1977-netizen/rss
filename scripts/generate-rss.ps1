param(
  [string]$PostsFile = ".\data\posts.json",
  [string]$FeedFile = ".\data\feed.json",
  [string]$OutputFile = ".\public\rss.xml",
  [string]$ImageBaseUrl = "https://shmy1977-netizen.github.io/rss/public/images"
)

$ErrorActionPreference = "Stop"

function Convert-ToRfc822Date {
  param([string]$DateText)

  $date = [DateTimeOffset]::Parse($DateText)
  return Convert-DateToRfc822 -Date $date
}

function Convert-DateToRfc822 {
  param([DateTimeOffset]$Date)

  $culture = [System.Globalization.CultureInfo]::InvariantCulture
  $offset = $Date.ToString("zzz", $culture).Replace(":", "")
  return $Date.ToString("ddd, dd MMM yyyy HH:mm:ss ", $culture) + $offset
}

function Escape-XmlText {
  param([string]$Value)

  if ($null -eq $Value) {
    return ""
  }

  return [System.Security.SecurityElement]::Escape($Value)
}

function Get-ImageMimeType {
  param([string]$Path)

  $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
  switch ($extension) {
    ".jpg" { return "image/jpeg" }
    ".jpeg" { return "image/jpeg" }
    ".png" { return "image/png" }
    ".webp" { return "image/webp" }
    ".gif" { return "image/gif" }
    default { return "application/octet-stream" }
  }
}

function Get-StableHash {
  param([string]$Value)

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
  $sha1 = [System.Security.Cryptography.SHA1]::Create()
  try {
    $hashBytes = $sha1.ComputeHash($bytes)
  }
  finally {
    $sha1.Dispose()
  }

  return ([System.BitConverter]::ToString($hashBytes)).Replace("-", "").Substring(0, 10).ToLowerInvariant()
}

function Get-PostGuid {
  param([psobject]$Post)

  $date = [DateTimeOffset]::Parse([string]$Post.published)
  $hash = Get-StableHash -Value "$($Post.title)|$($Post.published)|$($Post.description)"
  return "tag:shmy1977-netizen.github.io,$($date.ToString("yyyy-MM-dd")):rss/$hash"
}

function Get-ImageFileName {
  param(
    [psobject]$Post,
    [string]$SourcePath
  )

  $extension = [System.IO.Path]::GetExtension($SourcePath).ToLowerInvariant()
  if (-not $extension) {
    $extension = ".jpg"
  }

  $date = [DateTimeOffset]::Parse([string]$Post.published)
  $key = "$($Post.title)|$($Post.link)|$($Post.published)"
  $hash = Get-StableHash -Value $key

  return "$($date.ToString("yyyyMMddHHmmss"))-$hash$extension"
}

function Resolve-PostImage {
  param(
    [psobject]$Post,
    [string]$OutputDirectory,
    [string]$BaseUrl
  )

  if (-not $Post.image) {
    return $null
  }

  $image = [string]$Post.image
  if ($image -match "^https?://") {
    return [pscustomobject]@{
      Url = $image
      MimeType = Get-ImageMimeType -Path $image
      Length = $null
    }
  }

  if (-not (Test-Path -LiteralPath $image)) {
    Write-Warning "Image file not found, skipping RSS image: $image"
    return $null
  }

  $imagesDir = Join-Path $OutputDirectory "images"
  if (-not (Test-Path -LiteralPath $imagesDir)) {
    New-Item -ItemType Directory -Path $imagesDir | Out-Null
  }

  $fileName = Get-ImageFileName -Post $Post -SourcePath $image
  $targetPath = Join-Path $imagesDir $fileName
  Copy-Item -LiteralPath $image -Destination $targetPath -Force

  $file = Get-Item -LiteralPath $targetPath
  return [pscustomobject]@{
    Url = "$($BaseUrl.TrimEnd("/"))/$fileName"
    MimeType = Get-ImageMimeType -Path $targetPath
    Length = $file.Length
  }
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

$fullOutputDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $outputDir))

$latestDate = if ($posts.Count -gt 0) {
  Convert-ToRfc822Date -DateText (($posts | Sort-Object published -Descending | Select-Object -First 1).published)
}
else {
  Convert-DateToRfc822 -Date ([DateTimeOffset]::Now)
}

$items = foreach ($post in ($posts | Sort-Object published -Descending)) {
  $title = Escape-XmlText -Value $post.title
  $date = Convert-ToRfc822Date -DateText $post.published
  $guid = Escape-XmlText -Value (Get-PostGuid -Post $post)
  $description = $post.description
  $imageInfo = Resolve-PostImage -Post $post -OutputDirectory $fullOutputDir -BaseUrl $ImageBaseUrl
  $imageTags = ""

  if ($imageInfo) {
    $imageUrl = Escape-XmlText -Value $imageInfo.Url
    $imageMimeType = Escape-XmlText -Value $imageInfo.MimeType
    $description = "<p><img src=""$imageUrl"" alt=""$title"" /></p>`n`n$description"

    $enclosureTag = if ($imageInfo.Length) {
      "      <enclosure url=""$imageUrl"" length=""$($imageInfo.Length)"" type=""$imageMimeType"" />"
    }
    else {
      ""
    }

    $imageTags = @"
$enclosureTag
      <media:content url="$imageUrl" medium="image" type="$imageMimeType" />
      <media:thumbnail url="$imageUrl" />
"@
  }

  @"
    <item>
      <title>$title</title>
      <guid isPermaLink="false">$guid</guid>
      <pubDate>$date</pubDate>
      <description><![CDATA[$description]]></description>
$imageTags
    </item>
"@
}

$channelTitle = Escape-XmlText -Value $feed.title
$channelLink = Escape-XmlText -Value $feed.link
$channelDescription = Escape-XmlText -Value $feed.description

$rss = @"
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
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
