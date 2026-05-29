$ErrorActionPreference = "Stop"

$port = 4173
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dataFile = Join-Path $root "data.json"
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Prefixes.Add("http://127.0.0.1:$port/")

function Send-Text($Response, [int]$StatusCode, [string]$Text, [string]$ContentType) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $Response.StatusCode = $StatusCode
  $Response.ContentType = $ContentType
  $Response.ContentLength64 = $bytes.Length
  $Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $Response.OutputStream.Close()
}

function Send-Json($Response, [int]$StatusCode, $Value) {
  Send-Text $Response $StatusCode ($Value | ConvertTo-Json -Depth 20) "application/json; charset=utf-8"
}

function Read-Data {
  Get-Content -LiteralPath $dataFile -Raw | ConvertFrom-Json
}

function Write-Data($Data) {
  $Data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $dataFile -Encoding UTF8
}

function Read-JsonBody($Request) {
  $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
  $body = $reader.ReadToEnd()
  $reader.Close()
  if ([string]::IsNullOrWhiteSpace($body)) {
    return @{}
  }
  return $body | ConvertFrom-Json
}

function Normalize-Route($Route) {
  [pscustomobject]@{
    number = ([string]$Route.number).Trim().ToUpperInvariant()
    from = ([string]$Route.from).Trim()
    to = ([string]$Route.to).Trim()
    fare = [int]$Route.fare
    duration = ([string]$Route.duration).Trim()
    stops = @($Route.stops | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    timings = @($Route.timings | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
  }
}

function Handle-Api($Context, [string]$Path) {
  $request = $Context.Request
  $response = $Context.Response
  $data = Read-Data

  if ($request.HttpMethod -eq "GET" -and $Path -eq "/api/routes") {
    Send-Json $response 200 @($data.routes)
    return
  }

  if ($request.HttpMethod -eq "POST" -and $Path -eq "/api/routes") {
    $route = Normalize-Route (Read-JsonBody $request)
    if (-not $route.number -or -not $route.from -or -not $route.to -or $route.stops.Count -eq 0 -or $route.timings.Count -eq 0) {
      Send-Json $response 400 @{ error = "Bus number, from, to, stops, and timings are required." }
      return
    }

    $routes = @($data.routes | Where-Object { $_.number -ne $route.number })
    $data.routes = @($routes + $route)
    Write-Data $data
    Send-Json $response 200 $route
    return
  }

  if ($request.HttpMethod -eq "DELETE" -and $Path.StartsWith("/api/routes/")) {
    $number = [System.Uri]::UnescapeDataString($Path.Replace("/api/routes/", ""))
    $data.routes = @($data.routes | Where-Object { $_.number -ne $number })
    if ($data.driverUpdates.PSObject.Properties.Name -contains $number) {
      $data.driverUpdates.PSObject.Properties.Remove($number)
    }
    Write-Data $data
    Send-Json $response 200 @{ ok = $true }
    return
  }

  if ($request.HttpMethod -eq "GET" -and $Path -eq "/api/driver-updates") {
    Send-Json $response 200 $data.driverUpdates
    return
  }

  if ($request.HttpMethod -eq "POST" -and $Path -eq "/api/driver-updates") {
    $body = Read-JsonBody $request
    $routeNumber = ([string]$body.routeNumber).Trim().ToUpperInvariant()
    if (-not $routeNumber) {
      Send-Json $response 400 @{ error = "Route number is required." }
      return
    }

    $data.driverUpdates | Add-Member -NotePropertyName $routeNumber -NotePropertyValue ([pscustomobject]@{
      driver = if ($body.driver) { ([string]$body.driver).Trim() } else { "Driver" }
      stop = if ($body.stop) { ([string]$body.stop).Trim() } else { "Not updated" }
      status = if ($body.status) { ([string]$body.status).Trim() } else { "On time" }
      delay = if ($body.delay) { ([string]$body.delay).Trim() } else { "0" }
      updatedAt = (Get-Date).ToString("hh:mm tt")
    }) -Force

    Write-Data $data
    Send-Json $response 200 $data.driverUpdates.$routeNumber
    return
  }

  Send-Json $response 404 @{ error = "API route not found." }
}

function Serve-File($Context, [string]$Path) {
  $response = $Context.Response
  if ($Path -eq "/") {
    $Path = "/index.html"
  }

  $relative = $Path.TrimStart("/").Replace("/", [System.IO.Path]::DirectorySeparatorChar)
  $filePath = [System.IO.Path]::GetFullPath((Join-Path $root $relative))
  if (-not $filePath.StartsWith($root)) {
    Send-Text $response 403 "Forbidden" "text/plain; charset=utf-8"
    return
  }

  if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
    Send-Text $response 404 "Not found" "text/plain; charset=utf-8"
    return
  }

  $extension = [System.IO.Path]::GetExtension($filePath)
  $contentType = switch ($extension) {
    ".html" { "text/html; charset=utf-8" }
    ".json" { "application/json; charset=utf-8" }
    ".js" { "text/javascript; charset=utf-8" }
    ".css" { "text/css; charset=utf-8" }
    default { "application/octet-stream" }
  }

  $bytes = [System.IO.File]::ReadAllBytes($filePath)
  $response.StatusCode = 200
  $response.ContentType = $contentType
  $response.ContentLength64 = $bytes.Length
  $response.OutputStream.Write($bytes, 0, $bytes.Length)
  $response.OutputStream.Close()
}

$listener.Start()
Write-Host "Bus app running at http://localhost:$port"

while ($listener.IsListening) {
  $context = $listener.GetContext()
  try {
    $path = $context.Request.Url.AbsolutePath
    if ($path.StartsWith("/api/")) {
      Handle-Api $context $path
    } else {
      Serve-File $context $path
    }
  } catch {
    Send-Json $context.Response 500 @{ error = $_.Exception.Message }
  }
}
