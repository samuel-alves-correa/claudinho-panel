# Cenas do Claudinho: vinhetas curtas por cima das animacoes de estado, inspiradas no app mobile do Claude
# (tela vazia do Code: "build a feature" -> plugue, "fix a bug" -> inseto, "explain your code" -> quadro; puxar a tela -> pendurado).
#
# Carregado por claudinho-widget.ps1 com:  . (Join-Path $PSScriptRoot 'cenas.ps1')
# Salve em UTF-8 COM BOM (PowerShell 5.1 le .ps1 sem BOM como ANSI).
#
# Fluxo por quadro (no Paint, antes de Draw-Mascot):
#   Cena-Gatilhos $v $t   -> decide se comeca/para alguma cena (estado do mod, arrasto, rodizio no ocioso)
#   Cena-Passo $t         -> calcula $script:cq (quadro-chave atual) ou $null
#   Draw-Mascot           -> se $script:cq existir, usa a pose dele no lugar da animacao do estado
#                            e chama Cena-Props (camadas 'atras' e 'frente') para desenhar inseto, quadro e plugue
#
# Coordenadas: "pixels do bichinho" (a funcao U), x = 0 no centro do anel, y = 0 no chao, negativo = para cima.
# O corpo de frente ocupa x -8..8 e y -16..0; o anel tem raio ~17 nessas unidades, com o centro em y = -8.
#
# Depuracao: CW_CENAS=0 desliga todas as cenas; CW_CENA=inseto|quadro|plugue|aguardando|chefe|pescaria|cochilo repete essa cena em laco (bom para gravar GIF).
#   Tambem: terminal|costura|lampada|lupa|fumaca|placa (cenas do estado: entra, 3 lacos e sai) e bandeira|borboleta.

# ---------- configuracao ----------
$script:CN_ON = ($env:CW_CENAS -ne '0')
$script:CN_DEBUG = [string]$env:CW_CENA
$CN_OCIOSO_MIN = 40.0      # s parado ate a 1a cena do rodizio (e intervalo minimo entre cenas)
$CN_OCIOSO_VAR = 40.0      # + ate isso de sorteio
$CN_FALHA_JANELA = 8000.0  # ms: falha de ferramenta mais velha que isso nao vira inseto (evita tocar ao abrir o widget)
$CN_RODIZIO = @('plugue', 'inseto', 'quadro', 'borboleta')

# cores dos adereços (contraste >= 3:1 sobre o preto do notch)
$CN_BUG = '#e5484d'; $CN_BUGD = '#7a1f22'; $CN_PATA = '#8a8a8a'
$CN_QFACE = '#bfe9d9'; $CN_QBORDA = '#9aa0a8'; $CN_QPE = '#6b7078'; $CN_TINTA = '#1b1b1b'; $CN_PINCEL = '#8b7cf6'
$CN_PLUG = '#9aa0a8'; $CN_PLUGD = '#6b7078'; $CN_FAISCA = '#f5c542'
$CN_AREIA = '#e8c97a'; $CN_VIDRO = '#9aa0a8'   # ampulheta da cena aguardando (as bolinhas usam $SUBC do widget)
$CN_CAIXA = '#c8a26a'; $CN_CAIXAD = '#9a7746'   # caixas dos mini-Claudinhos (chefe)
$CN_PRANCHA = '#a0714f'; $CN_PAPEL = '#faf9f5'; $CN_OK = '#5fd38d'; $CN_FUMACA = '#a09d96'
$CN_Z = '#a09d96'; $CN_ZD = '#6b6b66'; $CN_ALERTA = '#f5c542'
$CN_VARA = '#8b6a4a'; $CN_LINHA = '#c8c6bf'; $CN_LINHAD = '#6b6b66'; $CN_AGUA = '#4a90c8'; $CN_AGUAD = '#2f6a9a'; $CN_BOIA = '#ff5f56'
# estado Agentes: comeca no chefe de obra ou na pescaria (alterna a cada vez que subagentes comecam);
# depois de $CN_AG_SONO s com subagentes rodando ele cansa e vai para o cochilo
$CN_AG_INICIO = @('chefe', 'pescaria')
$CN_AG_SONO = 25.0
$CN_CO_VEL = 1.6   # rad/s dos minis correndo em volta no cochilo (~4 s por volta)
# cenas do estado (em laco enquanto o estado pedir): s que o estado precisa durar antes de a cena comecar
# (evita piscar nas trocas rapidas Codando <-> Pensando entre uma ferramenta e outra)
$CN_EST_ESPERA = @{ terminal = 0.6; costura = 0.6; lampada = 1.5; lupa = 0.6; fumaca = 0.9; placa = 0.3 }
$CN_OKD = '#3a9a63'     # verde escuro (bandeira)
$CN_ASA = '#8ec5ff'; $CN_ASAD = '#5a9bd8'   # asas da borboleta (corpo $CN_VARA)
$CN_LENTE = '#9fd0f5'   # vidro da lupa (aro $CN_AGULHA, cabo $CN_VARA, pegadas $CN_PATA)
$CN_LAMPF = '#8a7a3a'; $CN_LAMPM = '#c9ad4a'; $CN_LAMPA = '#ffe066'   # lampada fraca, piscando e acesa
$CN_AGULHA = '#c8c6bf'   # agulha da costura (a linha usa $CN_PINCEL)
$CN_TELA = '#0d1117'   # fundo do terminal (a moldura cinza separa do preto do anel)

# ---------- estado ----------
$script:cena = $null        # @{ id; prio; fase = 'entra'|'laco'|'sai'; tf = inicio da fase; t0 = inicio da cena; voltas; fixo; fam }
$script:cq = $null          # quadro atual: @{ id; fase; a = tempo na fase; tc = tempo na cena; k = quadro-chave }
$script:cnFalhaVista = -1.0 # failAt ja tratado (-1 = ainda nao leu: o 1o valor so e registrado, nao toca)
$script:cnProxOcioso = 0.0  # quando tocar a proxima cena do rodizio
$script:cnUltima = ''       # ultima cena do rodizio (nao repete seguida)
$script:cnAgN = 0            # bolinhas da cena aguardando (1..3): ultimo agentsN > 0 visto (a saida ainda precisa dele)
$script:cnAgPrev = 0         # agentsN do quadro anterior (para perceber um subagente terminando)
$script:cnAgDesde = 0.0      # quando os subagentes comecaram (decide chefe -> cochilo)
$script:cnSaiu = -99.0       # quando um subagente terminou por ultimo ($t)
$script:cnSaiuIdx = 0; $script:cnSaiuN = 1   # qual mini-Claudinho saiu e quantos havia (para achar onde ele estava)
$script:cnFeitos = 0         # subagentes terminados desde que comecaram (checks na prancheta / peixes no pier, max 3)
$script:cnAgVez = -1         # indice em $CN_AG_INICIO da cena de abertura atual
$script:cnAgIni = 'chefe'    # cena de abertura do estado Agentes desta vez
$script:cnFam = ''          # familia de modo vista no quadro anterior
$script:cnModo = ''         # modo visto no quadro anterior
$script:cnEstQuer = ''      # cena do estado pedida agora ('' = nenhuma)
$script:cnEstDesde = 0.0    # desde quando ela e pedida
$script:cnLupaOx = 0.0      # onde a lupa parou (a saida volta dali para o centro)
$script:cnDoneVez = 0       # Terminou alterna plugue / bandeira
$script:cnRnd = New-Object System.Random
# arrasto (preenchido pelos eventos de mouse do widget)
$script:arrY = 0.0; $script:arrT = 0.0; $script:arrVel = 0.0

# ---------- quadros-chave ----------
# Cada quadro vale ATE o instante `ate` (s, relativo ao inicio da fase). Campos omitidos usam o padrao de CN-Kf.
# pose: front | turn | squash (front agachado) | hang (front pendurado); lift: pernas mais longas (+) ou curtas (-)
# eyes: open | closed | happy | squint | x; eyX/eyY: posicao dos olhos; armL/armR: braco sobe (negativo)
# reachL: braco esquerdo esticado na horizontal (unidades); ox/oy: deslocamento do corpo (unidades); sy: escala vertical
# wf: frequencia do passo das pernas (0 = parado); marker: pincel roxo na mao direita; tilt: cabeca inclinada
function CN-Kf([hashtable]$o) {
  $k = @{ ate = 0.0; pose = 'front'; eyes = 'open'; eyX = 0.0; eyY = -14.0; armL = 0.0; armR = 0.0; reachL = 0.0
          ox = 0.0; oy = 0.0; sy = 1.0; wf = 0.0; lift = 0.0; marker = $false; tilt = $false }
  foreach ($key in $o.Keys) { $k[$key] = $o[$key] }
  $k
}
function CN-Seq([object[]]$lista) { , @($lista | ForEach-Object { CN-Kf $_ }) }

# Tempos medidos na gravacao do app (60 fps, amostras a cada 0,2 s): [Comprovado] a ordem das poses;
# [Hipotese] os tempos exatos (+-0,2 s) e a leitura de alguns quadros (ver docs/cenas.md).
$script:CENAS = @{
  # fix a bug (video 9,2 s -> 11,8 s): inseto entra pela esquerda, bichinho olha, agacha, da um tapa, inseto foge
  'inseto' = @{ prio = 1; entra = (CN-Seq @(
      @{ ate = 0.5 }
      @{ ate = 0.9; eyX = -1.0 }
      @{ ate = 1.4; pose = 'squash'; lift = -2.0; eyX = -1.0; eyY = -13.0 }
      @{ ate = 1.8; reachL = 3.0; eyX = -1.0; armR = -1.0 }
      @{ ate = 2.3; eyX = -1.0 }
      @{ ate = 2.6 }
    )) }
  # explain your code (video 12,4 s -> 14,6 s): da um passo para a esquerda, o quadro gira para dentro,
  # escreve com o pincel roxo; na saida o quadro gira para fora e ele volta ao centro
  'quadro' = @{ prio = 2
    entra = (CN-Seq @(
      @{ ate = 0.25; ox = -2.0; wf = 8.0 }
      @{ ate = 0.5; ox = -4.0; marker = $true; armR = -2.0 }
    ))
    laco = (CN-Seq @(
      @{ ate = 0.25; ox = -4.0; marker = $true; eyX = 0.6 }
      @{ ate = 0.5; ox = -4.0; marker = $true; eyX = 0.6; armR = -1.0 }
    ))
    sai = (CN-Seq @(
      @{ ate = 0.3; ox = -4.0; marker = $true; armR = -3.0 }
      @{ ate = 0.6; ox = -2.0; wf = 8.0 }
    )) }
  # build a feature (video 7,8 s -> 9,2 s): um plugue aparece ao lado, ele olha, o plugue encaixa (faisca)
  # e ele fica contente (olhos apertados, cabeca inclinada)
  'plugue' = @{ prio = 1; entra = (CN-Seq @(
      @{ ate = 0.3 }
      @{ ate = 0.7; eyX = -1.0 }
      @{ ate = 1.1; eyes = 'squint'; tilt = $true }
      @{ ate = 1.4 }
    )) }
  # subagentes rodando (inspirada no app): ele espera batendo o pe devagar e olhando de lado a lado, com uma bolinha rosa
  # por subagente (max 3) orbitando; no laco o numero de bolinhas acompanha agentsN; ao acabar elas voam para ele e ele pula
  'aguardando' = @{ prio = 1.5
    entra = (CN-Seq @( @{ ate = 0.3; wf = 3.0 } ))
    laco = (CN-Seq @(
      @{ ate = 0.6; wf = 3.0; eyX = -1.0 }
      @{ ate = 1.2; wf = 3.0 }
      @{ ate = 1.8; wf = 3.0; eyX = 1.0; tilt = $true }
      @{ ate = 2.4; wf = 3.0 }
    ))
    sai = (CN-Seq @(
      @{ ate = 0.2; sy = 0.95 }
      @{ ate = 0.35; oy = -3.0; armL = -2.0; armR = -2.0 }
      @{ ate = 0.5 }
    )) }
  # 1) chefe de obra: de prancheta na mao, acompanha com os olhos os mini-Claudinhos (um por subagente, max 3) que
  # carregam caixas pelo chao; quando um subagente termina, o mini dele acena e some numa fumacinha e a prancheta ganha um check;
  # quando todos terminam ele pula (quadro dinamico em CN-ChefeKf)
  'chefe' = @{ prio = 1.5
    entra = (CN-Seq @(
      @{ ate = 0.2; ox = -2.5; wf = 8.0 }
      @{ ate = 0.4; ox = -5.0; eyY = -13.0 }
    ))
    laco = (CN-Seq @( @{ ate = 8.0; ox = -5.0; eyY = -13.0 } ))
    sai = (CN-Seq @(
      @{ ate = 0.3; ox = -5.0; eyes = 'happy' }
      @{ ate = 0.55; ox = -5.0; oy = -3.0; armL = -2.0; armR = -2.0; eyes = 'happy' }
      @{ ate = 0.8; ox = -2.5; wf = 8.0 }
    )) }
  # 2) pescaria: sentado na ponta do pier, segura uma vara com uma linha por subagente (max 3) descendo para a agua;
  # as boias balancam e de vez em quando afundam; quando um subagente termina ele puxa a linha e sai um peixinho rosa,
  # que voa por cima dele e cai na pilha do pier; quando todos terminam, pesca o ultimo e pula (quadro dinamico em CN-PescaKf)
  'pescaria' = @{ prio = 1.5
    entra = (CN-Seq @(
      @{ ate = 0.25; ox = -2.0; wf = 8.0 }
      @{ ate = 0.5; ox = -4.0; lift = -2.0; eyX = 1.0; eyY = -13.0; armR = -1.0 }
    ))
    laco = (CN-Seq @( @{ ate = 8.0; ox = -4.0; lift = -2.0; eyX = 1.0; eyY = -13.0; armR = -1.0 } ))
    sai = (CN-Seq @(
      @{ ate = 0.3; ox = -4.0; lift = -2.0; armR = -3.0; eyX = 1.0; oy = -0.5 }
      @{ ate = 1.1; ox = -4.0; lift = -2.0; armR = -2.0; eyes = 'happy' }
      @{ ate = 1.35; ox = -4.0; oy = -3.0; armL = -2.0; armR = -2.0; eyes = 'happy' }
      @{ ate = 1.6; ox = -4.0 }
    )) }
  # 7) cochilo vigiado: sentado, cochila com "z" subindo mas com um olho aberto seguindo as bolinhas; quando um subagente
  # termina acorda num pulo com um "!" e volta a cochilar (quadro dinamico em CN-CochiloKf)
  'cochilo' = @{ prio = 1.5
    entra = (CN-Seq @(
      @{ ate = 0.3; lift = -1.0; eyes = 'squint' }
      @{ ate = 0.8; lift = -2.0; eyes = 'closed' }
    ))
    laco = (CN-Seq @( @{ ate = 8.0; lift = -2.0; eyes = 'vigia' } ))
    sai = (CN-Seq @(
      @{ ate = 0.12; lift = -2.5 }
      @{ ate = 0.4; oy = -4.0; armL = -3.0; armR = -3.0; eyY = -15.0 }
      @{ ate = 1.0 }
    )) }
  # Terminou (alterna com o plugue): anda para a esquerda com uma bandeirinha verde, finca no chao agachando
  # (poeira) e comemora; a bandeira tremula e afunda no fim
  'bandeira' = @{ prio = 1; entra = (CN-Seq @(
      @{ ate = 0.2; ox = -1.5; wf = 8.0; eyX = 1.0 }
      @{ ate = 0.35; ox = -3.0; eyX = 1.0 }
      @{ ate = 0.55; ox = -3.0; pose = 'squash'; lift = -1.5; eyX = 1.0; eyY = -13.0 }
      @{ ate = 1.8; ox = -3.0; eyes = 'happy'; armL = -2.0 }
      @{ ate = 2.2; ox = -3.0; eyes = 'happy' }
    )) }
  # Ocioso (rodizio): uma borboleta entra pela direita, pousa na cabeca dele (ele fica vesgo olhando para ela) e vai embora
  # pela esquerda; ele acompanha e sorri (posicao da borboleta em CN-Borboleta)
  'borboleta' = @{ prio = 1; entra = (CN-Seq @(
      @{ ate = 0.5; eyX = 1.0; eyY = -14.5 }
      @{ ate = 1.1; eyX = 0.5; eyY = -15.5 }
      @{ ate = 1.6; eyY = -15.5 }
      @{ ate = 3.8; eyes = 'vesgo' }
      @{ ate = 4.4; eyX = -1.0; eyY = -15.0 }
      @{ ate = 5.0; eyes = 'happy' }
    )) }
  # ---- cenas do estado (estado = $true): prio 0.5, qualquer outra cena passa por cima; semRm = nao toca com reducao de movimento
  # Codando com Bash: terminal a esquerda, ele digita e le as linhas verdes que sobem; na saida aparece um "$" novo
  'terminal' = @{ prio = 0.5; estado = $true; semRm = $true
    entra = (CN-Seq @(
      @{ ate = 0.2; ox = 1.5; wf = 8.0 }
      @{ ate = 0.4; ox = 3.0; eyX = -1.0; eyY = -13.0 }
    ))
    laco = (CN-Seq @(
      @{ ate = 0.15; ox = 3.0; eyX = -1.0; eyY = -13.0; armL = -1.0 }
      @{ ate = 0.3; ox = 3.0; eyX = -1.0; eyY = -13.0 }
      @{ ate = 0.45; ox = 3.0; eyX = -1.0; eyY = -13.0; armL = -1.0 }
      @{ ate = 1.4; ox = 3.0; eyX = -1.0; eyY = -12.5 }
    ))
    sai = (CN-Seq @(
      @{ ate = 0.5; ox = 3.0; eyX = -1.0; eyes = 'happy' }
      @{ ate = 0.8; ox = 1.5; wf = 8.0 }
    )) }
  # Codando com Edit: tira um pedaco de uma faixa de "codigo" (traco vermelho) e costura um novo (verde) no lugar com
  # agulha e linha (quadro dinamico em CN-CosturaKf)
  'costura' = @{ prio = 0.5; estado = $true; semRm = $true
    entra = (CN-Seq @(
      @{ ate = 0.2; ox = -2.0; wf = 8.0 }
      @{ ate = 0.4; ox = -4.0; eyX = 1.0; eyY = -12.5 }
    ))
    laco = (CN-Seq @( @{ ate = 3.2; ox = -4.0; eyX = 1.0; eyY = -12.5 } ))
    sai = (CN-Seq @(
      @{ ate = 0.4; ox = -4.0; eyX = 1.0; eyes = 'happy' }
      @{ ate = 0.7; ox = -2.0; wf = 8.0 }
    )) }
  # Pensando: lampada fraca piscando sobre a cabeca, ele olha para cima; ao sair do Pensando ela acende forte e ele pula
  'lampada' = @{ prio = 0.5; estado = $true; semRm = $true
    entra = (CN-Seq @( @{ ate = 0.4; eyY = -15.5 } ))
    laco = (CN-Seq @(
      @{ ate = 1.5; eyY = -15.5; eyX = -0.5 }
      @{ ate = 2.2; eyY = -15.5; eyX = 0.5 }
      @{ ate = 3.0; eyY = -15.5; eyX = 0.5; tilt = $true }
    ))
    sai = (CN-Seq @(
      @{ ate = 0.15; eyY = -15.5 }
      @{ ate = 0.35; oy = -1.5; eyes = 'happy'; armR = -2.0 }
      @{ ate = 0.7; eyes = 'happy' }
    )) }
  # Lendo com Read/Glob/LS: anda de um lado para o outro com a lupa perto do chao, seguindo pegadas (quadro dinamico em CN-LupaKf)
  'lupa' = @{ prio = 0.5; estado = $true; semRm = $true
    entra = (CN-Seq @(
      @{ ate = 0.2; ox = -1.5; wf = 6.0 }
      @{ ate = 0.4; ox = -3.0; wf = 6.0; eyX = 1.0; eyY = -12.5 }
    ))
    laco = (CN-Seq @( @{ ate = 6.0; wf = 6.0; eyY = -12.5 } ))
    sai = (CN-Seq @( @{ ate = 0.4; wf = 6.0 } )) }
  # Erro: o notebook no chao solta fumaca escura; ele abana com a mao esquerda, descansa olhando e abana de novo
  'fumaca' = @{ prio = 0.5; estado = $true; semRm = $true
    entra = (CN-Seq @(
      @{ ate = 0.2; ox = 3.0; eyes = 'x' }
      @{ ate = 0.5; ox = 3.0; oy = -1.5; eyes = 'x'; armL = -2.0; armR = -2.0 }
    ))
    laco = (CN-Seq @(
      @{ ate = 0.15; ox = 3.0; eyes = 'x'; eyX = -1.0; armL = -3.0 }
      @{ ate = 0.3; ox = 3.0; eyes = 'x'; eyX = -1.0 }
      @{ ate = 0.45; ox = 3.0; eyes = 'x'; eyX = -1.0; armL = -3.0 }
      @{ ate = 0.6; ox = 3.0; eyes = 'x'; eyX = -1.0 }
      @{ ate = 0.75; ox = 3.0; eyes = 'x'; eyX = -1.0; armL = -3.0 }
      @{ ate = 0.9; ox = 3.0; eyes = 'x'; eyX = -1.0 }
      @{ ate = 3.0; ox = 3.0; eyes = 'x'; eyX = -1.0; eyY = -13.0; tilt = $true }
    )) }
  # Aguardando permissao: levanta uma placa "OK?" na mao direita e balanca de leve (informa: com reducao de movimento fica parada)
  'placa' = @{ prio = 0.5; estado = $true
    entra = (CN-Seq @(
      @{ ate = 0.2; ox = -2.5; wf = 8.0 }
      @{ ate = 0.4; ox = -4.5; armR = -1.0 }
    ))
    laco = (CN-Seq @(
      @{ ate = 1.2; ox = -4.5; armR = -1.0; eyX = 0.5 }
      @{ ate = 2.4; ox = -4.5; armR = -1.0; eyX = 0.5; tilt = $true }
    ))
    sai = (CN-Seq @(
      @{ ate = 0.25; ox = -4.5; armR = -1.0 }
      @{ ate = 0.5; ox = -2.5; wf = 8.0 }
    )) }
  # puxar a tela (video 15 s -> 19 s): enquanto voce arrasta o widget ele fica pendurado (quadro calculado em CN-Pendurado)
  'pendurado' = @{ prio = 3; laco = (CN-Seq @( @{ ate = 1.0; pose = 'hang' } )) }
  # ao soltar: agacha no impacto, quica e volta
  'aterrissa' = @{ prio = 3; entra = (CN-Seq @(
      @{ ate = 0.12; pose = 'squash'; lift = -2.0; eyes = 'closed' }
      @{ ate = 0.3; oy = -3.0; armL = -2.0; armR = -2.0 }
      @{ ate = 0.42; pose = 'squash'; lift = -1.0 }
      @{ ate = 0.6 }
    )) }
}

# ---------- motor ----------
function CN-EhAg([string]$id) { $id -eq 'aguardando' -or $id -eq 'chefe' -or $id -eq 'pescaria' -or $id -eq 'cochilo' }
function CN-EhEst([string]$id) { $d = $script:CENAS[$id]; [bool]($d -and $d.estado) }
# cena do estado que o modo atual pede ('' = nenhuma)
function CN-Estado($v, [string]$mode, [string]$fam) {
  $tool = [string]$v.tool
  if ($mode -eq 'thinking') { return 'lampada' }
  if ($mode -eq 'error') { return 'fumaca' }
  if ($fam -eq 'alerta' -and $v.askKind -eq 'permissao') { return 'placa' }
  if ($mode -eq 'reading' -and ($tool -eq 'Read' -or $tool -eq 'Glob' -or $tool -eq 'LS')) { return 'lupa' }
  if ($mode -eq 'coding' -and $tool -eq 'Bash') { return 'terminal' }
  if ($mode -eq 'coding' -and ($tool -eq 'Edit' -or $tool -eq 'MultiEdit' -or $tool -eq 'NotebookEdit')) { return 'costura' }
  ''
}
function CN-Fam([string]$mode, [bool]$loud) {
  if ($mode -eq 'thinking' -or $mode -eq 'coding' -or $mode -eq 'reading' -or $mode -eq 'agents') { return 'ocupado' }
  if ($mode -eq 'waiting' -and $loud) { return 'alerta' }
  if ($mode -eq 'error') { return 'erro' }
  if ($mode -eq 'offline' -or $mode -eq '') { return 'off' }
  'calmo'   # idle, done, waiting sem alerta
}

# Comeca uma cena. Nao interrompe outra de prioridade maior (ou igual, se ainda nao acabou) a menos que -Forcar.
# -Laco: fica na fase 'laco' ate Cena-Parar. -Voltas n: repete o laco n vezes e sai sozinha.
function Cena-Tocar([string]$id, [double]$t, [switch]$Forcar, [switch]$Laco, [int]$Voltas = 0) {
  if (-not $script:CN_ON) { return }
  $def = $script:CENAS[$id]; if (-not $def) { return }
  $c = $script:cena
  if ($c -and -not $Forcar -and $c.prio -ge $def.prio) { return }
  $fixo = [bool]$script:rm
  if ($fixo -and $def.semRm) { return }   # cena do estado que so enfeita: com reducao de movimento fica a animacao do estado
  # reducao de movimento: so a cena que informa algo (quadro em laco = pergunta pendente) aparece, e parada
  if ($fixo -and -not ($Laco -and $def.laco)) { $script:cena = $null; return }
  $fase = $(if ($def.entra -and -not $fixo) { 'entra' } elseif ($def.laco) { 'laco' } else { 'sai' })
  $script:cena = @{ id = $id; prio = [double]$def.prio; fase = $fase; tf = $t; t0 = $t; laco = [bool]$Laco; voltas = $Voltas; fixo = $fixo }
}

# Pede para a cena sair (toca a fase 'sai' se houver; senao encerra na hora)
function Cena-Parar([double]$t, [switch]$Ja) {
  $c = $script:cena; if (-not $c) { return }
  $def = $script:CENAS[$c.id]
  if ($Ja -or $c.fixo -or -not $def.sai) { Cena-Fim $t; return }
  if ($c.fase -ne 'sai') { $c.fase = 'sai'; $c.tf = $t }
}

function Cena-Fim([double]$t) {
  $script:cena = $null; $script:cq = $null
  # depois de qualquer cena, o rodizio do ocioso espera pelo menos o intervalo minimo
  if ($script:cnProxOcioso -gt 0) { $script:cnProxOcioso = [math]::Max($script:cnProxOcioso, $t + $CN_OCIOSO_MIN) }
  # se a cena interrompeu o Codando, volta direto para o notebook (sem repetir a introducao de 1,75 s)
  if ($script:lastMode -eq 'coding') { $script:introSkip = $true }
  $script:inval = $true
}

function Cena-Ativa { [bool]$script:cena }

# Decide o que tocar neste quadro. Chamar 1x por quadro, antes de Cena-Passo.
function Cena-Gatilhos($v, [double]$t) {
  if (-not $script:CN_ON) { return }
  $mode = [string]$v.mode; $fam = CN-Fam $mode ([bool]$v.loud)
  $mudouFam = ($fam -ne $script:cnFam); $mudouModo = ($mode -ne $script:cnModo)
  $script:cnFam = $fam; $script:cnModo = $mode
  $c = $script:cena
  # subagentes ativos e a conversa principal nao esta em alerta nem em erro (a ferramenta Agent deixa o principal em
  # Codando/Pensando ate o subagente acabar; em segundo plano ele pode estar em Sua vez/Ocioso)
  $nAg = 0; try { $nAg = [int]$v.agentsN } catch { }
  $querAg = ($nAg -gt 0 -and $fam -ne 'alerta' -and $fam -ne 'erro')
  if ($nAg -gt 0) { $script:cnAgN = [math]::Min(3, $nAg) }
  if ($nAg -gt 0 -and $script:cnAgPrev -le 0) {   # subagentes comecaram: zera a contagem e alterna a cena de abertura
    $script:cnAgDesde = $t; $script:cnFeitos = 0
    $script:cnAgVez = ($script:cnAgVez + 1) % $CN_AG_INICIO.Count; $script:cnAgIni = $CN_AG_INICIO[$script:cnAgVez]
  }
  if ($nAg -lt $script:cnAgPrev) {   # um (ou mais) subagente terminou
    $script:cnSaiu = $t; $script:cnSaiuIdx = $nAg; $script:cnSaiuN = [math]::Min(3, $script:cnAgPrev)
    $script:cnFeitos = [math]::Min(3, $script:cnFeitos + ($script:cnAgPrev - $nAg))
  }
  $script:cnAgPrev = $nAg

  if ($fam -eq 'off') { if ($c) { Cena-Fim $t }; return }

  # 0) depuracao: uma cena em laco
  if ($script:CN_DEBUG -and $script:CENAS[$script:CN_DEBUG]) {
    if (-not $c) {
      if ($script:CN_DEBUG -eq 'quadro') { Cena-Tocar 'quadro' $t -Voltas 4 }
      elseif (CN-EhAg $script:CN_DEBUG) { if ($script:cnAgN -lt 1) { $script:cnAgN = 3 }; Cena-Tocar $script:CN_DEBUG $t -Laco }
      elseif (CN-EhEst $script:CN_DEBUG) { Cena-Tocar $script:CN_DEBUG $t -Voltas 3 }   # entra, 3 lacos e sai
      else { Cena-Tocar $script:CN_DEBUG $t }
    }
    return
  }

  # 1) arrasto do widget: pendurado enquanto arrasta, aterrissa ao soltar
  if ($script:down -and $script:moved) {
    if (-not $c -or $c.id -ne 'pendurado') { Cena-Tocar 'pendurado' $t -Forcar -Laco }
    return
  }
  if ($c -and $c.id -eq 'pendurado') { Cena-Tocar 'aterrissa' $t -Forcar; return }
  if ($c -and $c.id -eq 'aterrissa') { return }

  # 2) pergunta ou plano esperando voce: quadro em laco ate responder
  $querQuadro = ($fam -eq 'alerta' -and ($v.askKind -eq 'pergunta' -or $v.askKind -eq 'plano'))
  if ($querQuadro) {
    if (-not $c -or $c.id -ne 'quadro' -or -not $c.laco -or $c.fase -eq 'sai') { Cena-Tocar 'quadro' $t -Forcar -Laco }
    return
  }
  if ($c -and $c.id -eq 'quadro' -and $c.laco) { Cena-Parar $t; return }

  # 3) a familia de modo mudou (ex.: chegou um alerta, deu erro, voce mandou um prompt): a cena em curso sai
  #    (a aguardando sobrevive a ocupado <-> calmo enquanto houver subagentes)
  if ($c -and $mudouFam -and $c.id -ne 'aterrissa' -and -not ((CN-EhAg $c.id) -and $querAg)) {
    # o quadro sai girando; as cenas de subagente tocam a saida (pulo) quando eles acabam e ele fica parado; o resto some
    # (a lampada tambem sai acendendo: ela marca o fim do Pensando)
    if ($c.id -eq 'quadro' -or $c.id -eq 'lampada' -or $c.id -eq 'placa' -or ((CN-EhAg $c.id) -and $fam -eq 'calmo')) { Cena-Parar $t } else { Cena-Fim $t; $c = $null }
  }

  # 4) ferramenta falhou (failAt novo): inseto
  $fa = 0.0; try { $fa = [double]$v.failAt } catch { }
  if ($script:cnFalhaVista -lt 0) { $script:cnFalhaVista = $fa }
  elseif ($fa -gt $script:cnFalhaVista) {
    $script:cnFalhaVista = $fa
    $nowMs = [double][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    if (($nowMs - $fa) -lt $CN_FALHA_JANELA -and ($fam -eq 'ocupado' -or $fam -eq 'calmo')) { Cena-Tocar 'inseto' $t; return }
  }

  # 5) turno terminou: plugue ("feature pronta")
  if ($mudouModo -and $mode -eq 'done') {
    $script:cnDoneVez = 1 - $script:cnDoneVez
    Cena-Tocar $(if ($script:cnDoneVez -eq 1) { 'bandeira' } else { 'plugue' }) $t; return
  }

  # 5b) subagentes ativos: chefe ou pescaria, e depois de $CN_AG_SONO s, cochilo (so comeca sem outra cena: inseto/plugue terminam antes e ela volta)
  if ($c -and (CN-EhAg $c.id) -and $c.fase -ne 'sai' -and -not $querAg) { Cena-Parar $t; return }
  if ($querAg) {
    $sono = (($t - $script:cnAgDesde) -ge $CN_AG_SONO)
    if (-not $c -or (CN-EhEst $c.id)) { Cena-Tocar $(if ($sono) { 'cochilo' } else { $script:cnAgIni }) $t -Laco }
    elseif (($c.id -eq 'chefe' -or $c.id -eq 'pescaria') -and $sono -and $c.fase -eq 'laco' -and ($t - $script:cnSaiu) -gt 1.0) { Cena-Fim $t; Cena-Tocar 'cochilo' $t -Laco }
    $script:cnProxOcioso = 0.0; return   # o rodizio do ocioso nao toca enquanto houver subagentes
  }

  # 5c) cena do estado: em laco enquanto o modo (e a ferramenta) pedirem; troca = a atual sai e a nova espera o estado assentar
  $est = CN-Estado $v $mode $fam
  if ($est -ne $script:cnEstQuer) { $script:cnEstQuer = $est; $script:cnEstDesde = $t }
  if ($c -and (CN-EhEst $c.id) -and $c.id -ne $est) { if ($c.fase -ne 'sai') { Cena-Parar $t }; return }
  if ($est) {
    if (-not $c -and ($t - $script:cnEstDesde) -ge $CN_EST_ESPERA[$est]) { Cena-Tocar $est $t -Laco }
    return
  }

  # 6) rodizio no ocioso / sua vez (como a tela vazia do app, mas espacado)
  if ($fam -ne 'calmo' -or $script:rm) { $script:cnProxOcioso = 0.0; return }
  if ($mudouFam -or $script:cnProxOcioso -le 0) { $script:cnProxOcioso = $t + $CN_OCIOSO_MIN + $script:cnRnd.NextDouble() * $CN_OCIOSO_VAR; return }
  if (-not $c -and $t -ge $script:cnProxOcioso) {
    $op = @($CN_RODIZIO | Where-Object { $_ -ne $script:cnUltima })
    $id = $op[$script:cnRnd.Next($op.Count)]
    $script:cnUltima = $id
    if ($id -eq 'quadro') { Cena-Tocar 'quadro' $t -Voltas 4 } else { Cena-Tocar $id $t }
    $script:cnProxOcioso = $t + $CN_OCIOSO_MIN + $script:cnRnd.NextDouble() * $CN_OCIOSO_VAR
  }
}

# Avanca a cena e preenche $script:cq. Chamar 1x por quadro, depois de Cena-Gatilhos e antes de Draw-Mascot.
function Cena-Passo([double]$t) {
  $c = $script:cena
  if (-not $c) { $script:cq = $null; return }
  $def = $script:CENAS[$c.id]
  for ($guard = 0; $guard -lt 4; $guard++) {
    $seq = $def[$c.fase]; $a = $t - $c.tf
    if ($c.fase -eq 'laco') {
      $per = $seq[-1].ate
      if ($c.fixo) { $script:cq = @{ id = $c.id; fase = 'laco'; a = 0.0; tc = $t - $c.t0; k = $seq[0]; fixo = $true }; return }
      if (-not $c.laco -and $c.voltas -gt 0 -and $a -ge $c.voltas * $per) {
        if ($def.sai) { $c.fase = 'sai'; $c.tf = $t; continue } else { Cena-Fim $t; return }
      }
      $al = $a % $per
    } else {
      if ($a -ge $seq[-1].ate) {
        if ($c.fase -eq 'entra' -and $def.laco -and ($c.laco -or $c.voltas -gt 0)) { $c.fase = 'laco'; $c.tf = $t; continue }
        if ($c.fase -eq 'entra' -and $def.sai -and $def.laco) { $c.fase = 'sai'; $c.tf = $t; continue }
        Cena-Fim $t; return
      }
      $al = $a
    }
    $k = $seq[-1]
    foreach ($q in $seq) { if ($al -lt $q.ate) { $k = $q; break } }
    if ($c.id -eq 'pendurado') { $k = CN-Pendurado $k $t }
    elseif ($c.id -eq 'chefe' -and $c.fase -eq 'laco') { $k = CN-ChefeKf $k $t ($t - $c.t0) }
    elseif ($c.id -eq 'cochilo' -and $c.fase -eq 'laco') { $k = CN-CochiloKf $k $t $c.t0 }
    elseif ($c.id -eq 'pescaria' -and $c.fase -eq 'laco') { $k = CN-PescaKf $k $t $c.t0 }
    elseif ($c.id -eq 'costura' -and $c.fase -eq 'laco') { $k = CN-CosturaKf $k $al }
    elseif ($c.id -eq 'lupa' -and $c.fase -ne 'entra') { $k = CN-LupaKf $k $c.fase $al }
    $script:cq = @{ id = $c.id; fase = $c.fase; a = $al; tc = $t - $c.t0; k = $k; fixo = $false }
    return
  }
  Cena-Fim $t
}

# Pendurado: estica e balanca conforme a velocidade do arrasto (px/s; positivo = descendo)
function CN-Pendurado($k, [double]$t) {
  $vel = $script:arrVel
  if (($t - $script:arrT) -gt 0.12) { $vel = 0.0 }   # mouse parado: sem velocidade
  $n = [math]::Max(-1.0, [math]::Min(1.0, $vel / 1500.0))
  $kk = $k.Clone()
  $kk.armL = -4.0; $kk.armR = -4.0
  $kk.lift = 1.5 + [math]::Abs($n) * 1.5          # pernas esticam com a velocidade
  $kk.sy = 1.0 + [math]::Abs($n) * 0.12
  $kk.oy = $n * 2.0                                # o corpo atrasa em relacao ao movimento
  $kk.ox = [math]::Sin($t * 6.0) * 0.8             # balanco lateral
  $kk.eyY = $(if ($n -lt -0.2) { -15.0 } elseif ($n -gt 0.2) { -13.0 } else { -14.0 })
  $kk
}

# Chamado pelo MouseMove do widget durante o arrasto (y = Cursor.Position.Y em px de tela)
function Cena-Arrasto([double]$y, [double]$t) {
  $dt = $t - $script:arrT
  if ($dt -gt 0.001 -and $dt -lt 0.25) {
    $inst = ($y - $script:arrY) / $dt
    $script:arrVel = $script:arrVel + ($inst - $script:arrVel) * [math]::Min(1.0, $dt * 12)   # suavizado
  } elseif ($dt -ge 0.25) { $script:arrVel = 0.0 }
  $script:arrY = $y; $script:arrT = $t
}

# ---------- aderecos (desenhados com U, em coordenadas do mundo: nao andam com o corpo) ----------
function CN-Lerp([double[]]$xs, [double[]]$ys, [double]$x) {
  if ($x -le $xs[0]) { return $ys[0] }
  for ($i = 1; $i -lt $xs.Count; $i++) {
    if ($x -le $xs[$i]) { $f = ($x - $xs[$i - 1]) / ($xs[$i] - $xs[$i - 1]); return $ys[$i - 1] + ($ys[$i] - $ys[$i - 1]) * $f }
  }
  $ys[-1]
}

# camada: 'atras' (antes do corpo) ou 'frente' (depois). Chamada por Draw-Mascot com a origem no chao, centro do anel.
function Cena-Props($cq, [string]$camada, [double]$t) {
  switch ($cq.id) {
    'inseto' { if ($camada -eq 'frente') { CN-Inseto $cq $t } }
    'quadro' { if ($camada -eq 'atras') { CN-Quadro $cq $t } }
    'plugue' { if ($camada -eq 'atras') { CN-Plugue $cq $t } }
    'aguardando' { CN-Aguardando $cq $camada $t }
    'chefe' { CN-Chefe $cq $camada $t }
    'cochilo' { CN-Cochilo $cq $camada $t }
    'pescaria' { CN-Pescaria $cq $camada $t }
    'terminal' { if ($camada -eq 'atras') { CN-Terminal $cq $t } }
    'costura' { if ($camada -eq 'frente') { CN-Costura $cq } }
    'lampada' { if ($camada -eq 'frente') { CN-Lampada $cq $t } }
    'lupa' { CN-Lupa $cq $camada }
    'fumaca' { CN-Fumaca $cq $camada }
    'bandeira' { if ($camada -eq 'frente') { CN-Bandeira $cq $t } }
    'placa' { if ($camada -eq 'frente') { CN-Placa $cq $t } }
    'borboleta' { if ($camada -eq 'frente') { CN-Borboleta $cq $t } }
  }
}

# Joaninha vermelha de 4 x 2 que anda no chao. Posicao e direcao pelo tempo da cena.
function CN-Inseto($cq, [double]$t) {
  $A = $cq.tc
  $x = CN-Lerp @(0.0, 0.9, 1.4, 1.8, 2.6) @(-19.0, -12.5, -12.5, -13.0, -21.0) $A
  if ($x -lt -18.5) { return }                       # fora do anel
  $dir = $(if ($A -lt 1.6) { 1 } else { -1 })        # depois do tapa vira e foge
  $andando = ($A -lt 0.9 -or $A -gt 1.6)
  $passo = $(if ($andando -and -not $script:rm) { ([int][math]::Floor($t * 12)) % 2 } else { 0 })
  # patas (alternam ao andar)
  U $CN_PATA ($x + 0.5 + $passo) (-0.6) 0.6 0.6; U $CN_PATA ($x + 2.0 + $passo) (-0.6) 0.6 0.6
  # casco e cabeca (a cabeca vai na frente, do lado para onde anda)
  U $CN_BUG ($x + 0.5) (-2.2) 3 1.6
  U $CN_BUGD ($x + 1.7) (-2.2) 0.6 1.6               # risca do casco
  $hx = $(if ($dir -gt 0) { $x + 3.5 } else { $x - 0.4 })
  U $CN_BUGD $hx (-1.6) 0.9 1
}

# Quadro branco-esverdeado com cavalete, a direita. Gira (estreita) ao entrar e ao sair.
function CN-Quadro($cq, [double]$t) {
  $esc = 1.0
  if ($cq.fase -eq 'entra') { $esc = [math]::Max(0.0, [math]::Min(1.0, ($cq.a - 0.25) / 0.25)) }
  elseif ($cq.fase -eq 'sai') { $esc = [math]::Max(0.0, 1.0 - $cq.a / 0.3) }
  if ($esc -le 0.05) { return }
  $x0 = 5.0; $w = 8.0; $y0 = -14.0; $hq = 10.0; $mx = $x0 + $w / 2
  $wl = $w * $esc; $xl = $mx - $wl / 2
  # pes do cavalete
  U $CN_QPE ($xl + 0.5 * $esc) ($y0 + $hq) 0.8 (-($y0 + $hq)); U $CN_QPE ($xl + $wl - 1.3 * $esc) ($y0 + $hq) 0.8 (-($y0 + $hq))
  # moldura e face
  U $CN_QBORDA $xl $y0 $wl $hq
  U $CN_QFACE ($xl + 0.7 * $esc) ($y0 + 0.7) ($wl - 1.4 * $esc) ($hq - 1.4)
  if ($esc -lt 0.9) { return }
  # rabisco "7-3" que aparece aos poucos (sendo escrito) e o "?" embaixo
  $px = @(
    @(1, 1), @(2, 1), @(2.8, 1), @(2.8, 2), @(2, 3),           # 7
    @(3.8, 2), @(4.6, 2),                                      # -
    @(5.6, 1), @(6.3, 1.8), @(5.6, 2.6), @(6.3, 3.3)           # 3 (pontilhado, como no app)
  )
  $n = $px.Count
  if (-not $cq.fixo -and ($cq.fase -eq 'entra' -or ($cq.fase -eq 'laco' -and $cq.tc -lt 2.5))) {
    $n = [int][math]::Min($px.Count, [math]::Floor(($cq.tc - 0.5) * 8))
  }
  for ($i = 0; $i -lt $n; $i++) { U $CN_TINTA ($x0 + $px[$i][0]) ($y0 + $px[$i][1]) 0.8 0.8 }
  # "?" pisca 1x por segundo enquanto espera (parado com reducao de movimento)
  $ver = ($cq.fixo -or (([int][math]::Floor($t * 2)) % 2 -eq 0))
  if ($ver) {
    $qx = $x0 + 3.2; $qy = $y0 + 4.6
    U $CN_TINTA $qx $qy 2 0.8; U $CN_TINTA ($qx + 1.6) ($qy + 0.6) 0.8 1.2; U $CN_TINTA ($qx + 0.8) ($qy + 1.8) 0.8 1
    U $CN_TINTA ($qx + 0.8) ($qy + 3.4) 0.8 0.8
  }
}

# Plugue cinza deitado a esquerda, pinos virados para o bichinho: entra pela borda do anel, encaixa no braco e solta faisca
function CN-Plugue($cq, [double]$t) {
  $A = $cq.tc
  if ($A -gt 1.3) { return }
  $cor = $(if ($A -lt 0.15) { $CN_PLUGD } else { $CN_PLUG })   # "acende" ao aparecer (U nao tem alfa)
  $x = CN-Lerp @(0.0, 0.3, 0.55, 1.3) @(-18.0, -17.0, -15.5, -15.5) $A
  $y = -11.0
  U $CN_PLUGD ($x - 2) ($y + 1) 2 0.7                                      # cabo
  U $cor $x $y 2.5 2.5                                                    # corpo
  U $cor ($x + 2.5) ($y + 0.3) 1 0.6; U $cor ($x + 2.5) ($y + 1.6) 1 0.6   # pinos
  if ($A -ge 0.55 -and $A -lt 0.8 -and -not $script:rm) {
    U $CN_FAISCA ($x + 3.6) ($y - 0.9) 0.8 0.8; U $CN_FAISCA ($x + 3.8) ($y + 2.6) 0.8 0.8
  }
}

# Bolinhas de subagente (cor $SUBC) orbitando numa elipse achatada; as de tras (sen < 0) vao na camada 'atras', as da frente
# na 'frente'. Ampulheta pequena sobre a cabeca (so no expandido). Entra: crescem; sai: voam para dentro do mascote.
function CN-Aguardando($cq, [string]$camada, [double]$t) {
  $n = [math]::Max(1, [math]::Min(3, $script:cnAgN))
  $tc = $cq.tc
  $esc = 1.0; $voo = 0.0
  if ($cq.fase -eq 'entra') { $esc = [math]::Max(0.0, [math]::Min(1.0, $cq.a / 0.3)) }
  elseif ($cq.fase -eq 'sai') { $voo = [math]::Min(1.0, $cq.a / 0.4) }
  if ($esc -le 0.05 -or $voo -ge 1.0) { return }
  $cy = -9.0; $rx = 14.0; $ry = 7.0
  for ($i = 0; $i -lt $n; $i++) {
    $ang = $(if ($cq.fixo) { 0.6 + $i * 2.0944 } else { $tc * 1.75 + $i * 2.0944 })
    $sn = [math]::Sin($ang)
    if (($camada -eq 'atras') -ne ($sn -lt 0)) { continue }
    $f = 1.0 - $voo
    $x = [math]::Cos($ang) * $rx * $f; $y = $cy + $sn * $ry * $f
    $pul = $(if ($cq.fixo) { 0.0 } else { 0.5 + 0.5 * [math]::Sin($tc * 5.0 + $i * 2.1) })
    $s = (1.7 + 0.5 * $pul) * $esc * (1.0 - 0.6 * $voo)
    # bolinha em forma de cruz gorda (pixel art)
    U $SUBC ($x - $s * 0.6) ($y - $s * 0.3) ($s * 1.2) ($s * 0.6)
    U $SUBC ($x - $s * 0.3) ($y - $s * 0.6) ($s * 0.6) ($s * 1.2)
  }
  # ampulheta: so atras do corpo, expandido e fora da saida; vira a cada 2 s (parada no meio com reducao de movimento)
  if ($camada -ne 'atras' -or $script:compact -or $cq.fase -ne 'laco') { return }
  $p = $(if ($cq.fixo) { 0.5 } else { ($tc % 2.0) / 2.0 })
  $hx = -1.5; $hy = -23.0
  U $CN_VIDRO $hx $hy 3 0.6; U $CN_VIDRO $hx ($hy + 4.4) 3 0.6          # tampas
  U $CN_VIDRO $hx ($hy + 0.6) 0.5 1.8; U $CN_VIDRO ($hx + 2.5) ($hy + 0.6) 0.5 1.8   # paredes de cima
  U $CN_VIDRO $hx ($hy + 2.6) 0.5 1.8; U $CN_VIDRO ($hx + 2.5) ($hy + 2.6) 0.5 1.8   # paredes de baixo
  $alto = 1.6 * (1.0 - $p); $baixo = 1.6 * $p
  if ($alto -gt 0.1) { U $CN_AREIA ($hx + 0.5) ($hy + 0.6 + (1.6 - $alto)) 2 $alto }
  if ($baixo -gt 0.1) { U $CN_AREIA ($hx + 0.5) ($hy + 4.4 - $baixo) 2 $baixo }
  if (-not $cq.fixo -and $p -lt 0.95) { U $CN_AREIA ($hx + 1.2) ($hy + 2.2) 0.6 1.6 }   # fio de areia
}

# ---------- chefe de obra ----------
# posicao do mini-Claudinho i (de n) no tempo tc: vai e volta no chao entre -4 e 10 (a frente do chefe, que fica a
# esquerda), carregando caixa na ida
$CN_MINI_A = -4.0; $CN_MINI_B = 10.0; $CN_MINI_E = 1.5   # trajeto e escala do mini (1 = 4 x 3,4 pixels do bichinho)
function CN-MiniX([int]$i, [int]$n, [double]$tc) {
  $per = 8.0; $u = ($tc + $i * $per / [math]::Max(1, $n)) % $per; $span = $CN_MINI_B - $CN_MINI_A
  if ($u -lt 4.0) { return @(($CN_MINI_A + $span * $u / 4.0), 1) }
  @(($CN_MINI_B - $span * ($u - 4.0) / 4.0), -1)
}

# mini-Claudinho rosa (cor dos subagentes) em pe no chao; dir: 1 direita / -1 esquerda
function CN-Mini([double]$x, [int]$dir, [bool]$caixa, [int]$passo, [double]$aceno, [double]$dy = 0.0, [double]$esc = 0.0) {
  # dy: desloca o chao do mini (orbita com profundidade no cochilo); esc: escala (0 = $CN_MINI_E)
  $e = $(if ($esc -gt 0) { $esc } else { $CN_MINI_E }); $mb = $SUBC; $mi = '#1c1410'
  U $mb ($x - 2 * $e) (-3.4 * $e + $dy) (4 * $e) (2.2 * $e)
  U $mb ($x - 1.5 * $e) (-1.2 * $e + $dy) (0.8 * $e) ((1.2 - 0.5 * $passo) * $e)
  U $mb ($x + 0.7 * $e) (-1.2 * $e + $dy) (0.8 * $e) ((0.7 + 0.5 * $passo) * $e)
  $ex = $x + (-1.1 + 0.4 * $dir) * $e
  U $mi $ex (-2.8 * $e + $dy) (0.6 * $e) (0.6 * $e); U $mi ($ex + 1.6 * $e) (-2.8 * $e + $dy) (0.6 * $e) (0.6 * $e)
  if ($caixa) {
    U $mb ($x - 2.6 * $e) (-4.4 * $e + $dy) (0.6 * $e) (1.6 * $e); U $mb ($x + 2 * $e) (-4.4 * $e + $dy) (0.6 * $e) (1.6 * $e)   # bracos para cima
    U $CN_CAIXA ($x - 1.6 * $e) (-5.6 * $e + $dy) (3.2 * $e) (1.8 * $e); U $CN_CAIXAD ($x - 1.6 * $e) (-4.8 * $e + $dy) (3.2 * $e) (0.4 * $e)
  } elseif ($aceno -ge 0) {
    U $mb ($x - 2.6 * $e) (-2.8 * $e + $dy) (0.6 * $e) (1 * $e)
    U $mb ($x + 2 * $e) ((-5.0 + 0.6 * $aceno) * $e + $dy) (0.6 * $e) (1.8 * $e)          # tchau
  } else {
    # bracos balancando com o passo (correndo) ou parados
    $ba = 0.4 * $passo
    U $mb ($x - 2.6 * $e) ((-2.8 - $ba) * $e + $dy) (0.6 * $e) (1 * $e); U $mb ($x + 2 * $e) ((-3.2 + $ba) * $e + $dy) (0.6 * $e) (1 * $e)
  }
}

# olhos seguem o mini da frente; de tempos em tempos confere a prancheta; sorri quando alguem termina
function CN-ChefeKf($k, [double]$t, [double]$tc) {
  $kk = $k.Clone()
  $n = [math]::Max(1, [math]::Min(3, $script:cnAgN))
  $m = CN-MiniX 0 $n $tc
  $kk.eyX = [math]::Max(-1.0, [math]::Min(1.0, ($m[0] - 3.0) / 7.0))   # o chefe fica em x = -5; os minis andam de -4 a 10
  $ciclo = $tc % 6.0
  if ($ciclo -ge 4.2 -and $ciclo -lt 5.2) { $kk.eyX = 1.0; $kk.eyY = -12.5; $kk.tilt = $true }   # confere a prancheta
  if (($t - $script:cnSaiu) -lt 0.9) { $kk.eyes = 'happy'; $kk.eyY = -14.0 }
  $kk
}

function CN-Chefe($cq, [string]$camada, [double]$t) {
  $tc = $cq.tc
  if ($camada -eq 'frente') {
    # minis trabalhando (na saida so o ultimo, acenando)
    $n = $(if ($cq.fase -eq 'sai') { 0 } else { [math]::Max(1, [math]::Min(3, $script:cnAgN)) })
    $passo = $(if ($cq.fixo) { 0 } else { ([int][math]::Floor($t * 8)) % 2 })
    for ($i = 0; $i -lt $n; $i++) {
      if ($cq.fixo) { $x = $CN_MINI_A + 1.0 + $i * 6.0; $d = 1 } else { $m = CN-MiniX $i $n $tc; $x = $m[0]; $d = $m[1] }
      CN-Mini $x $d ($d -gt 0) $passo -1
    }
    # quem acabou de terminar: para onde estava, acena e some numa fumacinha
    $w = $t - $script:cnSaiu
    if ($w -ge 0 -and $w -lt 0.9 -and $script:cnSaiuIdx -lt 3 -and $script:cnSaiu -ge ($t - $tc)) {
      $m = CN-MiniX $script:cnSaiuIdx $script:cnSaiuN ($script:cnSaiu - ($t - $tc))
      if ($w -lt 0.6) { CN-Mini $m[0] $m[1] $false 0 ([math]::Abs([math]::Sin($w * 14))) }
      else {
        $r = 1.0 + ($w - 0.6) * 8
        U $CN_FUMACA ($m[0] - $r) (-3.0 - $r * 0.4) 1 1; U $CN_FUMACA ($m[0] + $r - 1) (-3.0 - $r * 0.4) 1 1; U $CN_FUMACA ($m[0] - 0.5) (-4.0 - $r) 1 1
      }
    }
    # prancheta na mao direita, com um check verde por subagente terminado
    if ($cq.fase -ne 'sai' -or $cq.a -lt 0.3) {
      $esc = $(if ($cq.fase -eq 'entra') { [math]::Min(1.0, $cq.a / 0.3) } else { 1.0 })
      if ($esc -lt 0.2) { return }
      $px = 4.5; $py = -13.0   # mao direita do chefe (corpo em x = -5)
      U $CN_PRANCHA $px $py 3.5 (5 * $esc)
      U $CN_PAPEL ($px + 0.5) ($py + 0.8) 2.5 (3.8 * $esc)
      U $CN_QPE ($px + 1.1) ($py - 0.5) 1.3 0.8
      if ($esc -lt 1) { return }
      for ($l = 0; $l -lt 3; $l++) {
        $ly = $py + 1.4 + $l * 1.1
        if ($l -lt $script:cnFeitos) { U $CN_OK ($px + 0.8) $ly 0.6 0.5 }
        U $CN_TINTA ($px + 1.6) $ly 1.1 0.4
      }
    }
  }
}

# ---------- cochilo vigiado ----------
function CN-CochiloKf($k, [double]$t, [double]$t0) {
  $kk = $k.Clone()
  if (-not $script:rm) { $kk.sy = 1.0 + 0.025 * [math]::Sin($t * 2.4) }   # respira
  $ang = ($t - $t0) * $CN_CO_VEL
  $kk.eyX = [math]::Cos($ang) * 1.0                                        # o olho aberto segue o 1o mini
  $w = $t - $script:cnSaiu
  if ($script:cnSaiu -ge $t0 -and $w -ge 0 -and $w -lt 1.4) {             # um subagente terminou: acorda num pulo
    $kk.sy = 1.0; $kk.eyes = 'open'; $kk.eyX = 0.0
    if ($w -lt 0.12) { $kk.lift = -2.5 }
    elseif ($w -lt 0.4) { $kk.lift = 0.0; $kk.oy = -4.0; $kk.armL = -3.0; $kk.armR = -3.0; $kk.eyY = -15.0 }
    else { $kk.lift = 0.0; $kk.eyX = $(if ($w -lt 0.9) { -1.0 } else { 1.0 }) }   # olha em volta
  }
  $kk
}

function CN-Cochilo($cq, [string]$camada, [double]$t) {
  $tc = $cq.tc
  $acordado = ($cq.fase -eq 'sai') -or (($t - $script:cnSaiu) -ge 0 -and ($t - $script:cnSaiu) -lt 1.4 -and $script:cnSaiu -ge ($t - $tc))
  # mini-Claudinhos rosa (um por subagente) correndo em volta dele no chao: na frente descem um pouco,
  # atras sobem e passam por tras do corpo (profundidade)
  if ($cq.fase -ne 'sai') {
    $n = [math]::Max(1, [math]::Min(3, $script:cnAgN))
    $passo = $(if ($cq.fixo) { 0 } else { ([int][math]::Floor($t * 10)) % 2 })
    for ($i = 0; $i -lt $n; $i++) {
      $ang = $(if ($cq.fixo) { 0.6 + $i * 2.0944 } else { $tc * $CN_CO_VEL + $i * 2.0944 })
      $sn = [math]::Sin($ang)
      if (($camada -eq 'atras') -ne ($sn -lt 0)) { continue }
      $x = [math]::Cos($ang) * 12.0
      $d = $(if ($sn -gt 0) { -1 } else { 1 })   # anda no sentido em que x muda (-sin)
      CN-Mini $x $d $false $passo -1 ($sn * 2.5) 1.1
    }
  }
  if ($camada -ne 'frente') { return }
  if ($acordado) {
    $w = $(if ($cq.fase -eq 'sai') { $cq.a } else { $t - $script:cnSaiu })
    if ($w -lt 0.9) { U $CN_ALERTA 9.5 (-21.0) 1 2.4; U $CN_ALERTA 9.5 (-18.0) 1 0.9 }   # "!"
    return
  }
  if ($cq.fase -eq 'entra') { return }
  # "z" subindo da cabeca (dois, defasados); parado com reducao de movimento
  for ($j = 0; $j -lt 2; $j++) {
    $age = $(if ($cq.fixo) { 0.6 + $j * 0.8 } else { ($tc + $j * 0.8) % 1.6 })
    $s = 0.5 + $age * 0.25
    $zx = 3.5 + $age * 1.8; $zy = -16.5 - $age * 2.6
    $cor = $(if ($age -lt 1.1) { $CN_Z } else { $CN_ZD })
    U $cor $zx $zy (3 * $s) $s; U $cor ($zx + $s) ($zy + $s) $s $s; U $cor $zx ($zy + 2 * $s) (3 * $s) $s
  }
}

# ---------- pescaria ----------
# geometria fixa (o corpo fica em ox = -4, sentado): mao direita ~ (7, -8), ponta da vara (11, -17), agua em y = 2,2
$script:PQ_MAO = @(7.0, -8.0); $script:PQ_PONTA = @(11.0, -17.0); $script:PQ_AGUA = 2.2

# linha reta de "pixels" de lado `esp` entre dois pontos
function CN-Linha([double]$x0, [double]$y0, [double]$x1, [double]$y1, [string]$cor, [double]$esp) {
  $d = [math]::Max([math]::Abs($x1 - $x0), [math]::Abs($y1 - $y0))
  $n = [math]::Max(1, [int][math]::Ceiling($d / $esp))
  for ($i = 0; $i -le $n; $i++) { $f = $i / $n; U $cor ($x0 + ($x1 - $x0) * $f - $esp / 2) ($y0 + ($y1 - $y0) * $f - $esp / 2) $esp $esp }
}

function CN-PqX([int]$i) { 6.0 + $i * 3.0 }   # onde a linha i entra na agua

# a boia i afunda de vez em quando (deterministico, cada linha no seu ritmo)
function CN-PqPuxao([int]$i, [double]$tc) {
  $f = (($tc * 0.37 + $i * 0.61) % 1.0)
  ($f -lt 0.06)
}

# janela da fisgada: $null ou o tempo desde que o subagente terminou (so se terminou durante esta cena)
function CN-PqFisga([double]$t, [double]$tc) {
  $w = $t - $script:cnSaiu
  if ($script:cnSaiu -ge ($t - $tc) -and $w -ge 0 -and $w -lt 1.2) { return $w }
  $null
}

function CN-PescaKf($k, [double]$t, [double]$t0) {
  $kk = $k.Clone(); $tc = $t - $t0
  $n = [math]::Max(1, [math]::Min(3, $script:cnAgN))
  for ($i = 0; $i -lt $n; $i++) { if (CN-PqPuxao $i $tc) { $kk.eyY = -14.0; $kk.eyX = 1.0 } }   # boia afundou: olha
  $w = CN-PqFisga $t $tc
  if ($null -ne $w) {
    if ($w -lt 0.3) { $kk.armR = -3.0; $kk.oy = -0.5 }        # puxa
    elseif ($w -lt 1.1) { $kk.armR = -2.0; $kk.eyes = 'happy'; $kk.eyX = 0.0 }
  }
  $kk
}

# peixinho rosa de 3 x 1,6 (rabo do lado oposto a dir); balanca o rabo
function CN-Peixe([double]$x, [double]$y, [int]$dir, [double]$t) {
  U $SUBC ($x - 1.5) ($y - 0.8) 3 1.6
  $rx = $(if ($dir -gt 0) { $x - 2.3 } else { $x + 1.5 })
  $ab = $(if (([int][math]::Floor($t * 12)) % 2 -eq 0) { 0.0 } else { 0.4 })
  U $SUBC $rx ($y - 0.9 + $ab) 0.8 0.8; U $SUBC $rx ($y + 0.1 - $ab) 0.8 0.8
  $ox = $(if ($dir -gt 0) { $x + 0.7 } else { $x - 1.1 })
  U '#1c1410' $ox ($y - 0.4) 0.4 0.4
}

function CN-Pescaria($cq, [string]$camada, [double]$t) {
  $tc = $cq.tc
  $vis = $(if ($cq.fase -eq 'entra') { [math]::Max(0.0, ($cq.a - 0.25) / 0.25) } else { 1.0 })
  if ($camada -eq 'atras') {
    # pier (tabua e um poste) e agua com ondinhas andando
    U $CN_VARA (-15.0) 0 18 0.8; U $CN_CAIXAD 1.5 0.8 0.8 3
    $desl = $(if ($cq.fixo) { 0.0 } else { ($tc * 1.5) % 3.0 })
    for ($wx = 3.0 - $desl; $wx -lt 14.0; $wx += 3.0) { if ($wx -ge 3.0) { U $CN_AGUA $wx $script:PQ_AGUA 1.6 0.6 } }
    for ($wx = 4.5 + $desl; $wx -lt 13.0; $wx += 3.0) { U $CN_AGUAD $wx ($script:PQ_AGUA + 1.4) 1.2 0.5 }
    return
  }
  # frente: peixes ja pescados na pilha do pier
  for ($j = 0; $j -lt $script:cnFeitos; $j++) {
    $chegou = $true
    $w = CN-PqFisga $t $tc
    if ($null -ne $w -and $j -eq $script:cnFeitos - 1 -and $w -lt 1.1) { $chegou = $false }
    if ($cq.fase -eq 'sai' -and $j -eq $script:cnFeitos - 1 -and $cq.a -lt 1.1) { $chegou = $false }
    if ($chegou) { CN-Peixe (-10.0 + $j * 3.2) (-1.0) 1 0 }
  }
  if ($vis -le 0) { return }
  if ($cq.fase -eq 'sai' -and $cq.a -ge 1.1) { return }   # soltou a vara para pular
  # vara: da mao ate a ponta (a ponta sobe quando ele puxa)
  $w = $(if ($cq.fase -eq 'sai') { $cq.a } else { CN-PqFisga $t $tc })
  $pxp = $script:PQ_PONTA[0]; $pyp = $script:PQ_PONTA[1]
  if ($null -ne $w -and $w -lt 0.3) { $pyp -= 1.5; $pxp -= 1.0 }
  CN-Linha $script:PQ_MAO[0] $script:PQ_MAO[1] $pxp $pyp $CN_VARA 0.8
  # linhas e boias (uma por subagente); a da fisgada vira o peixe subindo
  $n = $(if ($cq.fase -eq 'sai') { 1 } else { [math]::Max(1, [math]::Min(3, $script:cnAgN)) })
  $iFis = -1
  if ($null -ne $w) { $iFis = $(if ($cq.fase -eq 'sai') { 0 } else { [math]::Min(2, $script:cnSaiuIdx) }) }
  $nDes = [math]::Max($n, $iFis + 1)
  for ($i = 0; $i -lt $nDes; $i++) {
    $lx = CN-PqX $i
    if ($i -eq $iFis) {
      # peixe: sai da agua, sobe em arco por cima dele e cai na pilha do pier
      if ($w -lt 1.1) {
        $f = [math]::Min(1.0, $w / 1.1)
        $dx = -10.0 + ($script:cnFeitos - 1) * 3.2
        $fx = $lx + ($dx - $lx) * $f
        $fy = $script:PQ_AGUA + (-1.0 - $script:PQ_AGUA) * $f - 80.0 * $f * (1 - $f)   # arco por cima da cabeca
        if ($w -lt 0.35) { CN-Linha $pxp $pyp $fx ($fy - 0.8) $CN_LINHA 0.4 }   # ainda preso na linha
        CN-Peixe $fx $fy -1 $t
        if ($w -lt 0.25) { U $CN_AGUA ($lx - 1.5) ($script:PQ_AGUA - 0.8) 0.6 0.6; U $CN_AGUA ($lx + 1) ($script:PQ_AGUA - 1) 0.6 0.6 }   # respingo
      }
      continue
    }
    if ($i -ge $n) { continue }
    $puxa = (-not $cq.fixo) -and (CN-PqPuxao $i $tc)
    $bob = $(if ($cq.fixo) { 0.0 } elseif ($puxa) { 0.8 } else { 0.25 * [math]::Sin($tc * 3.0 + $i * 1.7) })
    $by = $script:PQ_AGUA - 0.6 + $bob
    CN-Linha $pxp $pyp $lx ($by - 0.6) $CN_LINHA 0.4
    U $CN_LINHAD ($lx - 0.2) ($script:PQ_AGUA + 0.6) 0.4 4.5          # linha seguindo para o fundo (sai do quadro)
    U $CN_BOIA ($lx - 0.5) ($by - 0.6) 1 0.6; U $CN_PAPEL ($lx - 0.5) $by 1 0.5
  }
}

# ---------- terminal (Codando com Bash) ----------
# Monitor de moldura cinza a esquerda (x -14..-6, y -13..-5; cantos a <= 14,9 do centro): enquanto o comando roda sobem
# linhas verdes de saida e o cursor pisca embaixo; na saida (comando acabou) as linhas param e aparece um "$" novo.
function CN-Terminal($cq, [double]$t) {
  $esc = 1.0
  if ($cq.fase -eq 'entra') { $esc = [math]::Min(1.0, $cq.a / 0.4) }
  elseif ($cq.fase -eq 'sai') { $esc = [math]::Max(0.0, 1.0 - [math]::Max(0.0, $cq.a - 0.5) / 0.3) }
  if ($esc -le 0.05) { return }
  U $CN_QPE (-10.8) (-5) 1.6 5; U $CN_QPE (-12.5) (-0.8) 5 0.8   # pe e base
  $hy = 8.0 * $esc
  U $CN_QBORDA (-14) (-5 - $hy) 8 $hy                              # moldura cresce de baixo para cima
  if ($esc -lt 1) { return }
  U $CN_TELA (-13.3) (-12.3) 6.6 6.6
  $sai = ($cq.fase -eq 'sai')
  # quantas linhas ja sairam (2,5 por segundo); na saida congela no instante em que o comando acabou
  $tl = $(if ($sai) { $cq.tc - $cq.a } else { $cq.tc })
  $n = [int][math]::Floor([math]::Max(0.0, $tl - 0.4) * 2.5)
  # fileira 0 = a de baixo (cursor ou "$"); fileiras 1..3 = as ultimas linhas, a mais nova embaixo
  for ($j = 1; $j -le 3; $j++) {
    $k = $n - $j; if ($k -lt 0) { break }
    U $CN_OK (-12.9) (-7.2 - 1.4 * $j) (1.6 + (($k * 7) % 5) * 0.9) 0.7
  }
  $pisca = (([int][math]::Floor($t * 3)) % 2 -eq 0)
  if ($sai) {
    U $CN_FAISCA (-12.9) (-7.5) 0.8 1.1                             # "$" novo
    if ($pisca) { U $CN_PAPEL (-11.7) (-7.2) 0.7 0.7 }
  } elseif ($pisca) { U $CN_PAPEL (-12.9) (-7.2) 0.7 0.7 }
}

# ---------- costura (Codando com Edit) ----------
# Faixa de 4 pedacos a direita, abaixo da mao (x 4,5..13,5, y -4,5..-2,9; cantos a <= 14,6 do centro). A cada volta (3,2 s) um pedaco
# do meio (alterna entre o 2o e o 3o) sobe e some, um verde desce no lugar e a agulha costura as duas emendas.
# Tempos da volta: 0,3-0,8 tira; 0,8-1,3 poe; 1,3-2,6 costura (emenda esquerda, depois direita); 2,6-3,2 contente.
function CN-CsAgulha([double]$a) {
  # $null fora da costura; senao @(x da emenda, y do topo da agulha)
  if ($a -lt 1.3 -or $a -ge 2.6) { return $null }
  $e = $(if ($a -lt 1.95) { 0 } else { 1 })
  @((6.75 + 2.25 * $e), (-7.6 + 2.4 * [math]::Abs([math]::Sin(($a - 1.3) * [math]::PI * 3))))
}

function CN-CosturaKf($k, [double]$a) {
  $kk = $k.Clone()
  if ($a -ge 0.3 -and $a -lt 0.8) { $kk.armR = -2.0 }                       # puxa o pedaco velho
  $ag = CN-CsAgulha $a
  if ($null -ne $ag -and $ag[1] -lt -6.5) { $kk.armR = -1.0 }               # mao sobe com a agulha
  if ($a -ge 2.6) { $kk.eyes = 'happy' }
  $kk
}

function CN-Costura($cq) {
  $esc = 1.0
  if ($cq.fase -eq 'entra') { $esc = [math]::Min(1.0, $cq.a / 0.4) }
  elseif ($cq.fase -eq 'sai') { $esc = [math]::Max(0.0, 1.0 - $cq.a / 0.4) }
  if ($esc -le 0.05) { return }
  $laco = ($cq.fase -eq 'laco')
  $a = $(if ($laco) { $cq.a } else { 0.0 })
  $volta = [int][math]::Floor([math]::Max(0.0, $cq.tc - 0.4) / 3.2)
  $r = 1 + ($volta % 2)                                                     # pedaco trocado nesta volta
  $y0 = -4.5
  for ($i = 0; $i -lt 4; $i++) {
    $x = 4.5 + 2.25 * $i
    if ($x + 2.25 * $esc -gt 13.51) { break }
    $novo = ($i -ne 0 -and $volta -ge 1)                                    # ja foi trocado numa volta anterior
    $dy = 0.0; $velho = $false
    if ($laco -and $i -eq $r) {
      if ($a -lt 0.8) { $velho = $true; $dy = -6.5 * [math]::Max(0.0, $a - 0.3) / 0.5; if ($a -ge 0.75) { continue } }
      else { $novo = $true; $dy = -6.0 * [math]::Max(0.0, 1.3 - $a) / 0.5 }
    }
    U $(if ($novo) { $CN_QFACE } else { $CN_PAPEL }) $x ($y0 + $dy) 2.0 1.6
    U $(if ($velho) { $CN_BUG } else { $CN_TINTA }) ($x + 0.3) ($y0 + 0.5 + $dy) 1.5 0.6   # "linha de codigo"
  }
  if (-not $laco) { return }
  # pontos ja dados nas emendas do pedaco novo
  for ($e = 0; $e -lt 2; $e++) {
    $fim = 1.95 + 0.65 * $e
    if ($a -ge $fim - 0.65) {
      $hh = 2.6 * [math]::Min(1.0, ($a - ($fim - 0.65)) / 0.65)
      U $CN_PINCEL (6.5 + 2.25 * ($r - 1) + 2.25 * $e) (-4.8) 0.5 $hh
    }
  }
  # agulha e linha: da mao (x 8) ate o olho da agulha; fora da costura a agulha fica na mao
  $ag = CN-CsAgulha $a
  if ($null -eq $ag) { U $CN_AGULHA 8.3 (-12.6) 0.5 2.4; return }
  $sx = $ag[0] + 2.25 * ($r - 1); $sy = $ag[1]
  CN-Linha 8.0 (-10.0) $sx $sy $CN_PINCEL 0.6
  U $CN_AGULHA ($sx - 0.25) $sy 0.5 2.4
}

# ---------- lampada (Pensando) ----------
# Lampada de 3 x 3,6 sobre a cabeca (x -1,5..1,5, y -22,6..-17,8; cantos a <= 14,6 do centro); fica parada no pulo da saida.
# Laco: fraca, com piscadas curtas; saida: acesa forte, com 4 raios.
function CN-Lampada($cq, [double]$t) {
  $dy = 0.0
  $cor = $CN_LAMPF
  if ($cq.fase -eq 'entra' -and $cq.a -lt 0.2) { $cor = $CN_QPE }                        # ainda apagada
  elseif ($cq.fase -eq 'sai') { $cor = $CN_LAMPA }
  elseif ((($t * 1.3) % 1.0) -lt 0.08 -or ((($t * 1.3) + 0.37) % 1.0) -lt 0.04) { $cor = $CN_LAMPM }   # pisca
  U $cor (-1.0) (-22.6 + $dy) 2.0 0.6
  U $cor (-1.5) (-22.0 + $dy) 3.0 3.0
  U $CN_QBORDA (-1.0) (-19.0 + $dy) 2.0 1.2                                                # rosca
  if ($cq.fase -eq 'sai') {
    U $CN_LAMPA (-3.4) (-21.5 + $dy) 0.8 0.8; U $CN_LAMPA 2.6 (-21.5 + $dy) 0.8 0.8
    U $CN_LAMPA (-3.6) (-18.6 + $dy) 0.8 0.8; U $CN_LAMPA 2.8 (-18.6 + $dy) 0.8 0.8
  }
}

# ---------- lupa (Lendo com Read/Glob/LS) ----------
# Laco de 6 s: 3 s andando para a direita (ox -3 -> 1) e 3 s para a esquerda (ox 3 -> -1), com a lupa na mao da frente,
# a 9 unidades do corpo, encostada no chao e varrendo +-1 (aro x ate +-12,7, y -3,4..0; cantos a <= 14,9 do centro).
# Pegadas no chao (x -11..11); a que passa embaixo da lente aparece aumentada (cortada no vidro).
function CN-LupaPos([double]$a) {
  # @(ox, dir)
  if ($a -lt 3.0) { return @((-3.0 + 4.0 * $a / 3.0), 1) }
  @((3.0 - 4.0 * ($a - 3.0) / 3.0), -1)
}

function CN-LupaKf($k, [string]$fase, [double]$a) {
  $kk = $k.Clone()
  if ($fase -eq 'sai') { $kk.ox = $script:cnLupaOx * [math]::Max(0.0, 1.0 - $a / 0.4); return $kk }
  $p = CN-LupaPos $a
  $kk.ox = $p[0]; $kk.eyX = [double]$p[1]
  $script:cnLupaOx = $p[0]
  $kk
}

function CN-Lupa($cq, [string]$camada) {
  if ($camada -eq 'atras') {
    if ($cq.fase -eq 'sai' -and $cq.a -gt 0.25) { return }
    for ($i = 0; $i -lt 10; $i++) { U $CN_PATA (-11.0 + 2.4 * $i) (-1.2 + 0.6 * ($i % 2)) 1.0 0.6 }
    return
  }
  if ($cq.fase -eq 'sai' -or ($cq.fase -eq 'entra' -and $cq.a -lt 0.2)) { return }
  if ($cq.fase -eq 'entra') { $ox = $cq.k.ox; $dir = 1 } else { $p = CN-LupaPos $cq.a; $ox = $p[0]; $dir = $p[1] }
  $xl = $ox + 9.0 * $dir + $(if ($cq.fase -eq 'laco') { [math]::Sin($cq.a * 4.0) } else { 0.0 })
  CN-Linha ($ox + 10.0 * $dir) (-8.0) $xl (-3.4) $CN_VARA 0.7   # cabo, da mao ate o aro
  U $CN_AGULHA ($xl - 1.7) (-3.4) 3.4 3.4                    # aro
  U $CN_LENTE ($xl - 1.1) (-2.8) 2.2 2.2                     # vidro
  # pegada aumentada embaixo da lente (1,4 x 1, cortada nas bordas do vidro)
  $i = [int][math]::Round(($xl - 0.5 + 11.0) / 2.4)
  if ($i -ge 0 -and $i -lt 10) {
    $px = -11.0 + 2.4 * $i - 0.2
    $x0 = [math]::Max($px, $xl - 1.1); $x1 = [math]::Min($px + 1.4, $xl + 1.1)
    if ($x1 - $x0 -ge 0.6) { U $CN_AGUAD $x0 (-1.6 + 0.6 * ($i % 2)) ($x1 - $x0) 1.0 }
  }
}

# ---------- fumaca (Erro) ----------
# Notebook de frente no chao, a esquerda (x -12,5..-5, y -6..0; cantos a <= 14,8 do centro), tela vermelha escura
# (pisca vermelha na entrada). 4 nuvens sobem da tampa, crescem, clareiam e vao para a esquerda (abanadas): ate (-12,9, -14,8).
# O notebook vai atras do corpo; a fumaca na frente (passa pela mao que abana).
function CN-Fumaca($cq, [string]$camada) {
  if ($camada -eq 'frente') {
    for ($i = 0; $i -lt 4; $i++) {
      $f = (($cq.tc + $i * 0.375) % 1.5) / 1.5
      if ($cq.tc + $i * 0.375 -lt 1.5 -and $f -lt 0.05) { continue }
      $s = 1.4 + 1.2 * $f
      $x = -10.0 - 1.2 * $f + 0.3 * [math]::Sin($cq.tc * 3 + $i)
      $y = -6.5 - 7.0 * $f
      U $(if ($f -lt 0.5) { $CN_ZD } else { $CN_FUMACA }) ($x - $s / 2) ($y - $s / 2) $s $s
    }
    return
  }
  U $CN_QBORDA (-12.5) (-1.0) 7.5 1.0                                     # base
  U $CN_QPE (-12.0) (-6.0) 6.5 5.0                                        # tampa
  $tela = $(if ($cq.fase -eq 'entra' -and ([int][math]::Floor($cq.a * 10)) % 2 -eq 0) { $CN_BUG } else { $CN_BUGD })
  U $tela (-11.4) (-5.4) 5.3 3.8
}

# ---------- bandeira (Terminou) ----------
# Mastro na mao direita (x 9,4..10,1 com ox -3, topo em -13) e bandeira para fora (x 10,1..12,5, y -13..-10,6); entra carregada
# 1,5 acima do chao, acompanhando a mao, e afunda nele aos 0,45 s (cantos a <= 14,8 do centro). Some afundando nos ultimos 0,3 s.
function CN-Bandeira($cq, [double]$t) {
  $a = $cq.a
  if ($a -lt 0.2) { return }                                           # aparece quando ele chega (ox -3)
  $dy = CN-Lerp @(0.35, 0.45) @(-1.5, 0.0) $a
  $mx = 12.4 + $cq.k.ox                                                # mastro na mao
  $topo = -13.0 + $dy + [math]::Max(0.0, $a - 1.9) / 0.3 * 13.0        # no fim afunda
  if ($topo -ge -0.5) { return }
  U $CN_QBORDA $mx $topo 0.7 ($dy - $topo)
  if ($topo -gt -10.6 + $dy) { return }
  $w = $(if (([int][math]::Floor($t * 6)) % 2 -eq 0 -or $a -lt 0.55) { 0.0 } else { 0.6 })   # tremula
  U $CN_OK ($mx + 0.7) $topo 2.4 1.2
  U $CN_OKD ($mx + 0.7) ($topo + 1.2) (2.4 - $w) 1.2
  if ($a -ge 0.45 -and $a -lt 0.75) {                                  # poeira ao fincar
    $r = ($a - 0.45) * 4
    U $CN_FUMACA (8.6 - $r) (-0.8) 0.6 0.6; U $CN_FUMACA (10.8 + $r) (-0.8) 0.6 0.6
  }
}

# ---------- placa (Aguardando permissao) ----------
# Placa de 7,8 x 5 na mao direita levantada (x 3,3..11,1, y -17,5..-12,5; com o balanco de +-0,4, cantos a <= 14,9 do centro),
# num cabo marrom, moldura cinza, fundo de papel e "OK?" em traco de 0,7. Sobe na entrada e desce na saida.
function CN-Placa($cq, [double]$t) {
  $dy = 0.0
  if ($cq.fase -eq 'entra') { if ($cq.a -lt 0.2) { return }; $dy = 4.0 * (1.0 - ($cq.a - 0.2) / 0.2) }
  elseif ($cq.fase -eq 'sai') { $dy = 4.0 * $cq.a / 0.25; if ($dy -ge 4.0) { return } }
  $dx = $(if ($cq.fixo -or $script:rm -or $cq.fase -ne 'laco') { 0.0 } else { 0.4 * [math]::Sin($t * 3.0) })
  $x = 3.3 + $dx; $y = -17.5 + $dy
  U $CN_VARA ($x + 2.7) ($y + 5.0) 0.8 (2.5 - [math]::Min(2.5, $dy))   # cabo ate a mao
  U $CN_QBORDA $x $y 7.8 5.0
  U $CN_PAPEL ($x + 0.4) ($y + 0.4) 7.0 4.2
  if ($dy -gt 1.0) { return }
  $bx = $x + 0.5; $by = $y + 1.0
  # O
  U $CN_TINTA $bx $by 2.0 0.7; U $CN_TINTA $bx ($by + 2.3) 2.0 0.7; U $CN_TINTA $bx $by 0.7 3.0; U $CN_TINTA ($bx + 1.3) $by 0.7 3.0
  # K
  $kx = $bx + 2.6
  U $CN_TINTA $kx $by 0.7 3.0; U $CN_TINTA ($kx + 0.7) ($by + 1.15) 0.7 0.7
  U $CN_TINTA ($kx + 1.4) $by 0.7 1.15; U $CN_TINTA ($kx + 1.4) ($by + 1.85) 0.7 1.15
  # ?
  $qx = $bx + 4.8
  U $CN_TINTA $qx $by 1.9 0.7; U $CN_TINTA ($qx + 1.2) ($by + 0.5) 0.7 0.9
  U $CN_TINTA ($qx + 0.6) ($by + 1.3) 0.7 0.6; U $CN_TINTA ($qx + 0.6) ($by + 2.3) 0.7 0.7
}

# ---------- borboleta (Ocioso) ----------
# Asas azuis de 1,4 x 1,2 (+ 1 x 0,7 embaixo) e corpo marrom. Caminho: entra em (12, -13), passa por cima da cabeca e pousa nela
# em (0,5, -17,4) aos 1,6 s, fica ate 3,8 s batendo as asas devagar e sai por (-4, -20,5) ate (-11, -14).
# Cantos a <= 15 do centro em todo o caminho.
function CN-Borboleta($cq, [double]$t) {
  $A = $cq.tc
  if ($A -gt 4.9) { return }
  $ts = @(0.0, 0.5, 1.0, 1.6, 3.8, 4.3, 4.9)
  $bx = CN-Lerp $ts @(12.0, 8.0, 4.0, 0.5, 0.5, -4.0, -11.0) $A
  $by = CN-Lerp $ts @(-13.0, -18.0, -19.8, -17.4, -17.4, -20.5, -14.0) $A
  $pousada = ($A -ge 1.6 -and $A -lt 3.8)
  $aberta = $(if ($pousada) { (($A % 0.8) -lt 0.6) } else { (([int][math]::Floor($t * 10)) % 2 -eq 0) })
  if ($aberta) {
    U $CN_ASA ($bx - 1.7) ($by - 1.0) 1.4 1.2; U $CN_ASA ($bx + 0.3) ($by - 1.0) 1.4 1.2
    U $CN_ASAD ($bx - 1.3) ($by + 0.2) 1.0 0.7; U $CN_ASAD ($bx + 0.3) ($by + 0.2) 1.0 0.7
  } else {
    U $CN_ASA ($bx - 0.9) ($by - 1.4) 0.6 1.4; U $CN_ASA ($bx + 0.3) ($by - 1.4) 0.6 1.4
  }
  U $CN_VARA ($bx - 0.3) ($by - 0.8) 0.6 1.6
}
