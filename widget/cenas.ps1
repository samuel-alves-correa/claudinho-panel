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
# Depuracao: CW_CENAS=0 desliga todas as cenas; CW_CENA=inseto|quadro|plugue|aguardando repete essa cena em laco (bom para gravar GIF).

# ---------- configuracao ----------
$script:CN_ON = ($env:CW_CENAS -ne '0')
$script:CN_DEBUG = [string]$env:CW_CENA
$CN_OCIOSO_MIN = 40.0      # s parado ate a 1a cena do rodizio (e intervalo minimo entre cenas)
$CN_OCIOSO_VAR = 40.0      # + ate isso de sorteio
$CN_FALHA_JANELA = 8000.0  # ms: falha de ferramenta mais velha que isso nao vira inseto (evita tocar ao abrir o widget)
$CN_RODIZIO = @('plugue', 'inseto', 'quadro')

# cores dos adereços (contraste >= 3:1 sobre o preto do notch)
$CN_BUG = '#e5484d'; $CN_BUGD = '#7a1f22'; $CN_PATA = '#8a8a8a'
$CN_QFACE = '#bfe9d9'; $CN_QBORDA = '#9aa0a8'; $CN_QPE = '#6b7078'; $CN_TINTA = '#1b1b1b'; $CN_PINCEL = '#8b7cf6'
$CN_PLUG = '#9aa0a8'; $CN_PLUGD = '#6b7078'; $CN_FAISCA = '#f5c542'
$CN_AREIA = '#e8c97a'; $CN_VIDRO = '#9aa0a8'   # ampulheta da cena aguardando (as bolinhas usam $SUBC do widget)

# ---------- estado ----------
$script:cena = $null        # @{ id; prio; fase = 'entra'|'laco'|'sai'; tf = inicio da fase; t0 = inicio da cena; voltas; fixo; fam }
$script:cq = $null          # quadro atual: @{ id; fase; a = tempo na fase; tc = tempo na cena; k = quadro-chave }
$script:cnFalhaVista = -1.0 # failAt ja tratado (-1 = ainda nao leu: o 1o valor so e registrado, nao toca)
$script:cnProxOcioso = 0.0  # quando tocar a proxima cena do rodizio
$script:cnUltima = ''       # ultima cena do rodizio (nao repete seguida)
$script:cnAgN = 0            # bolinhas da cena aguardando (1..3): ultimo agentsN > 0 visto (a saida ainda precisa dele)
$script:cnFam = ''          # familia de modo vista no quadro anterior
$script:cnModo = ''         # modo visto no quadro anterior
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

  if ($fam -eq 'off') { if ($c) { Cena-Fim $t }; return }

  # 0) depuracao: uma cena em laco
  if ($script:CN_DEBUG -and $script:CENAS[$script:CN_DEBUG]) {
    if (-not $c) {
      if ($script:CN_DEBUG -eq 'quadro') { Cena-Tocar 'quadro' $t -Voltas 4 }
      elseif ($script:CN_DEBUG -eq 'aguardando') { if ($script:cnAgN -lt 1) { $script:cnAgN = 3 }; Cena-Tocar 'aguardando' $t -Laco }
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
  if ($c -and $mudouFam -and $c.id -ne 'aterrissa' -and -not ($c.id -eq 'aguardando' -and $querAg)) {
    # o quadro sai girando; a aguardando pula (bolinhas voam para ele) quando o subagente acaba e ele fica parado; o resto some
    if ($c.id -eq 'quadro' -or ($c.id -eq 'aguardando' -and $fam -eq 'calmo')) { Cena-Parar $t } else { Cena-Fim $t; $c = $null }
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
  if ($mudouModo -and $mode -eq 'done') { Cena-Tocar 'plugue' $t; return }

  # 5b) subagentes ativos: aguardando (so comeca sem outra cena: inseto/plugue terminam antes e ela volta)
  if ($c -and $c.id -eq 'aguardando' -and $c.fase -ne 'sai' -and -not $querAg) { Cena-Parar $t; return }
  if ($querAg) {
    if (-not $c) { Cena-Tocar 'aguardando' $t -Laco }
    $script:cnProxOcioso = 0.0; return   # o rodizio do ocioso nao toca enquanto houver subagentes
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
