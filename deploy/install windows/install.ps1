<#
.SYNOPSIS
  Instalação simples do painel no Windows 11: verifica o Python, cria o .venv, instala as dependências e inicia o painel.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File ".\deploy\install windows\install.ps1"
  Parâmetros: -Run (inicia sem perguntar) | -NoRun (só instala)
  Pode ser executado de novo (é idempotente). Não precisa de administrador.
#>
param([switch]$Run, [switch]$NoRun)
$ErrorActionPreference = 'Stop'

$Origem = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$PyMinMinor = 10   # Python 3.10+

function Log($m)   { Write-Host "`n==> $m" -ForegroundColor Green }
function Aviso($m) { Write-Host "[aviso] $m" -ForegroundColor Yellow }
function Falha($m) { Write-Host "[erro] $m" -ForegroundColor Red; exit 1 }

if (-not (Test-Path (Join-Path $Origem 'wsgi.py')) -or -not (Test-Path (Join-Path $Origem 'requirements.txt'))) {
  Falha "Não encontrei o projeto em $Origem (wsgi.py/requirements.txt)."
}

# Retorna o comando de um Python 3.10+ (ignora o atalho da Microsoft Store, que não é um Python de verdade)
function Find-Python {
  $candidatos = @(@('py', '-3'), @('python'), @('python3'))
  foreach ($c in $candidatos) {
    $cmd = Get-Command $c[0] -ErrorAction SilentlyContinue
    if (-not $cmd -or $cmd.Source -like '*\WindowsApps\*') { continue }
    $args2 = @()
    if ($c.Count -gt 1) { $args2 = $c[1..($c.Count - 1)] }
    try {
      $v = & $cmd.Source @args2 -c 'import sys; print(sys.version_info[0]*100+sys.version_info[1])' 2>$null
      if ($LASTEXITCODE -eq 0 -and [int]$v -ge (300 + $PyMinMinor)) {
        return @{ Exe = $cmd.Source; Args = $args2 }
      }
    } catch { }
  }
  return $null
}

function Update-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

# ---------------------------------------------------------------- Python
Log "Verificando o Python (3.$PyMinMinor ou mais novo)"
$py = Find-Python
if ($py) {
  Write-Host ("Encontrado: " + (& $py.Exe @($py.Args) --version))
} else {
  Aviso "Python 3.$PyMinMinor+ não encontrado."
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    Log "Instalando o Python 3.12 com o winget"
    winget install --id Python.Python.3.12 -e --source winget --scope user --accept-package-agreements --accept-source-agreements
    Update-Path
    $py = Find-Python
    if (-not $py) { Falha "O Python foi instalado, mas ainda não está no PATH. Feche e abra o terminal e rode o script de novo." }
  } else {
    Falha "Instale o Python 3.12 em https://www.python.org/downloads/windows/ (marque 'Add python.exe to PATH') e rode o script de novo."
  }
}

# ---------------------------------------------------------------- venv + dependências
Set-Location $Origem
# .venv de macOS/Linux (pasta bin/) não funciona no Windows
if ((Test-Path '.venv') -and -not (Test-Path '.venv\Scripts\python.exe')) {
  Aviso "A pasta .venv existente não é do Windows; será recriada."
  Remove-Item -Recurse -Force '.venv'
}
Log "Criando o ambiente virtual (.venv)"
if (-not (Test-Path '.venv\Scripts\python.exe')) {
  & $py.Exe @($py.Args) -m venv .venv
  if ($LASTEXITCODE -ne 0) { Falha "Falha ao criar o .venv." }
}
$venvPy = Join-Path $Origem '.venv\Scripts\python.exe'
Log "Instalando as dependências (requirements.txt)"
# gunicorn não roda no Windows; usa-se o waitress no lugar
$req = Get-Content requirements.txt | Where-Object { $_ -notmatch '^\s*gunicorn' }
$tmpReq = Join-Path $env:TEMP 'plenario-aberto-requirements-win.txt'
$req | Set-Content $tmpReq
& $venvPy -m pip install --quiet --upgrade pip
if ($LASTEXITCODE -ne 0) { Falha "Falha ao atualizar o pip." }
& $venvPy -m pip install --quiet -r $tmpReq waitress
if ($LASTEXITCODE -ne 0) { Falha "Falha ao instalar as dependências." }
Remove-Item $tmpReq -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force 'cache' | Out-Null

# ---------------------------------------------------------------- iniciar
Write-Host @"

Instalação concluída.
  Para iniciar depois (PowerShell):
      cd "$Origem"
      .venv\Scripts\Activate.ps1
      flask --app wsgi run --debug
  Abra: http://127.0.0.1:5000   (parar: Ctrl+C)
  Erro "a execução de scripts foi desabilitada"? Use: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
  Cache: $Origem\cache (o 1º acesso a cada ano baixa 4-7 MB)
"@

$iniciar = $Run
if (-not $Run -and -not $NoRun) {
  $r = Read-Host "Iniciar o painel agora? [S/n]"
  $iniciar = -not ($r -match '^[nN]')
}
if ($iniciar) {
  Log "Iniciando em http://127.0.0.1:5000 (Ctrl+C para parar)"
  Start-Job { Start-Sleep 3; Start-Process 'http://127.0.0.1:5000' } | Out-Null
  & $venvPy -m flask --app wsgi run
}
