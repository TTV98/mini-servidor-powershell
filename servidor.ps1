<#
  Mini servidor local em PowerShell (exemplo didático)

  - Mostra os arquivos da pasta "site" em http://localhost:8090/
  - Salva e lê arquivos JSON só na pasta "dados" (nenhuma outra pasta pode ser gravada)
  - Antes de sobrescrever um arquivo, guarda a versão anterior em "dados\versoes-anteriores"
  - Escuta apenas no próprio computador (localhost)

  Para parar: Ctrl+C nesta janela.
#>
param(
  [int]$Porta = 8090,
  [string]$PastaSite = (Join-Path $PSScriptRoot 'site'),
  [string]$PastaDados = (Join-Path $PSScriptRoot 'dados'),
  [string]$ArquivoLog = (Join-Path $PSScriptRoot 'servidor-erros.log'),
  [int]$LimiteBytes = 1MB,
  [switch]$AbrirNavegador
)

$ErrorActionPreference = 'Stop'

$PastaSite    = [IO.Path]::GetFullPath($PastaSite)
$PastaDados   = [IO.Path]::GetFullPath($PastaDados)
$PastaVersoes = Join-Path $PastaDados 'versoes-anteriores'
New-Item -ItemType Directory -Force -Path $PastaDados, $PastaVersoes | Out-Null

# Só estes tipos de arquivo saem da pasta "site"
$Tipos = @{
  '.html' = 'text/html; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.js'   = 'text/javascript; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.png'  = 'image/png'
  '.svg'  = 'image/svg+xml'
  '.ico'  = 'image/x-icon'
}

# Nome de arquivo aceito para salvar: letras minúsculas, números e hífen (ex.: anotacoes.json)
$NomeValido = '^[a-z0-9-]{1,40}\.json$'

function Responder($ctx, [int]$status, [byte[]]$corpo, [string]$tipo) {
  $r = $ctx.Response
  $r.StatusCode = $status
  $r.ContentType = $tipo
  $r.Headers['X-Content-Type-Options'] = 'nosniff'
  $r.Headers['Cache-Control'] = 'no-store'
  $r.ContentLength64 = $corpo.Length
  $r.OutputStream.Write($corpo, 0, $corpo.Length)
  $r.Close()
}

function ResponderJson($ctx, [int]$status, $objeto) {
  $texto = $objeto | ConvertTo-Json -Compress -Depth 5
  Responder $ctx $status ([Text.Encoding]::UTF8.GetBytes($texto)) 'application/json; charset=utf-8'
}

# Devolve o caminho completo só se ele ficar DENTRO da pasta. Bloqueia truques como ..\..\Windows
function DentroDaPasta([string]$pasta, [string]$relativo) {
  try {
    $completo = [IO.Path]::GetFullPath([IO.Path]::Combine($pasta, $relativo))
  } catch {
    return $null
  }
  if ($completo.StartsWith($pasta.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $completo }
  return $null
}

function ServirArquivo($ctx) {
  $relativo = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart('/')
  if ($relativo -eq '' -or $relativo.EndsWith('/')) { $relativo += 'index.html' }
  $arquivo = DentroDaPasta $PastaSite ($relativo -replace '/', '\')
  if (-not $arquivo -or -not (Test-Path -LiteralPath $arquivo -PathType Leaf)) {
    return ResponderJson $ctx 404 @{ erro = 'Arquivo não encontrado' }
  }
  $extensao = [IO.Path]::GetExtension($arquivo).ToLower()
  if (-not $Tipos.ContainsKey($extensao)) {
    return ResponderJson $ctx 403 @{ erro = 'Tipo de arquivo não permitido' }
  }
  Responder $ctx 200 ([IO.File]::ReadAllBytes($arquivo)) $Tipos[$extensao]
}

function SalvarJson($ctx) {
  $pedido = $ctx.Request

  # Outro site aberto no navegador não pode mandar salvar nada aqui
  $origem = $pedido.Headers['Origin']
  if ($origem -and $origem -ne "http://localhost:$Porta") {
    return ResponderJson $ctx 403 @{ erro = 'Origem não permitida' }
  }
  # Exigir JSON obriga o navegador a pedir licença antes de um envio vindo de outro site
  if (-not ("$($pedido.ContentType)" -like 'application/json*')) {
    return ResponderJson $ctx 415 @{ erro = 'Envie o conteúdo como application/json' }
  }

  $nome = $pedido.QueryString['nome']
  if ("$nome" -cnotmatch $NomeValido) {
    return ResponderJson $ctx 400 @{ erro = 'Nome inválido. Use letras minúsculas, números e hífen, terminando em .json' }
  }

  # Lê o conteúdo com limite de tamanho
  $memoria = New-Object IO.MemoryStream
  $bloco = New-Object byte[] 65536
  while (($lidos = $pedido.InputStream.Read($bloco, 0, $bloco.Length)) -gt 0) {
    $memoria.Write($bloco, 0, $lidos)
    if ($memoria.Length -gt $LimiteBytes) {
      return ResponderJson $ctx 413 @{ erro = "Conteúdo maior que o limite de $LimiteBytes bytes" }
    }
  }
  $texto = [Text.Encoding]::UTF8.GetString($memoria.ToArray())

  if ([string]::IsNullOrWhiteSpace($texto)) {
    return ResponderJson $ctx 400 @{ erro = 'Conteúdo vazio' }
  }
  try { $null = $texto | ConvertFrom-Json } catch {
    return ResponderJson $ctx 400 @{ erro = 'O conteúdo não é um JSON válido' }
  }

  $destino = Join-Path $PastaDados $nome
  $versaoAnterior = $null
  if (Test-Path -LiteralPath $destino) {
    $carimbo = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $versaoAnterior = '{0}-{1}.json' -f [IO.Path]::GetFileNameWithoutExtension($nome), $carimbo
    Copy-Item -LiteralPath $destino -Destination (Join-Path $PastaVersoes $versaoAnterior)
  }

  # Grava primeiro num arquivo temporário e depois troca: se faltar luz no meio, o original não se perde
  $temporario = "$destino.tmp"
  [IO.File]::WriteAllText($temporario, $texto, (New-Object Text.UTF8Encoding $false))
  if (Test-Path -LiteralPath $destino) {
    # [NullString]::Value: o PowerShell transformaria $null em texto vazio, e o Replace recusa texto vazio
    [IO.File]::Replace($temporario, $destino, [NullString]::Value)
  } else {
    [IO.File]::Move($temporario, $destino)
  }

  ResponderJson $ctx 200 @{ ok = $true; arquivo = $nome; versaoAnterior = $versaoAnterior }
}

function LerJson($ctx) {
  $nome = $ctx.Request.QueryString['nome']
  if ("$nome" -cnotmatch $NomeValido) {
    return ResponderJson $ctx 400 @{ erro = 'Nome inválido' }
  }
  $arquivo = Join-Path $PastaDados $nome
  if (-not (Test-Path -LiteralPath $arquivo -PathType Leaf)) {
    return ResponderJson $ctx 404 @{ erro = 'Arquivo não encontrado' }
  }
  Responder $ctx 200 ([IO.File]::ReadAllBytes($arquivo)) 'application/json; charset=utf-8'
}

function Listar($ctx) {
  $lista = @(Get-ChildItem -LiteralPath $PastaDados -Filter '*.json' -File | Sort-Object Name | ForEach-Object {
    @{ nome = $_.Name; bytes = $_.Length; alterado = $_.LastWriteTime.ToString('s') }
  })
  ResponderJson $ctx 200 @{ arquivos = $lista }
}

function Atender($ctx) {
  $metodo = $ctx.Request.HttpMethod
  $caminho = $ctx.Request.Url.AbsolutePath

  if (-not $ctx.Request.IsLocal) {
    return ResponderJson $ctx 403 @{ erro = 'Só aceito pedidos deste computador' }
  }

  switch ("$metodo $caminho") {
    'GET /api/ping'    { return ResponderJson $ctx 200 @{ ok = $true } }
    'GET /api/listar'  { return Listar $ctx }
    'GET /api/ler'     { return LerJson $ctx }
    'POST /api/salvar' { return SalvarJson $ctx }
  }
  if ($caminho.StartsWith('/api/')) {
    return ResponderJson $ctx 404 @{ erro = 'Rota não encontrada' }
  }
  if ($metodo -ne 'GET') {
    return ResponderJson $ctx 405 @{ erro = 'Método não permitido' }
  }
  ServirArquivo $ctx
}

$ouvinte = New-Object Net.HttpListener
$ouvinte.Prefixes.Add("http://localhost:$Porta/")
try {
  $ouvinte.Start()
} catch {
  Write-Host "Não consegui abrir a porta $Porta. Ela pode estar em uso por outro programa." -ForegroundColor Red
  exit 1
}

Write-Host "Servidor no ar: http://localhost:$Porta/" -ForegroundColor Green
Write-Host "Site:  $PastaSite"
Write-Host "Dados: $PastaDados"
Write-Host 'Para parar, aperte Ctrl+C.'
if ($AbrirNavegador) { Start-Process "http://localhost:$Porta/" }

try {
  while ($ouvinte.IsListening) {
    $tarefa = $ouvinte.GetContextAsync()
    # Espera em pedaços de meio segundo para o Ctrl+C conseguir parar o servidor
    while (-not $tarefa.AsyncWaitHandle.WaitOne(500)) { }
    $ctx = $tarefa.GetAwaiter().GetResult()
    try {
      Atender $ctx
    } catch {
      $linha = '{0}  {1} {2}  {3}' -f (Get-Date -Format 's'), $ctx.Request.HttpMethod, $ctx.Request.Url.AbsolutePath, $_.Exception.Message
      Add-Content -LiteralPath $ArquivoLog -Value $linha -Encoding UTF8
      try { ResponderJson $ctx 500 @{ erro = 'Erro interno. Veja o arquivo servidor-erros.log' } } catch { }
    }
  }
} finally {
  $ouvinte.Stop()
  $ouvinte.Close()
  Write-Host 'Servidor parado.'
}
