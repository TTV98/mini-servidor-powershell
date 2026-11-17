<#
  Testes do mini servidor
  Abre o servidor numa porta de teste, com uma pasta de dados temporária, faz os pedidos e confere as respostas.
  Nada é gravado na pasta "dados" do projeto. No fim, o servidor é fechado e a pasta temporária é apagada.

  Como rodar:  powershell -NoProfile -ExecutionPolicy Bypass -File testes\testar.ps1
#>
param([int]$Porta = 8091)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent
$base = "http://localhost:$Porta"
$temp = Join-Path ([IO.Path]::GetTempPath()) ('mini-servidor-teste-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$dados = Join-Path $temp 'dados'
New-Item -ItemType Directory -Force -Path $dados | Out-Null

# Pedido normal. Devolve o código de resposta e o texto, mesmo quando é erro (4xx)
function Pedir([string]$metodo, [string]$caminho, [string]$corpo = $null, [string]$tipo = 'application/json; charset=utf-8', [hashtable]$cabecalhos = @{}) {
  $p = @{ Uri = "$base$caminho"; Method = $metodo; UseBasicParsing = $true; Headers = $cabecalhos }
  if ($null -ne $corpo -and $corpo -ne '') { $p.Body = [Text.Encoding]::UTF8.GetBytes($corpo); $p.ContentType = $tipo }
  try {
    $r = Invoke-WebRequest @p
    $texto = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
    return @{ status = [int]$r.StatusCode; texto = $texto; tipo = $r.Headers['Content-Type'] }
  } catch [Net.WebException] {
    $resposta = $_.Exception.Response
    if ($null -eq $resposta) { throw }
    $leitor = New-Object IO.StreamReader($resposta.GetResponseStream(), [Text.Encoding]::UTF8)
    return @{ status = [int]$resposta.StatusCode; texto = $leitor.ReadToEnd(); tipo = $resposta.ContentType }
  }
}

# Pedido "cru", escrito à mão, para o caminho chegar ao servidor do jeito que foi digitado (com .. e %2e)
function PedirCru([string]$caminho) {
  $cliente = New-Object Net.Sockets.TcpClient('127.0.0.1', $Porta)
  try {
    $fluxo = $cliente.GetStream()
    $bytes = [Text.Encoding]::ASCII.GetBytes("GET $caminho HTTP/1.1`r`nHost: localhost:$Porta`r`nConnection: close`r`n`r`n")
    $fluxo.Write($bytes, 0, $bytes.Length)
    $resposta = (New-Object IO.StreamReader($fluxo)).ReadToEnd()
    return @{ status = [int](($resposta -split "`r`n")[0] -split ' ')[1]; texto = $resposta }
  } finally { $cliente.Close() }
}

$resultados = New-Object System.Collections.ArrayList
function Conferir([string]$descricao, [bool]$passou, [string]$detalhe = '') {
  [void]$resultados.Add([pscustomobject]@{ Teste = $descricao; Resultado = $(if ($passou) { 'passou' } else { 'FALHOU' }); Detalhe = $detalhe })
}

# 1ª parte: a função DentroDaPasta sozinha, lida direto do servidor.ps1 (sem abrir o servidor)
$arvore = [Management.Automation.Language.Parser]::ParseFile((Join-Path $raiz 'servidor.ps1'), [ref]$null, [ref]$null)
$funcao = $arvore.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'DentroDaPasta' }, $true)
. ([scriptblock]::Create($funcao.Extent.Text))

$casos = @(
  @('index.html', 'C:\site\index.html'),
  @('css\estilo.css', 'C:\site\css\estilo.css'),
  @('..\servidor.ps1', $null),
  @('..\..\Windows\win.ini', $null),
  @('C:\Windows\win.ini', $null),
  @('..\site-falso\pagina.html', $null),
  @('nome:invalido', $null)
)
foreach ($caso in $casos) {
  $obtido = DentroDaPasta 'C:\site' $caso[0]
  Conferir "DentroDaPasta('C:\site', '$($caso[0])')" ($obtido -eq $caso[1]) "$obtido"
}

# 2ª parte: o servidor de verdade, respondendo a pedidos
$arquivosDoSiteAntes = @(Get-ChildItem -LiteralPath (Join-Path $raiz 'site') -Recurse -File).Count

$servidor = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList @(
  '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $raiz 'servidor.ps1')`"",
  '-Porta', $Porta, '-PastaDados', "`"$dados`"", '-ArquivoLog', "`"$(Join-Path $temp 'erros.log')`"", '-LimiteBytes', 2000
)

try {
  # O Windows (HTTP.sys) já recusa alguns desses endereços com 403, antes de chegarem ao script.
  # A função DentroDaPasta, testada acima, é a segunda barreira.

  # Espera o servidor subir (até 15 segundos)
  $pronto = $false
  for ($i = 0; $i -lt 30 -and -not $pronto; $i++) {
    Start-Sleep -Milliseconds 500
    try { $pronto = (Pedir 'GET' '/api/ping').status -eq 200 } catch { }
  }
  Conferir 'O servidor abre e responde ao /api/ping' $pronto
  if (-not $pronto) { throw 'O servidor não abriu.' }

  $r = Pedir 'GET' '/'
  Conferir 'A página inicial abre (200, HTML)' ($r.status -eq 200 -and $r.tipo -like 'text/html*' -and $r.texto -like '*<title>*') "$($r.status) $($r.tipo)"

  $r = Pedir 'GET' '/nao-existe.html'
  Conferir 'Arquivo que não existe dá 404' ($r.status -eq 404) "$($r.status)"

  foreach ($caminho in '/../servidor.ps1', '/%2e%2e/servidor.ps1', '/..%5cservidor.ps1', '/%2e%2e%5c%2e%2e%5cWindows/win.ini', '/C:/Windows/win.ini') {
    $r = PedirCru $caminho
    Conferir "Bloqueia a saída da pasta site: $caminho" ($r.status -ne 200 -and $r.texto -notlike '*param(*') "$($r.status)"
  }

  $corpo1 = '{"texto":"Primeira versão: ação, atenção, coração","n":1}'
  $r = Pedir 'POST' '/api/salvar?nome=teste-1.json' $corpo1
  $gravado = if (Test-Path (Join-Path $dados 'teste-1.json')) { [IO.File]::ReadAllText((Join-Path $dados 'teste-1.json'), [Text.Encoding]::UTF8) } else { '' }
  Conferir 'Salva um JSON novo, com acentos' ($r.status -eq 200 -and $gravado -eq $corpo1) "$($r.status) $($r.texto)"

  $corpo2 = '{"texto":"Segunda versão","n":2}'
  $r = Pedir 'POST' '/api/salvar?nome=teste-1.json' $corpo2
  $resposta = $r.texto | ConvertFrom-Json
  $versao = if ($resposta.versaoAnterior) { Join-Path (Join-Path $dados 'versoes-anteriores') $resposta.versaoAnterior } else { '' }
  $versaoOk = $versao -and (Test-Path $versao) -and ([IO.File]::ReadAllText($versao, [Text.Encoding]::UTF8) -eq $corpo1)
  Conferir 'Ao sobrescrever, guarda a versão anterior' ($r.status -eq 200 -and $versaoOk) "$($resposta.versaoAnterior)"

  $r = Pedir 'GET' '/api/ler?nome=teste-1.json'
  Conferir 'Lê o arquivo salvo (a versão nova)' ($r.status -eq 200 -and $r.texto -eq $corpo2) "$($r.status)"

  $r = Pedir 'GET' '/api/listar'
  Conferir 'Lista os arquivos da pasta dados' ($r.status -eq 200 -and $r.texto -like '*teste-1.json*') "$($r.status)"

  $r = Pedir 'GET' '/api/ler?nome=nao-existe.json'
  Conferir 'Ler arquivo que não existe dá 404' ($r.status -eq 404) "$($r.status)"

  foreach ($nome in '..%2Fsaiu.json', 'Maiusculo.json', 'sem-extensao', 'teste.txt', '') {
    $r = Pedir 'POST' "/api/salvar?nome=$nome" '{"a":1}'
    Conferir "Recusa nome inválido: '$nome'" ($r.status -eq 400) "$($r.status)"
  }
  Conferir 'Nada foi gravado fora da pasta dados' (-not (Test-Path (Join-Path $temp 'saiu.json')))

  $r = Pedir 'POST' '/api/salvar?nome=teste-2.json' '{isto não é json'
  Conferir 'Recusa JSON inválido (400)' ($r.status -eq 400) "$($r.status)"

  $r = Pedir 'POST' '/api/salvar?nome=teste-2.json' '{"a":1}' 'text/plain'
  Conferir 'Recusa conteúdo que não é application/json (415)' ($r.status -eq 415) "$($r.status)"

  $r = Pedir 'POST' '/api/salvar?nome=teste-2.json' '{"a":1}' 'application/json' @{ Origin = 'http://outro-site.example' }
  Conferir 'Recusa pedido vindo de outro site (403)' ($r.status -eq 403) "$($r.status)"

  $r = Pedir 'POST' '/api/salvar?nome=teste-2.json' ('{"texto":"' + ('x' * 3000) + '"}')
  Conferir 'Recusa conteúdo acima do limite (413)' ($r.status -eq 413) "$($r.status)"
  Conferir 'Os pedidos recusados não criaram arquivo' (-not (Test-Path (Join-Path $dados 'teste-2.json')))

  $r = Pedir 'DELETE' '/index.html'
  Conferir 'Método diferente de GET fora da API dá 405' ($r.status -eq 405) "$($r.status)"

  $r = Pedir 'GET' '/api/rota-inventada'
  Conferir 'Rota da API que não existe dá 404' ($r.status -eq 404) "$($r.status)"

  $arquivosDoSiteDepois = @(Get-ChildItem -LiteralPath (Join-Path $raiz 'site') -Recurse -File).Count
  Conferir 'A pasta site não mudou' ($arquivosDoSiteAntes -eq $arquivosDoSiteDepois)
} finally {
  if ($servidor -and -not $servidor.HasExited) { Stop-Process -Id $servidor.Id -Force }
  Start-Sleep -Milliseconds 300
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

$resultados | Format-Table -AutoSize -Wrap
$falhas = @($resultados | Where-Object Resultado -ne 'passou').Count
$cor = if ($falhas -eq 0) { 'Green' } else { 'Red' }
Write-Host ("{0} de {1} testes passaram." -f ($resultados.Count - $falhas), $resultados.Count) -ForegroundColor $cor
exit $falhas
