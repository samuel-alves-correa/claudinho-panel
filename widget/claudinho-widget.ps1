# Claudinho: notch preto na borda direita da tela (sempre no topo): mascote + linhas de uso (5 h, 7 d, contexto, subagentes).
# Passe o mouse num item para abrir o balao dele. Clique no mascote = reduz/expande (reduzido: so o mascote, com um ponto de aviso de limite). Arraste (vertical) = muda a posicao. Botao direito = menu.
# Le claudinho-state.json (escrito pelo mod) so quando o arquivo muda; anima com timer proprio.
# Variaveis de ambiente: CW_REDUCE_MOTION=1 (ou reduceMotion no estado) desliga pulso, giros e pulos do mascote.
#   CW_PIN=mascot|limits|ctx|sub inicia com o balao daquele item fixado (depuracao/capturas). CW_TOP=<px> forca a posicao vertical (depuracao). CW_COMPACT=0|1 forca expandido/reduzido (depuracao).
# A posicao (top) fica em %USERPROFILE%\.claude\claudinho-widget.json.
param([string]$StateFile = (Join-Path $PSScriptRoot '..\claudinho-state.json'))

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' -Name D -Namespace Cw
[void][Cw.D]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:S = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX / 96.0

# ---------- paleta ----------
$BLACK = '#000000'; $TEXT = '#faf9f5'; $DIM = '#a09d96'; $TRK = '#2a2a2a'; $LINE = '#262626'; $QUIET = '#3d3d3a'
$GRN = '#5fd38d'; $AMB = '#f5c542'; $RED = '#ff5f56'; $SUBC = '#6cc4e8'

$script:state = $null
$script:lastWrite = [datetime]::MinValue
$script:brushes = @{}
$script:pens = @{}
$script:sw = [System.Diagnostics.Stopwatch]::StartNew()
$script:lastMode = ''; $script:prevMode = ''; $script:codingEnd = 0.0; $script:introSkip = $false
$script:modeT0 = 0.0
$script:A = 255; $script:lastT = 0.0; $script:lastChk = -1.0
$script:lastAct = 0.0; $script:prevLoud = $false
$script:rm = $false; $script:reduce = ($env:CW_REDUCE_MOTION -eq '1')
# respeita "Efeitos de animacao" do Windows (SPI_GETCLIENTAREAANIMATION = 0x1042)
try {
  Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint a, uint b, ref int c, uint d);' -Name Sp -Namespace Cw
  $anim = 1
  if ([Cw.Sp]::SystemParametersInfo(0x1042, 0, [ref]$anim, 0) -and $anim -eq 0) { $script:reduce = $true }
} catch { }

# geometria do notch (px logicos)
$NW = 72.0; $FL = 24.0; $RAD = 18.0        # largura da faixa, alargamento concavo (expandido), raio dos cantos esquerdos
$FLC = 14.0; $MR = 32.0                    # alargamento no modo reduzido; raio do anel do mascote
$script:flare = $FL
$BWID = 250.0; $ARW = 12.0; $GAPW = 4.0    # balao: largura, comprimento da seta, vao ate a faixa
$script:items = New-Object System.Collections.ArrayList
$script:curH = 0.0; $script:tgtH = 0.0
$script:hov = ''; $script:pinned = ''; $script:alert = $false; $script:leaveAt = 0.0; $script:openKey = ''; $script:compact = $false
$script:balH = 0.0; $script:balKey = ''; $script:geo = $null; $script:shapeKey = ''
$script:down = $false; $script:moved = $false; $script:dirty = $false
$script:pt = [System.Globalization.CultureInfo]::GetCultureInfo('pt-BR')

function Br([string]$hex, [int]$a = 255) {
  $a = [int]([math]::Min(255, [math]::Round($a * $script:A / 255.0 / 16.0) * 16))
  if ($a -lt 16) { $a = 16 }
  $k = "$hex|$a"
  if (-not $script:brushes.ContainsKey($k)) {
    $c = [System.Drawing.ColorTranslator]::FromHtml($hex)
    $script:brushes[$k] = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($a, $c))
  }
  $script:brushes[$k]
}
function Pn([string]$hex, [single]$w, [int]$a = 255) {
  $a = [int]([math]::Min(255, [math]::Max(16, [math]::Round($a / 16.0) * 16)))
  $k = "$hex|$w|$a"
  if (-not $script:pens.ContainsKey($k)) {
    $c = [System.Drawing.ColorTranslator]::FromHtml($hex)
    $p = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($a, $c)), $w
    $p.StartCap = 'Round'; $p.EndCap = 'Round'; $p.LineJoin = 'Round'
    $script:pens[$k] = $p
  }
  $script:pens[$k]
}
function Rect($g, $hex, $x, $y, $w, $h, [int]$a = 255) { $g.FillRectangle((Br $hex $a), [single]$x, [single]$y, [single]$w, [single]$h) }

$script:pp = New-Object System.Collections.ArrayList
function RoundPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure(); [void]$script:pp.Add($p); $p   # o Paint descarta todos no final
}
# faixa encostada na direita: cantos esquerdos arredondados e alargamento concavo em cima e embaixo (funde com a borda)
function NotchPath([double]$x0, [double]$y0, [double]$w, [double]$h) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $r = $RAD; $f = $script:flare; $d = $r * 2; $rt = $x0 + $w; $yb = $y0 + $h - $f; $yt = $y0 + $f
  $p.AddArc([single]($rt - 2 * $f), [single]($y0 - $f), [single](2 * $f), [single](2 * $f), 0, 90)
  $p.AddLine([single]($rt - $f), [single]$yt, [single]($x0 + $r), [single]$yt)
  $p.AddArc([single]$x0, [single]$yt, [single]$d, [single]$d, 270, -90)
  $p.AddLine([single]$x0, [single]($yt + $r), [single]$x0, [single]($yb - $r))
  $p.AddArc([single]$x0, [single]($yb - $d), [single]$d, [single]$d, 180, -90)
  $p.AddLine([single]($x0 + $r), [single]$yb, [single]($rt - $f), [single]$yb)
  $p.AddArc([single]($rt - 2 * $f), [single]($y0 + $h - $f), [single](2 * $f), [single](2 * $f), 270, 90)
  $p.CloseFigure(); $p
}
# balao com seta para a direita (ponta em $ty)
function BalloonPath([double]$by, [double]$bh, [double]$ty) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $r = 16.0; $d = $r * 2; $ah = 9.0
  $p.AddArc([single]0, [single]$by, [single]$d, [single]$d, 180, 90)
  $p.AddArc([single]($BWID - $d), [single]$by, [single]$d, [single]$d, 270, 90)
  $p.AddLine([single]$BWID, [single]($ty - $ah), [single]($BWID + $ARW), [single]$ty)
  $p.AddLine([single]($BWID + $ARW), [single]$ty, [single]$BWID, [single]($ty + $ah))
  $p.AddArc([single]($BWID - $d), [single]($by + $bh - $d), [single]$d, [single]$d, 0, 90)
  $p.AddArc([single]0, [single]($by + $bh - $d), [single]$d, [single]$d, 90, 90)
  $p.CloseFigure(); $p
}

function F([string]$n,[double]$pt,$st='Regular'){ New-Object System.Drawing.Font($n,[single]($pt*96/72),[System.Drawing.FontStyle]$st,[System.Drawing.GraphicsUnit]::Pixel) }
$fHead = (F 'Segoe UI' 11 'Bold')
$fName = (F 'Segoe UI' 8.5 'Bold')
$fBody = (F 'Segoe UI' 9.5)
$fSmall = (F 'Segoe UI' 9)
$fRing = (F 'Segoe UI' 9 'Bold')
$fPct = (F 'Segoe UI' 10 'Bold')
$fNum = (F 'Segoe UI' 13 'Bold')
$fMono = (F 'Consolas' 9)
$fMonoB = (F 'Consolas' 11 'Bold')
$center = New-Object System.Drawing.StringFormat; $center.Alignment = 'Center'; $center.FormatFlags = 'NoWrap'
$mid = New-Object System.Drawing.StringFormat; $mid.Alignment = 'Center'; $mid.LineAlignment = 'Center'; $mid.FormatFlags = 'NoWrap'
$left = New-Object System.Drawing.StringFormat; $left.FormatFlags = 'NoWrap'
$right = New-Object System.Drawing.StringFormat; $right.Alignment = 'Far'; $right.FormatFlags = 'NoWrap'
# superficie so para medir texto fora do Paint (altura do balao)
$script:mg = [System.Drawing.Graphics]::FromImage((New-Object System.Drawing.Bitmap 1, 1))
$script:mg.TextRenderingHint = 'ClearTypeGridFit'

function Dur($ms) {
  $t = [int][math]::Max(0, [math]::Floor($ms / 1000)); $m = [int][math]::Floor($t / 60)
  if ($m -ge 60) { '{0}h{1:00}' -f [math]::Floor($m / 60), ($m % 60) } else { '{0}:{1:00}' -f $m, ($t % 60) }
}
# tempo relativo curto: agora / 2 min / 1 h
function Rel($nowMs, $t) { $d = [math]::Max(0, ($nowMs - [double]$t) / 1000); if ($d -lt 5) { 'agora' } elseif ($d -lt 60) { '{0} s' -f [math]::Floor($d) } elseif ($d -lt 3600) { '{0} min' -f [math]::Floor($d / 60) } else { '{0} h' -f [math]::Floor($d / 3600) } }
# numero curto sem casas inuteis: 70k, 1M
function KS($n) { if ($n -ge 1e6) { '{0:0.#}M' -f ($n / 1e6) } elseif ($n -ge 1e3) { '{0:0}k' -f ($n / 1e3) } else { "$n" } }
function K($n) { if ($n -ge 1e6) { '{0:N2}M' -f ($n / 1e6) } elseif ($n -ge 1e3) { '{0:N1}k' -f ($n / 1e3) } else { "$n" } }
# "reinicia em 51 min" / "reinicia em 3 h 20 min" / "reinicia qui 00:00"
function ResetTxt($ms, $nowMs) {
  if (-not $ms -or [double]$ms -le 0) { return '' }
  $d = ([double]$ms - $nowMs) / 60000.0
  if ($d -le 0) { return 'reiniciando' }
  if ($d -lt 60) { return ('reinicia em {0} min' -f [math]::Ceiling($d)) }
  if ($d -lt 1440) { $hh = [math]::Floor($d / 60); $mm = [math]::Floor($d % 60); if ($mm -gt 0) { return ('reinicia em {0} h {1} min' -f $hh, $mm) } else { return ('reinicia em {0} h' -f $hh) } }
  $dt = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$ms).LocalDateTime
  $dias = 'dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'
  'reinicia {0} {1:HH:mm}' -f $dias[[int]$dt.DayOfWeek], $dt
}
function BandCol($p) { if ($p -le 65) { $GRN } elseif ($p -le 85) { $AMB } else { $RED } }
# corta pelo tamanho real do texto (g so existe no Paint, entao vem por parametro)
function ClipW($g, [string]$s, $font, [double]$max) {
  if ($g.MeasureString($s, $font).Width -le $max) { return $s }
  $t2 = $s
  while ($t2.Length -gt 1 -and $g.MeasureString($t2 + '…', $font).Width -gt $max) { $t2 = $t2.Substring(0, $t2.Length - 1) }
  $t2 + '…'
}

function Mix([string]$a, [string]$b, [double]$k) {
  $x = [System.Drawing.ColorTranslator]::FromHtml($a); $y = [System.Drawing.ColorTranslator]::FromHtml($b)
  '#{0:x2}{1:x2}{2:x2}' -f [int]($x.R + ($y.R - $x.R) * $k), [int]($x.G + ($y.G - $x.G) * $k), [int]($x.B + ($y.B - $x.B) * $k)
}

# ---------- o bichinho (pixel-art como no app do Claude), animado por tempo ----------
# Poses: de frente, virando, agachado. Unico adereço: o notebook no Codando (o anel ao redor comunica o estado).
function Draw-Mascot($g, [single]$cx, [single]$gy, [single]$p, $s, [double]$t, [double]$age, [double]$range) {
  $mode = [string]$s.mode; $loud = [bool]$s.loud
  $B = [string]$s.palette.B; $D = [string]$s.palette.D
  $shade = Mix $B $D 0.4; $deep = Mix $D '#1c1410' 0.6
  $u = [math]::Max(1.0, [math]::Round(2.0 * $p * $script:S)) / $script:S    # alinhado ao pixel do dispositivo; 1 "pixel" do bichinho; corpo de frente = 16 x 16 pixels (+ bracos)
  $ox = 0.0; $oy = 0.0; $sy = 1.0; $wf = 0.0
  $pose = 'front'; $eyes = 'open'; $eyY = (-14.0); $eyX = 0.0
  $armL = 0.0; $armR = 0.0   # deslocamento vertical dos bracos em pixels (negativo = sobe)
  $stk = ''; $mouth = $false
  $prev = [string]$script:prevMode

  if ($mode -eq 'coding') {
    # sequencia do video: de frente -> vira -> levanta o braco -> abaixa -> agacha e escreve
    $a = if ($script:introSkip) { 99.0 } else { $age }
    if     ($a -lt 0.30) { $pose = 'front' }
    elseif ($a -lt 0.55) { $pose = 'turn' }
    elseif ($a -lt 0.75) { $pose = 'front'; $armL = (-2.0); $stk = 'raise' }
    elseif ($a -lt 1.20) { $pose = 'front'; $armL = (-4.0); $stk = 'up' }
    elseif ($a -lt 1.45) { $pose = 'front'; $stk = 'diag' }
    elseif ($a -lt 1.75) { $pose = 'turn2'; $stk = 'L'; $ox = 3.0 * $u }
    else {
      $pose = 'crouch'; $stk = 'L'; $wf = 15; $ox = 3.0 * $u   # abre espaco a esquerda para o notebook
      $oy = -[math]::Abs([math]::Sin($t * 15)) * 0.3 * $u
      $mouth = (([int][math]::Floor($t * 6)) % 2 -eq 0)
    }
  } elseif ($prev -eq 'coding' -and $age -lt 0.36) {
    # saindo do Codando: levanta, vira e volta de frente
    if ($age -lt 0.18) { $pose = 'turn2'; $stk = 'L'; $ox = 3.0 * $u } else { $pose = 'turn' }
  } else {
    switch ($mode) {
      'idle' { $sy = 1 + 0.02 * [math]::Sin($t * 1.6); $eyes = 'closed' }
      'thinking' { $ox = [math]::Sin($t * 0.6) * $range * 0.5; $wf = 4; $eyY = (-15.5); $eyX = (-0.5) }
      'reading' { $ox = [math]::Sin($t * 0.9) * $range * 0.6; $wf = 6; $eyX = 0.6; $eyY = (-13.5) }
      'waiting' {
        if ($loud) { $hp = $(if ($script:rm) { 0.0 } else { [math]::Abs([math]::Sin($t * 4.2)) }); $oy = -$hp * 4 * $p; $sy = 0.92 + 0.15 * $hp; $armL = (-4.0); $armR = (-4.0) }
        else { $still = ($script:rm -or $age -gt 3.0); $hp = $(if ($still) { 0.0 } else { [math]::Abs([math]::Sin($t * 2)) }); $oy = -$hp * 1.5 * $p; if (-not $still -and [math]::Sin($t * 5) -gt 0) { $armL = (-4.0) } }
      }
      'done' { if ($age -lt 0.7) { $oy = -[math]::Abs([math]::Sin($age * 4.5)) * 5 * $p }; $eyes = 'happy'; $armL = (-4.0); $armR = (-4.0) }
      'error' { $ox = 1.4 * $p * [math]::Sin($age * 38) * [math]::Max(0, 1 - $age / 0.9); $eyes = 'x' }
    }
  }
  if ($eyes -eq 'open' -and ($t % 3.7) -lt 0.13) { $eyes = 'closed' }

  $mx = $cx + $ox
  # sombra
  $shW = 26 * $u * (1 + $oy / (30 * $p)); $g.FillEllipse((Br '#000000' 70), [single]($mx - $shW / 2), [single]($gy - 0.4 * $p), [single]$shW, [single](2.4 * $p))

  $st = $g.Save()
  $g.TranslateTransform([single]$mx, [single]($gy + $oy)); $g.ScaleTransform(1, [single]$sy)
  $g.SmoothingMode = 'None'
  function U($hex, $x, $y, $w, $h) { Rect $g $hex ($x * $u) ($y * $u) ($w * $u) ($h * $u) }
  $ink = '#0b0b0b'

  # pernas (4, como no video); no agachado ficam mais curtas e com pezinho
  $lx = -8, -4, 2, 6
  $legH = $(if ($pose -eq 'crouch') { 3.0 } else { 4.0 })
  for ($i = 0; $i -lt 4; $i++) {
    $lf = 0.0
    if ($wf -gt 0) { $ph = $t * $wf + $(if ($i % 2 -eq 1) { [math]::PI } else { 0 }); $lf = [math]::Max(0, [math]::Sin($ph)) * 1.1 }
    U $B $lx[$i] (-$legH) 2 ($legH - $lf)
    if ($pose -eq 'crouch' -and $lf -lt 0.3) { U $B ($lx[$i] + 2) (-1) 1 1 }
  }

  # corpo
  switch ($pose) {
    'front' {
      U $B (-8) (-16) 16 12; U $shade (-8) (-4.8) 16 0.8
      # braco levantado = "L" (ombro + haste p/ cima), nao um bloco colado no topo da cabeca
      if ($armL -lt 0 -and $stk -eq '') { U $B (-12) (-12) 4 2; U $B (-12) (-12 + $armL) 2 (2 - $armL) } else { U $B (-12) (-12 + $armL) 4 4 }
      if ($armR -lt 0 -and $stk -eq '') { U $B 8 (-12) 4 2; U $B 10 (-12 + $armR) 2 (2 - $armR) } else { U $B 8 (-12 + $armR) 4 4 }
      $eyeList = @(@((-6 + $eyX), $eyY, 2, 2), @((4 + $eyX), $eyY, 2, 2))
    }
    'turn' {
      U $B (-8) (-16) 16 12; U $shade (-8) (-4.8) 16 0.8
      U $B 8 (-13) 4 5; U $B (-11) (-8) 3 4
      $eyeList = @(@(-6, -12, 2, 2), @(3, -11, 3, 0.8))
    }
    'turn2' {
      U $B (-8) (-15) 16 11; U $shade 5.6 (-15) 2.4 11
      U $B (-9.5) (-18) 5 4; U $B 0.8 (-18) 4.5 4
      $eyeList = @(@(-7, -11, 2, 2), @(3, -11, 2, 2))
    }
    'crouch' {
      U $B (-8) (-14) 16 11; U $shade 4 (-14) 4 11
      U $B (-12) (-9) 4 5.5; U $shade (-12) (-9) 4 2
      if ($mouth) { U $deep (-12) (-6) 4 0.6 }
      $eyeList = @(@(-8, -11, 2, 2), @(0, -11, 2, 2))
    }
  }
  # olhos
  foreach ($e2 in $eyeList) {
    $ex = $e2[0]; $ey = $e2[1]; $ew = $e2[2]; $eh = $e2[3]
    $ec = $eyes
    if ($eh -lt 1) { $ec = 'dash' }
    switch ($ec) {
      'open' { U $ink $ex $ey $ew $eh }
      'dash' { U $ink $ex $ey $ew $eh }
      'closed' { U $ink $ex ($ey + 1) 2 0.7 }
      'happy' { U $ink ($ex - 0.3) ($ey + 1.5) 1 1; U $ink ($ex + 0.5) ($ey + 0.5) 1 1; U $ink ($ex + 1.3) ($ey + 1.5) 1 1 }
      'x' {
        U '#3a0f0b' $ex $ey 0.7 0.7; U '#3a0f0b' ($ex + 1.3) $ey 0.7 0.7; U '#3a0f0b' ($ex + 0.65) ($ey + 0.65) 0.7 0.7
        U '#3a0f0b' $ex ($ey + 1.3) 0.7 0.7; U '#3a0f0b' ($ex + 1.3) ($ey + 1.3) 0.7 0.7
      }
    }
  }
  # notebook visto de lado (so no Codando): base com teclado + tampa em pe, com a tela acesa virada para o bichinho
  if ($stk -eq 'L') {
    U '#9aa0a8' (-17) (-4) 7 1
    U '#6b7078' (-17) (-10) 1.2 6
    $glow = $(if ($script:rm -or $pose -ne 'crouch') { '#cfe8ff' } elseif (([int][math]::Floor($t * 3)) % 2 -eq 0) { '#cfe8ff' } else { '#9fd0f5' })
    U $glow (-15.8) (-9.4) 0.7 4.8
  }
  $g.Restore($st)
  $g.SmoothingMode = 'AntiAlias'
}

# ---------- itens da faixa ----------
function Find-Item([string]$key) {
  foreach ($it in $script:items) { if ($it.k -eq $key) { return $it } }
  if ($key -eq 'five_hour') { return (Find-Item 'seven_day') }
  if ($key -eq 'seven_day') { return (Find-Item 'five_hour') }
  $null
}
function Get-Limit($cur, [string]$kind) {
  if (-not $cur) { return $null }
  foreach ($l in @($cur.limits)) {
    if ($l -and $l.kind -eq $kind -and $null -ne $l.pct) {
      # a janela ja reiniciou e ainda nao veio leitura nova: o valor antigo nao vale mais
      if ($l.resetsAt -and [double]$l.resetsAt -gt 0 -and [double]$l.resetsAt -lt [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) { return [pscustomobject]@{ kind = $kind; pct = 0.0; resetsAt = 0 } }
      return $l
    }
  }
  $null
}
# cor do aviso no modo reduzido: o maior entre 5 h, 7 d e contexto ('' = sem aviso)
function Warn-Col($cur) {
  if (-not $cur) { return '' }
  $mx = 0.0
  foreach ($kd in 'five_hour', 'seven_day') { $l = Get-Limit $cur $kd; if ($l) { $mx = [math]::Max($mx, [double]$l.pct) } }
  if ($null -ne $cur.ctxPct) { $mx = [math]::Max($mx, [double]$cur.ctxPct) }
  if ($mx -gt 85) { $RED } elseif ($mx -ge 75) { $AMB } else { '' }
}
function Rebuild-Items {
  $cur = $script:state
  $script:items.Clear()
  # reduzido: so a bolinha do mascote, sem o nome do estado (a cor do anel ja diz), com menos folga e alargamento menor
  $script:flare = $(if ($script:compact) { $FLC } else { $FL })
  $padV = $(if ($script:compact) { 7.0 } else { 14.0 })
  $mh = $(if ($script:compact) { 2 * $MR + 4 } else { 2 * $MR + 24 })
  $y = $script:flare + $padV
  $lastGap = 12.0
  [void]$script:items.Add(@{ k = 'mascot'; bal = 'mascot'; y = $y; h = $mh; cy = ($y + $MR + 2); pad = 6.0 }); $y += $mh + $lastGap
  # expandido: bloco de uso em linhas (rotulo, valor e barra fina); o detalhe fica no balao
  if (-not $script:compact) {
    $rows = New-Object System.Collections.ArrayList
    foreach ($kd in 'five_hour', 'seven_day') { if (Get-Limit $cur $kd) { [void]$rows.Add(@($kd, 'limits')) } }
    if ($cur) { [void]$rows.Add(@('ctx', 'ctx')) }
    if (@($cur.agents | Where-Object { $_ }).Count -gt 0) { [void]$rows.Add(@('sub', 'sub')) }
    if ($rows.Count -gt 0) { $y += 4 }   # folga da linha separadora
    foreach ($rw in $rows) {
      [void]$script:items.Add(@{ k = $rw[0]; bal = $rw[1]; y = $y; h = 22.0; cy = ($y + 11.0); pad = 4.0; row = $true })
      $lastGap = 8.0; $y += 22 + $lastGap
    }
  }
  $script:tgtH = $y - $lastGap + $padV + $script:flare
  if ($script:curH -le 0) { $script:curH = $script:tgtH }
}

# ---------- balao: mede (dr = $false) ou desenha (dr = $true) e devolve a altura ----------
$script:dr = $false
function Tx($g, [string]$s, $font, [string]$hex, [double]$x, [double]$y, [double]$w = 0, $fmt = $null) {
  if (-not $script:dr) { return }
  if ($w -le 0) { $g.DrawString($s, $font, (Br $hex), [single]$x, [single]$y); return }
  $rc = [System.Drawing.RectangleF]::new([single]$x, [single]$y, [single]$w, [single]($font.Height + 6))
  $g.DrawString($s, $font, (Br $hex), $rc, $(if ($fmt) { $fmt } else { $left }))
}
function Bar($g, [double]$x, [double]$y, [double]$w, $pct, [string]$hex) {
  if (-not $script:dr) { return }
  $g.FillPath((Br $TRK), (RoundPath $x $y $w 6 3))
  if ($null -ne $pct -and [double]$pct -gt 0) {
    $fw = [math]::Max(6, $w * [math]::Min(100, [double]$pct) / 100)
    $g.FillPath((Br $hex), (RoundPath $x $y $fw 6 3))
  }
}
function Sep($g, [double]$y) { if ($script:dr) { Rect $g $LINE 16 $y 218 1 } }

function Draw-Balloon($g, [string]$bal, [bool]$dr, [double]$nowMs) {
  $script:dr = $dr
  $cur = $script:state; $y = 14.0; $cw = 218.0
  if (-not $cur) { Tx $g 'Aguardando o Claude Code…' $fBody $DIM 16 $y; return ($y + 22 + 14) }
  switch ($bal) {
    'mascot' {
      $nm = [string]$cur.name; if (-not $nm) { $nm = 'Claudinho' }
      $ncol = $(if ($cur.mode -eq 'idle' -or -not $cur.color) { $TEXT } else { [string]$cur.color })
      Tx $g $nm $fHead $ncol 16 $y
      $nw = $g.MeasureString($nm, $fHead).Width - 4
      $proj = [string]$cur.project
      if ($proj -and ($cw - $nw - 8) -gt 30) { Tx $g (ClipW $g $proj $fBody ($cw - $nw - 8)) $fBody $DIM (16 + $nw + 8) ($y + 2) ($cw - $nw - 8) }
      $y += 26
      if ($cur.mode -eq 'waiting') {
        $main = [string]$cur.ask; if (-not $main) { $main = [string]$cur.label }
        Tx $g (ClipW $g $main $fBody $cw) $fBody $TEXT 16 $y $cw; $y += 20
        if ($cur.waitSince -and [double]$cur.waitSince -gt 0) { Tx $g ('aguardando há ' + (Dur ($nowMs - [double]$cur.waitSince))) $fSmall $DIM 16 $y; $y += 18 }
      } else {
        Tx $g (ClipW $g ([string]$cur.label) $fBody $cw) $fBody $DIM 16 $y $cw; $y += 22
      }
      Sep $g ($y + 2); $y += 10
      Tx $g 'Modelo' $fSmall $DIM 16 ($y + 1)
      $mdl = [string]$cur.model; if (-not $mdl) { $mdl = '—' }
      Tx $g (ClipW $g $mdl $fBody 150) $fBody $TEXT 16 $y $cw $right; $y += 22
      $turn = $(if ($cur.mode -in 'thinking', 'coding', 'reading', 'error' -and $cur.turnStart -and [double]$cur.turnStart -gt 0) { Dur ($nowMs - [double]$cur.turnStart) } else { '—' })
      $sdur = $(if ($cur.sessionStart -and [double]$cur.sessionStart -gt 0) { Dur ($nowMs - [double]$cur.sessionStart) } else { '—' })
      Tx $g ('sessão {0} · turno {1}' -f $sdur, $turn) $fSmall $DIM 16 $y; $y += 22
      if ($script:compact) {
        # reduzido: os aneis estao escondidos, entao o resumo deles vem aqui
        $parts = @()
        $l5 = Get-Limit $cur 'five_hour'; if ($l5) { $parts += ('5h {0}%' -f [math]::Round([double]$l5.pct)) }
        $l7 = Get-Limit $cur 'seven_day'; if ($l7) { $parts += ('7d {0}%' -f [math]::Round([double]$l7.pct)) }
        if ($null -ne $cur.ctxPct) { $parts += ('ctx {0}%' -f [math]::Round([double]$cur.ctxPct)) }
        $nsub = @($cur.agents | Where-Object { $_ }).Count; if ($nsub -gt 0) { $parts += ('{0} sub' -f $nsub) }
        if ($parts.Count -gt 0) { Tx $g (ClipW $g ($parts -join ' · ') $fSmall $cw) $fSmall $TEXT 16 $y $cw; $y += 22 }
      }
      Sep $g ($y + 2); $y += 10
      Tx $g 'ATIVIDADE RECENTE' $fSmall $DIM 16 $y; $y += 20
      $hist = @($cur.history | Where-Object { $_ } | Select-Object -First 3)
      if ($hist.Count -eq 0) { Tx $g 'nada ainda' $fSmall $DIM 16 $y; $y += 18 }
      foreach ($hi in $hist) {
        Tx $g (Rel $nowMs $hi.t) $fMono $DIM 16 $y
        Tx $g (ClipW $g ([string]$hi.text) $fSmall ($cw - 50)) $fSmall $TEXT 66 ($y + 1) ($cw - 50)
        $y += 18
      }
    }
    'limits' {
      Tx $g 'Limites de uso' $fHead $TEXT 16 $y; $y += 28
      $first = $true
      foreach ($spec in @(@('five_hour', 'Sessão de 5 h'), @('seven_day', 'Semana'), @('spend_limit', 'Limite de gasto'))) {
        $lm = Get-Limit $cur $spec[0]
        if (-not $lm) { continue }
        if (-not $first) { $y += 8 }; $first = $false
        $pc = [double]$lm.pct
        Tx $g $spec[1] $fBody $TEXT 16 $y
        $rt = ResetTxt $lm.resetsAt $nowMs
        if ($rt) { Tx $g $rt $fSmall $DIM 16 ($y + 1) $cw $right }
        $y += 22
        Bar $g 16 $y $cw $pc (BandCol $pc); $y += 14
        Tx $g ('{0}% usado' -f [math]::Round($pc)) $fSmall $DIM 16 $y; $y += 18
      }
    }
    'ctx' {
      Tx $g 'Contexto' $fHead $TEXT 16 $y; $y += 28
      $cx0 = $cur.ctxPct
      if ($null -ne $cx0) {
        Tx $g ('{0}%' -f [math]::Round($cx0)) $fMonoB $TEXT 16 $y
        if ($null -ne $cur.ctxTok -and $null -ne $cur.ctxWin) { Tx $g ((KS $cur.ctxTok) + ' / ' + (KS $cur.ctxWin)) $fSmall $DIM 16 ($y + 2) $cw $right }
      } else { Tx $g 'sem dados' $fSmall $DIM 16 ($y + 2) }
      $y += 24
      Bar $g 16 $y $cw $cx0 $(if ($null -ne $cx0) { BandCol ([double]$cx0) } else { $DIM }); $y += 18
      Sep $g $y; $y += 10
      $tk = $cur.tokens
      $usdT = $(if ($null -ne $cur.usd) { '$' + ([double]$cur.usd).ToString('N2', $script:pt) } else { '—' })
      $cols = @(@('entrada', $(if ($tk) { K $tk.in } else { '—' })), @('saída', $(if ($tk) { K $tk.out } else { '—' })), @('custo', $usdT))
      for ($i = 0; $i -lt 3; $i++) {
        Tx $g $cols[$i][1] $fMonoB $TEXT (16 + $i * 76) $y
        Tx $g $cols[$i][0] $fSmall $DIM (16 + $i * 76) ($y + 17)
      }
      $y += 40
      if ($tk) { Tx $g ('cache ' + (K $tk.cache)) $fSmall $DIM 16 $y } else { Tx $g 'tokens aparecem após o 1º turno' $fSmall $DIM 16 $y }
      $y += 22
      Sep $g $y; $y += 10
      Tx $g 'FERRAMENTAS' $fSmall $DIM 16 $y; $y += 20
      # chips: ate 2 linhas; o que nao couber vira "+N" (nunca some em silencio)
      $chips = New-Object System.Collections.ArrayList
      $row = 0; $x = 16.0; $over = 0; $lim = 250 - 16
      foreach ($tp in @($cur.top | Where-Object { $_ })) {
        if ($over -gt 0) { $over++; continue }
        $ct = '{0} ×{1}' -f $tp[0], $tp[1]
        $cwid = $g.MeasureString($ct, $fSmall).Width + 8
        if ($x + $cwid -gt $lim -and $x -gt 16) { $row++; $x = 16.0 }
        if ($row -ge 2) { $over = 1; continue }
        [void]$chips.Add(@($ct, $row, $x, $cwid)); $x += $cwid + 6
      }
      while ($over -gt 0 -and $chips.Count -gt 0) {
        $lt = '+' + $over; $lw = $g.MeasureString($lt, $fSmall).Width + 8
        $lc = $chips[$chips.Count - 1]
        if (($lc[2] + $lc[3] + 6 + $lw) -le $lim) { [void]$chips.Add(@($lt, $lc[1], ($lc[2] + $lc[3] + 6), $lw)); break }
        $chips.RemoveAt($chips.Count - 1); $over++
      }
      if ($chips.Count -eq 0) { Tx $g 'nenhuma ainda' $fSmall $DIM 16 $y; $y += 20 }
      else {
        $nrow = 1
        foreach ($ch in $chips) {
          if ($ch[1] + 1 -gt $nrow) { $nrow = $ch[1] + 1 }
          $cyy = $y + $ch[1] * 26
          if ($script:dr) { $g.FillPath((Br '#262626'), (RoundPath $ch[2] $cyy $ch[3] 22 11)) }
          Tx $g $ch[0] $fSmall $DIM ($ch[2] + 4) ($cyy + 3)
        }
        $y += 22 + ($nrow - 1) * 26
      }
    }
    'sub' {
      $ags = @($cur.agents | Where-Object { $_ })
      Tx $g ('Subagentes · ' + $ags.Count) $fHead $TEXT 16 $y; $y += 28
      $shown = 0
      foreach ($ag in $ags) {
        if ($shown -ge 5) { break }
        $am = [string]$ag.model; $amw = 0
        if ($am) { $am = ClipW $g $am $fSmall 80; $amw = $g.MeasureString($am, $fSmall).Width + 6; Tx $g $am $fSmall $DIM 16 ($y + 1) $cw $right }
        $ad = [string]$ag.desc; if (-not $ad) { $ad = [string]$ag.type }
        Tx $g (ClipW $g $ad $fBody ($cw - $amw)) $fBody $TEXT 16 $y ($cw - $amw)
        $y += 22; $shown++
      }
      if ($ags.Count -gt 5) { Tx $g ('+' + ($ags.Count - 5) + ' em andamento') $fSmall $DIM 16 $y; $y += 20 }
    }
  }
  $y + 12
}

# ---------- janela ----------
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'; $form.TopMost = $true; $form.ShowInTaskbar = $false
$form.StartPosition = 'Manual'; $form.BackColor = [System.Drawing.ColorTranslator]::FromHtml($BLACK)
$form.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($form, $true)
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$script:top = $wa.Top + 70 * $script:S
# config salva (so top)
$CFG = "$env:USERPROFILE\.claude\claudinho-widget.json"
try {
  if (Test-Path -LiteralPath $CFG) {
    $sv = Get-Content -LiteralPath $CFG -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -ne $sv.top -and [double]$sv.top -ge $wa.Top -and [double]$sv.top -le ($wa.Bottom - 60)) { $script:top = [double]$sv.top }
    if ($null -ne $sv.compact) { $script:compact = [bool]$sv.compact }
  }
} catch { }
if ($env:CW_TOP) { try { $script:top = [double]$env:CW_TOP } catch { } }
if ($env:CW_COMPACT) { $script:compact = ($env:CW_COMPACT -eq '1') }
function Save-Cfg {
  try {
    $d = Split-Path -Parent $CFG
    if (-not (Test-Path -LiteralPath $d)) { $null = New-Item -ItemType Directory -Path $d -Force }
    (@{ top = [int]$script:top; compact = [bool]$script:compact } | ConvertTo-Json -Compress) | Set-Content -LiteralPath $CFG -Encoding UTF8
  } catch { }
}
$pinMap = @{ mascot = 'mascot'; limits = 'five_hour'; ctx = 'ctx'; sub = 'sub' }
if ($env:CW_PIN -and $pinMap.ContainsKey($env:CW_PIN)) { $script:pinned = $pinMap[$env:CW_PIN] }

# calcula a geometria (janela + faixa + balao) e so recria a Region quando a forma muda
function Apply-Geo {
  $k = $script:S
  $shPx = [int][math]::Round($script:curH * $k)
  $script:top = [math]::Max($wa.Top, [math]::Min($script:top, $wa.Bottom - $shPx))
  $topPx = [int][math]::Round($script:top)
  $nwPx = [int][math]::Round($NW * $k)
  $it = $null; if ($script:openKey) { $it = Find-Item $script:openKey }
  $balPx = 0; $bTop = 0; $tipPx = 0
  if ($it) {
    $balPx = [int][math]::Round($script:balH * $k)
    $iyPx = $topPx + [int][math]::Round($it.cy * $k)
    $pad = [int][math]::Round(($RAD + 9) * $k)
    $bTop = $iyPx - [int]($balPx / 2)
    $bTop = [math]::Max($iyPx - $balPx + $pad, [math]::Min($bTop, $iyPx - $pad))
    $bTop = [math]::Max($wa.Top + 4, [math]::Min($bTop, $wa.Bottom - 4 - $balPx))
    $tipPx = [math]::Max($bTop + $pad, [math]::Min($iyPx, $bTop + $balPx - $pad))
  }
  $wy = $topPx; $wb = $topPx + $shPx
  if ($it) { $wy = [math]::Min($wy, $bTop); $wb = [math]::Max($wb, $bTop + $balPx) }
  $wPx = $(if ($it) { [int][math]::Round(($BWID + $ARW + $GAPW + $NW) * $k) } else { $nwPx })
  $hPx = $wb - $wy
  $bx = '{0}|{1}|{2}|{3}' -f ($wa.Right - $wPx), $wy, $wPx, $hPx
  if ($bx -ne $script:boundsKey) { $script:boundsKey = $bx; $form.SetBounds($wa.Right - $wPx, $wy, $wPx, $hPx) }
  $script:geo = @{
    lw = $wPx / $k; lh = $hPx / $k; sx = ($wPx - $nwPx) / $k; sy = ($topPx - $wy) / $k; sh = $shPx / $k
    open = [bool]$it; by = ($bTop - $wy) / $k; bh = $balPx / $k; tipY = ($tipPx - $wy) / $k; item = $it
  }
  $sk = '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}' -f $wPx, $hPx, ($topPx - $wy), $shPx, ($bTop - $wy), $balPx, ($tipPx - $wy), $script:flare
  if ($sk -ne $script:shapeKey) {
    $script:shapeKey = $sk
    $geo = $script:geo
    $m = New-Object System.Drawing.Drawing2D.Matrix; $m.Scale([single]$k, [single]$k)
    $sp = NotchPath $geo.sx $geo.sy $NW $geo.sh; $sp.Transform($m)
    $rg = New-Object System.Drawing.Region $sp
    if ($geo.open) { $bp = BalloonPath $geo.by $geo.bh $geo.tipY; $bp.Transform($m); $rg.Union($bp); $bp.Dispose() }
    $oldR = $form.Region; $form.Region = $rg
    if ($oldR) { $oldR.Dispose() }
    $sp.Dispose(); $m.Dispose()
  }
}
$script:boundsKey = ''

function Hit-Item([double]$lx, [double]$ly) {
  $geo = $script:geo
  if (-not $geo -or $lx -lt $geo.sx) { return $null }
  foreach ($it in $script:items) {
    if ($ly -ge ($geo.sy + $it.y - $it.pad) -and $ly -le ($geo.sy + $it.y + $it.h + $it.pad)) { return $it }
  }
  $null
}

$form.Add_MouseDown({
  if ($_.Button -eq 'Left' -and ($_.X / $script:S) -ge $script:geo.sx) {
    $script:down = $true; $script:moved = $false
    $script:downY = [System.Windows.Forms.Cursor]::Position.Y; $script:topDown = $script:top
    $script:downHit = Hit-Item ($_.X / $script:S) ($_.Y / $script:S)
  }
})
$form.Add_MouseMove({
  if ($script:down) {
    $d = [System.Windows.Forms.Cursor]::Position.Y - $script:downY
    if ([math]::Abs($d) -gt 3 -or $script:moved) { $script:moved = $true; $script:top = $script:topDown + $d; Apply-Geo }
    return
  }
  $lx = $_.X / $script:S; $ly = $_.Y / $script:S
  $hit = Hit-Item $lx $ly
  $script:leaveAt = 0.0
  if ($hit) { $script:hov = $hit.k; $form.Cursor = [System.Windows.Forms.Cursors]::Hand }
  else { $form.Cursor = [System.Windows.Forms.Cursors]::Default }
})
function Toggle-Compact { $script:compact = -not $script:compact; $script:balKey = ''; Rebuild-Items; Save-Cfg }
$form.Add_MouseUp({
  if ($_.Button -eq 'Left' -and $script:down) {
    if ($script:moved) { $script:dirty = $true; Save-Cfg }
    elseif ($script:downHit -and [string]$script:downHit.k -eq 'mascot') { Toggle-Compact }   # clique no mascote: reduz / expande
  }
  $script:lastAct = $script:sw.Elapsed.TotalSeconds
  $script:down = $false; $script:moved = $false; $script:downHit = $null
})
$form.Add_FormClosing({ if ($script:dirty) { Save-Cfg } })
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$null = $menu.Items.Add('Expandir / reduzir', $null, { Toggle-Compact })
$null = $menu.Items.Add('Fixar balão aberto / soltar', $null, {
  if ($script:pinned) { $script:pinned = '' } else { $script:pinned = $(if ($script:openKey) { $script:openKey } else { 'mascot' }) }
})
$null = $menu.Items.Add('Fechar', $null, { $form.Close() })
$form.ContextMenuStrip = $menu

# anel de progresso: trilho + arco (a partir do topo, sentido horario)
function Ring($g, [double]$cx, [double]$cy, [double]$r, [double]$w, [string]$hex, [int]$a = 255) {
  $g.DrawEllipse((Pn $hex ([single]$w) $a), [single]($cx - $r), [single]($cy - $r), [single](2 * $r), [single](2 * $r))
}
function Arc($g, [double]$cx, [double]$cy, [double]$r, [double]$w, [string]$hex, [double]$start, [double]$sweep) {
  $g.DrawArc((Pn $hex ([single]$w)), [single]($cx - $r), [single]($cy - $r), [single](2 * $r), [single](2 * $r), [single]$start, [single]$sweep)
}

$form.Add_Paint({ try {
  $g = $_.Graphics
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
  $g.Clear([System.Drawing.ColorTranslator]::FromHtml($BLACK))
  $g.ScaleTransform($script:S, $script:S)
  $geo = $script:geo
  if (-not $geo) { return }
  $t = $script:sw.Elapsed.TotalSeconds
  $script:A = 255
  $cur = $script:state
  if (-not $cur) {
    $cur = [pscustomobject]@{ mode = 'idle'; loud = $false; name = 'Ocioso'; short = 'Ocioso'; color = '#7d7a76'; palette = [pscustomobject]@{ B = '#d97757'; D = '#a8553a' } }
  }
  if ($cur.mode -ne $script:lastMode) {
    if ($script:lastMode -eq 'coding') { $script:codingEnd = $t }
    $script:introSkip = ($cur.mode -eq 'coding' -and $script:codingEnd -gt 0 -and ($t - $script:codingEnd) -lt 8)
    $script:prevMode = $script:lastMode; $script:lastMode = $cur.mode; $script:modeT0 = $t
  }
  $age = $t - $script:modeT0
  $mode = [string]$cur.mode
  $script:rm = ($script:reduce -or ($cur.reduceMotion -eq $true))
  $loudWait = ($mode -eq 'waiting' -and $cur.loud)
  # pulsa ~3 ciclos ao entrar no loud e depois fica fixo na intensidade alta
  $pulse = 1.0
  if ($loudWait -and -not $script:rm -and $age -lt (3 * [math]::PI / 4.2)) { $pulse = [math]::Abs([math]::Sin($t * 4.2)) }
  $spinA = $(if ($script:rm) { -90.0 } else { ($t * 240) % 360 })

  # faixa
  $sp = NotchPath $geo.sx $geo.sy $NW $geo.sh
  $g.FillPath((Br $BLACK), $sp); $sp.Dispose()
  $ccx = $geo.sx + $NW / 2

  $sepDone = $false
  foreach ($it in $script:items) {
    $iy = $geo.sy + $it.y; $icy = $geo.sy + $it.cy
    $isOpen = ($geo.open -and $geo.item.k -eq $it.k)
    $trail = $(if ($isOpen) { '#3a3a3a' } else { $TRK })
    if ($it.k -eq 'mascot') {
      $rr = $MR
      switch ($mode) {
        { $_ -in 'thinking', 'coding', 'reading' } { Ring $g $ccx $icy $rr 2.5 $TRK; Arc $g $ccx $icy $rr 2.5 $(if ($cur.color) { [string]$cur.color } else { $TEXT }) $spinA 100 }
        'waiting' { if ($cur.loud) { Ring $g $ccx $icy $rr 3.5 $AMB ([int](140 + 115 * $pulse)) } else { Ring $g $ccx $icy $rr 2.5 $QUIET } }
        'done' { Ring $g $ccx $icy $rr 2.5 $GRN }
        'error' { Ring $g $ccx $icy $rr 2.5 $RED }
        default { Ring $g $ccx $icy $rr 2.5 $(if ($isOpen) { '#5a5a55' } else { $QUIET }) }
      }
      $u0 = [math]::Max(1.0, [math]::Round(2.0 * 0.9 * $script:S)) / $script:S
      Draw-Mascot $g $ccx ($icy + 8 * $u0) 0.9 $cur $t $age 4.0
      if ($script:compact) {
        # aneis escondidos: um ponto no anel avisa quando 5 h, 7 d ou contexto estao perto do limite
        $wc = Warn-Col $cur
        if ($wc) {
          $dx = $rr * 0.7071; $px = $ccx + $dx; $py = $icy - $dx
          $g.FillEllipse((Br $BLACK), [single]($px - 7), [single]($py - 7), 14, 14)
          $g.FillEllipse((Br $wc), [single]($px - 4.5), [single]($py - 4.5), 9, 9)
        }
      } else {
        $nm = [string]$cur.short; if (-not $nm) { $nm = ([string]$cur.name -split '/')[0] }
        $nm = ClipW $g $nm $fName ($NW - 4)
        $ncol = $(if ($mode -eq 'idle' -or -not $cur.color) { $DIM } else { [string]$cur.color })
        $g.DrawString($nm, $fName, (Br $ncol), [System.Drawing.RectangleF]::new([single]$geo.sx, [single]($iy + 2 * $MR + 8), [single]$NW, 16), $center)
      }
      continue
    }
    # linhas de uso: rotulo a esquerda, valor a direita, barra fina embaixo
    $x0 = $geo.sx + 10; $w0 = $NW - 20
    if (-not $sepDone) { $sepDone = $true; Rect $g $LINE $x0 ($iy - 9) $w0 1 }
    $lab = ''; $val = '—'; $pv = $null; $vcol = $TEXT
    switch ($it.k) {
      'five_hour' { $pv = [double](Get-Limit $cur 'five_hour').pct; $lab = '5h' }
      'seven_day' { $pv = [double](Get-Limit $cur 'seven_day').pct; $lab = '7d' }
      'ctx' { if ($null -ne $cur.ctxPct) { $pv = [double]$cur.ctxPct }; $lab = 'ctx' }
      'sub' { $lab = 'sub'; $val = [string]@($cur.agents | Where-Object { $_ }).Count; $vcol = $SUBC }
    }
    $g.FillPath((Br $trail), (RoundPath $x0 ($iy + 18) $w0 4 2))
    if ($it.k -eq 'sub') {
      $sx0 = $(if ($script:rm) { 0.0 } else { ($w0 - 18) * (0.5 + 0.5 * [math]::Sin($t * 3)) })
      $g.FillPath((Br $SUBC), (RoundPath ($x0 + $sx0) ($iy + 18) $(if ($script:rm) { $w0 } else { 18 }) 4 2))
    } elseif ($null -ne $pv) {
      $pv = [math]::Max(0, [math]::Min(100, $pv)); $val = '{0}%' -f [math]::Round($pv)
      if ($pv -gt 65) { $vcol = BandCol $pv }   # o numero so ganha cor quando merece atencao
      if ($pv -gt 0) { $g.FillPath((Br (BandCol $pv)), (RoundPath $x0 ($iy + 18) ([math]::Max(4, $w0 * $pv / 100)) 4 2)) }
    }
    $g.DrawString($lab, $fSmall, (Br $DIM), [single]($x0 - 3), [single]($iy - 1))
    $g.DrawString($val, $fRing, (Br $vcol), [System.Drawing.RectangleF]::new([single]$x0, [single]($iy - 1), [single]($w0 + 3), 16), $right)
  }

  # balao
  if ($geo.open) {
    $bp = BalloonPath $geo.by $geo.bh $geo.tipY
    $g.FillPath((Br $BLACK), $bp); $bp.Dispose()
    $stg = $g.Save()
    $g.TranslateTransform(0, [single]$geo.by)
    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    [void](Draw-Balloon $g ([string]$geo.item.bal) $true $nowMs)
    $g.Restore($stg)
  }
} catch { Add-Content "$env:TEMP\cw-log.txt" ("PAINT: " + $_.Exception.Message + " @ " + $_.InvocationInfo.ScriptLineNumber) } finally { foreach ($p2 in $script:pp) { $p2.Dispose() }; $script:pp.Clear() } })

# ---------- timer: anima por TEMPO (nao por quadro), le o arquivo so quando muda ----------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 33
$script:tick = 0
$timer.Add_Tick({ try {
  $script:tick++
  $now = $script:sw.Elapsed.TotalSeconds
  $dt = [math]::Min(0.1, $now - $script:lastT); $script:lastT = $now
  # consulta o arquivo de estado no max ~4x/s
  $changed = $false
  if (($now - $script:lastChk) -ge 0.25) {
    $script:lastChk = $now
    try {
      $fi = Get-Item -LiteralPath $StateFile -ErrorAction Stop
      if ($fi.LastWriteTimeUtc -ne $script:lastWrite) {
        $script:state = Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:lastWrite = $fi.LastWriteTimeUtc; $changed = $true
      }
    } catch { }
    if ($changed -or $script:items.Count -eq 0) { Rebuild-Items }
  }
  # alerta (waiting + loud): abre o balao do mascote; ao sair, fecha ~10 s depois sem mouse
  $loudNow = [bool]($script:state -and $script:state.mode -eq 'waiting' -and $script:state.loud)
  if ($form.Bounds.Contains([System.Windows.Forms.Cursor]::Position) -or $script:down) { $script:lastAct = $now }
  if ($loudNow) { $script:alert = $true; if (-not $script:prevLoud) { $script:lastAct = $now } }
  elseif ($script:prevLoud) { $script:lastAct = $now }
  elseif ($script:alert -and ($now - $script:lastAct) -gt 10) { $script:alert = $false }
  $script:prevLoud = $loudNow
  # mouse fora da faixa e do balao (posicao real do cursor; MouseLeave se perde quando a janela muda de forma)
  $cp = [System.Windows.Forms.Cursor]::Position; $inside = $false
  if ($form.Bounds.Contains($cp)) { $rgn = $form.Region; $inside = ((-not $rgn) -or $rgn.IsVisible($form.PointToClient($cp))) }
  if ($inside -or $script:down -or $menu.Visible) { $script:leaveAt = 0.0 }
  elseif ($script:hov -and $script:leaveAt -le 0) { $script:leaveAt = $now }
  # saiu: fecha o balao apos ~400 ms
  if ($script:leaveAt -gt 0 -and ($now - $script:leaveAt) -gt 0.4) { $script:hov = ''; $script:leaveAt = 0.0 }
  # qual item esta aberto: mouse > fixado > alerta
  $itOpen = $null
  if ($script:hov) { $itOpen = Find-Item $script:hov }
  if (-not $itOpen -and $script:pinned) { $itOpen = Find-Item $script:pinned }
  if (-not $itOpen -and $script:alert) { $itOpen = Find-Item 'mascot' }
  $script:openKey = $(if ($itOpen) { [string]$itOpen.k } else { '' })
  # altura do balao (mede so quando o item ou o estado muda)
  if ($itOpen) {
    $bk = '{0}|{1}|{2}|{3}' -f $itOpen.bal, $script:lastWrite.Ticks, $script:S, $script:compact
    if ($bk -ne $script:balKey) {
      $script:balKey = $bk
      $script:balH = [math]::Ceiling((Draw-Balloon $script:mg ([string]$itOpen.bal) $false ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())))
    }
  }
  # altura da faixa acompanha os itens (suave, ou direto com reducao de movimento)
  $script:rm = ($script:reduce -or ($script:state.reduceMotion -eq $true))
  $moving = $false
  if ($script:curH -ne $script:tgtH) {
    if ($script:rm -or [math]::Abs($script:tgtH - $script:curH) -lt 0.5) { $script:curH = $script:tgtH }
    else { $script:curH += ($script:tgtH - $script:curH) * [math]::Min(1.0, $dt * 14); $moving = $true }
  }
  Apply-Geo
  $iv = $(if ($moving) { 16 } else { 33 })
  if ($timer.Interval -ne $iv) { $timer.Interval = $iv }
  # parado de verdade: ocioso, ou "Sua vez" depois que o aceno inicial acabou -> redesenha ~4x/s em vez de 30
  $calm = $false
  if ($script:state) {
    $md = [string]$script:state.mode
    $calm = ($md -eq 'idle') -or ($md -eq 'waiting' -and -not $script:state.loud -and $script:lastMode -eq 'waiting' -and ($now - $script:modeT0) -gt 3.2)
  }
  $quiet = ($calm -and -not $itOpen -and -not @($script:state.agents | Where-Object { $_ }).Count)
  if ($quiet -and -not $moving -and ($script:tick % 8) -ne 0) { return }
  $form.Invalidate()
} catch { Add-Content "$env:TEMP\cw-log.txt" ("TICK: " + $_.Exception.Message + " @ " + $_.InvocationInfo.ScriptLineNumber) } })
Rebuild-Items; Apply-Geo
$timer.Start()
[void][System.Windows.Forms.Application]::Run($form)
