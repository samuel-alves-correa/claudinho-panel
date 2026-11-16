# Claudinho: widget fixo na borda direita da tela, sempre no topo.
# Clique = recolhe/expande. Arraste = muda a altura. Botao direito = menu.
# Le claudinho-state.json (escrito pelo mod) so quando o arquivo muda; anima com timer proprio.
# CW_EXPAND=1 forca expandido (tem prioridade sobre o salvo). CW_REDUCE_MOTION=1 (ou reduceMotion no estado) desliga pulso e pulos do mascote.
# Posicao (top) e expandido ficam em %USERPROFILE%\.claude\claudinho-widget.json.
param([string]$StateFile = (Join-Path $PSScriptRoot '..\claudinho-state.json'))

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' -Name D -Namespace Cw
[void][Cw.D]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:S = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX / 96.0

# ---------- paleta (tons quentes da Anthropic) ----------
$BG = '#262624'; $CARD = '#1f1e1d'; $LINE = '#3d3d3a'; $TEXT = '#faf9f5'; $DIM = '#a09d96'; $CORAL = '#d97757'

$script:state = $null
$script:lastWrite = [datetime]::MinValue
$script:brushes = @{}
$script:pens = @{}
$script:sw = [System.Diagnostics.Stopwatch]::StartNew()
$script:lastMode = ''; $script:prevMode = ''; $script:codingEnd = 0.0; $script:introSkip = $false
$script:modeT0 = 0.0
$script:expanded = [bool]$env:CW_EXPAND
$script:A = 255; $script:prog = 0.0; $script:e = 0.0; $script:lastT = 0.0
$script:lastAct = 0.0; $script:prevLoud = $false; $script:lastChk = -1.0; $script:hOpen = 440.0
$script:rm = $false; $script:reduce = ($env:CW_REDUCE_MOTION -eq '1'); $script:hovC = $false; $script:autoExp = $false
# respeita "Efeitos de animacao" do Windows (SPI_GETCLIENTAREAANIMATION = 0x1042)
try {
  Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint a, uint b, ref int c, uint d);' -Name Sp -Namespace Cw
  $anim = 1
  if ([Cw.Sp]::SystemParametersInfo(0x1042, 0, [ref]$anim, 0) -and $anim -eq 0) { $script:reduce = $true }
} catch { }
$W_OPEN = 240; $H_OPEN = 440; $W_SHUT = 104; $H_SHUT = 104
$script:curW = [double]$W_SHUT; $script:curH = [double]$H_SHUT

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
# janela encostada na direita: cantos arredondados so no lado esquerdo
function DockPath([single]$w, [single]$h, [single]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $p.AddArc(0, 0, $d, $d, 180, 90); $p.AddLine($r, 0, $w, 0); $p.AddLine($w, 0, $w, $h)
  $p.AddLine($w, $h, $r, $h); $p.AddArc(0, $h - $d, $d, $d, 90, 90); $p.CloseFigure(); $p
}

function F([string]$n,[double]$pt,$st='Regular'){ New-Object System.Drawing.Font($n,[single]($pt*96/72),[System.Drawing.FontStyle]$st,[System.Drawing.GraphicsUnit]::Pixel) }
$fTitle = (F 'Georgia' 15 'Bold')
$fName = (F 'Segoe UI' 9 'Bold')
$fBrand = (F 'Georgia' 11 'Bold')
$fBody = (F 'Segoe UI' 9.5)
$fSmall = (F 'Segoe UI' 9)
$fChev = (F 'Segoe UI' 18 'Bold')
$fMono = (F 'Consolas' 9)
$fMonoB = (F 'Consolas' 11 'Bold')
$fGlyph = (F 'Consolas' 10 'Bold')
$fZ = (F 'Georgia' 11 'Italic')
$fSpin = (F 'Segoe UI Symbol' 15)
$fSpinS = (F 'Segoe UI Symbol' 11)
$SPIN = '·', '✢', '✳', '✶', '✻', '✽'
function Spin([double]$t, [string]$mode) {
  if ($mode -in 'thinking', 'coding', 'reading') { $i = [int][math]::Floor($t * 8) % 10; if ($i -gt 5) { $i = 10 - $i }; $SPIN[$i] } else { '✻' }
}
$center = New-Object System.Drawing.StringFormat; $center.Alignment = 'Center'
$right = New-Object System.Drawing.StringFormat; $right.Alignment = 'Far'

function Dur($ms) {
  $t = [int][math]::Max(0, [math]::Floor($ms / 1000)); $m = [int][math]::Floor($t / 60)
  if ($m -ge 60) { '{0}h{1:00}' -f [math]::Floor($m / 60), ($m % 60) } else { '{0}:{1:00}' -f $m, ($t % 60) }
}
# tempo relativo curto: agora / 2 min / 1 h
function Rel($nowMs, $t) { $d = [math]::Max(0, ($nowMs - [double]$t) / 1000); if ($d -lt 5) { 'agora' } elseif ($d -lt 60) { '{0} s' -f [math]::Floor($d) } elseif ($d -lt 3600) { '{0} min' -f [math]::Floor($d / 60) } else { '{0} h' -f [math]::Floor($d / 3600) } }
# numero curto sem casas inuteis: 70k, 1M
function KS($n) { if ($n -ge 1e6) { '{0:0.#}M' -f ($n / 1e6) } elseif ($n -ge 1e3) { '{0:0}k' -f ($n / 1e3) } else { "$n" } }
function K($n) { if ($n -ge 1e6) { '{0:N2}M' -f ($n / 1e6) } elseif ($n -ge 1e3) { '{0:N1}k' -f ($n / 1e3) } else { "$n" } }
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
# Poses: de frente, virando, agachado; vareta cinza so no Codando (sequencia gravada em video).
function Draw-Mascot($g, [single]$cx, [single]$gy, [single]$p, $s, [double]$t, [double]$age, [double]$range) {
  $mode = [string]$s.mode; $loud = [bool]$s.loud
  $B = [string]$s.palette.B; $D = [string]$s.palette.D
  $shade = Mix $B $D 0.4; $deep = Mix $D '#1c1410' 0.6
  $q = $p * 3.65   # escala dos adereços (balões, teclas, partículas)
  $u = [math]::Max(1.0, [math]::Round(2.0 * $p * $script:S)) / $script:S    # alinhado ao pixel do dispositivo; 1 "pixel" do bichinho; corpo de frente = 16 x 16 pixels (+ bracos)
  $ox = 0.0; $oy = 0.0; $sy = 1.0; $wf = 0.0
  $pose = 'front'; $eyes = 'open'; $eyY = (-14.0); $eyX = 0.0
  $armL = 0.0; $armR = 0.0   # deslocamento vertical dos bracos em pixels (negativo = sobe)
  $stk = ''; $lift = 0.0; $lens = $false; $mouth = $false
  $prev = [string]$script:prevMode

  if ($mode -eq 'coding') {
    # sequencia do video: de frente -> vira -> pega a vareta -> abaixa -> agacha e escreve
    $a = if ($script:introSkip) { 99.0 } else { $age }
    if     ($a -lt 0.30) { $pose = 'front' }
    elseif ($a -lt 0.55) { $pose = 'turn' }
    elseif ($a -lt 0.75) { $pose = 'front'; $armL = (-2.0); $stk = 'raise' }
    elseif ($a -lt 1.20) { $pose = 'front'; $armL = (-4.0); $stk = 'up' }
    elseif ($a -lt 1.45) { $pose = 'front'; $stk = 'diag' }
    elseif ($a -lt 1.75) { $pose = 'turn2'; $stk = 'L' }
    else {
      $pose = 'crouch'; $stk = 'L'; $wf = 15
      $oy = -[math]::Abs([math]::Sin($t * 15)) * 0.3 * $u
      $mouth = (([int][math]::Floor($t * 6)) % 2 -eq 0)
      $fp = $t % 4.5
      if ($fp -lt 0.35) { $lift = [math]::Sin($fp / 0.35 * [math]::PI) }   # de vez em quando levanta a vareta
    }
  } elseif ($prev -eq 'coding' -and $age -lt 0.36) {
    # saindo do Codando: levanta, vira e volta de frente
    if ($age -lt 0.18) { $pose = 'turn2'; $stk = 'L' } else { $pose = 'turn' }
  } else {
    switch ($mode) {
      'idle' { $sy = 1 + 0.02 * [math]::Sin($t * 1.6); $eyes = 'closed' }
      'thinking' { $ox = [math]::Sin($t * 0.6) * $range * 0.5; $wf = 4; $eyY = (-15.5); $eyX = (-0.5) }
      'reading' { $ox = [math]::Sin($t * 0.9) * $range * 0.6; $wf = 6; $lens = $true; $eyX = 0.6; $eyY = (-13.5) }
      'waiting' {
        if ($loud) { $h = $(if ($script:rm) { 0.0 } else { [math]::Abs([math]::Sin($t * 4.2)) }); $oy = -$h * 6 * $p; $sy = 0.92 + 0.15 * $h; $armL = (-4.0); $armR = (-4.0) }
        else { $h = $(if ($script:rm) { 0.0 } else { [math]::Abs([math]::Sin($t * 2)) }); $oy = -$h * 1.5 * $p; if (-not $script:rm -and [math]::Sin($t * 5) -gt 0) { $armL = (-4.0) } }
      }
      'done' { if ($age -lt 0.7) { $oy = -[math]::Abs([math]::Sin($age * 4.5)) * 8 * $p }; $eyes = 'happy'; $armL = (-4.0); $armR = (-4.0) }
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

  # vareta cinza (so aparece no Codando, como no video)
  $gr = '#9b9b9b'
  switch ($stk) {
    'raise' { U $gr (-17) (-15.5) 6 2; U $gr (-14) (-17.5) 2.5 2.5 }
    'up' { U $gr (-14.8) (-23) 1.4 6.8; U $gr (-14.8) (-17.2) 6 1.2 }
    'diag' {
      U $gr (-22) (-3.6) 2 0.9; U $gr (-20) (-3) 2 0.9; U $gr (-18) (-2.2) 2 0.9; U $gr (-16) (-1.4) 2 0.9; U $gr (-14) (-1) 4 0.9
    }
    'L' {
      for ($i = 0; $i -lt 6; $i++) { U $gr (-19 + $i) (-6.5 + 0.9 * $i - $lift * 4 * (1 - $i / 5.0)) 1.4 1 }
      U $gr (-14) (-1.4) 5 0.9
    }
  }
  if ($lens) {
    $g.SmoothingMode = 'AntiAlias'
    $g.DrawEllipse((Pn ([string]$s.color) ([single](0.9 * $u))), [single](11.5 * $u), [single](-17.5 * $u), [single](7 * $u), [single](7 * $u))
    $g.DrawLine((Pn '#9b9b9b' ([single](0.9 * $u))), [single](12 * $u), [single](-10 * $u), [single](13.4 * $u), [single](-11.4 * $u))
  }
  $g.Restore($st)
  $g.SmoothingMode = 'AntiAlias'

  # ---------- adereços por estado ----------
  switch ($mode) {
    'idle' {
      for ($i = 0; $i -lt 3; $i++) {
        $ph = (($t * 0.35) + $i / 3.0) % 1.0
        $a = [int](255 * [math]::Sin($ph * [math]::PI)); if ($a -gt 0) {
          $g.DrawString('z', $fZ, (Br $DIM $a), [single]($mx + 3 * $q + 8 * [math]::Sin($ph * 6) * ($q / 9)), [single]($gy - 9 * $q - $ph * 5 * $q))
        }
      }
    }
    'thinking' {
      for ($i = 0; $i -lt 3; $i++) {
        $r = (0.25 + 0.2 * [math]::Max(0, [math]::Sin($t * 4.5 - $i * 0.9))) * $q * 1.4
        $g.FillEllipse((Br '#6cc4e8' 230), [single]($mx + (1 + $i * 1.5) * $q - $r), [single]($gy - (10.5 + $i * 0.6) * $q - $r), [single](2 * $r), [single](2 * $r))
      }
    }
    'coding' { if ($pose -eq 'crouch') {
      $kx = $mx - 7 * $q; $ky = $gy - 0.5 * $q
      $g.FillPath((Br '#3d3d3a'), (RoundPath $kx $ky (14 * $q) (1.7 * $q) (0.4 * $q)))
      $active = [int]([math]::Floor($t * 13)) % 9
      for ($i = 0; $i -lt 9; $i++) {
        $col = if ($i -eq $active) { $CORAL } else { '#57554f' }
        Rect $g $col ($kx + (0.5 + $i * 1.5) * $q) ($ky + 0.4 * $q) (1.2 * $q) (0.9 * $q)
      }
      $chars = '{', '}', ';', '=>', '()', '</>'
      for ($i = 0; $i -lt 4; $i++) {
        $ph = (($t * 0.9) + $i / 4.0) % 1.0
        $a = [int](230 * [math]::Sin($ph * [math]::PI))
        if ($a -gt 0) { $g.DrawString($chars[($i + [int]($t * 0.9)) % 6], $fGlyph, (Br $CORAL $a), [single]($mx - 4 * $q + $i * 2.6 * $q), [single]($gy - 10.5 * $q - $ph * 4 * $q)) }
      }    } }
    'waiting' {
      $k = if ($loud -and -not $script:rm) { 1 + 0.12 * [math]::Sin($t * 9) } else { 1 }
      $bw = 3.4 * $q * $k; $bh = 3 * $q * $k; $bx = $mx + 2 * $q; $by = $gy - 14 * $q - $oy * 0
      # amarelo so no "precisa de voce"; "sua vez" fica neutro
      $g.FillPath((Br $(if ($loud) { '#f5c542' } else { '#57554f' })), (RoundPath $bx $by $bw $bh (0.8 * $q)))
      $txt = if ($loud) { '!' } else { '…' }
      $g.DrawString($txt, $fMonoB, (Br $(if ($loud) { '#1c1410' } else { $TEXT })), [System.Drawing.RectangleF]::new([single]$bx, [single]($by + $bh / 2 - 9), [single]$bw, 20), $center)
    }
    'done' {
      for ($i = 0; $i -lt 5; $i++) {
        $ph = [math]::Min(1, $age / 1.2); $ang = $i * 1.26 - 1.2
        $d = (3 + $ph * 6) * $q; $a = [int](255 * (1 - $ph))
        if ($a -gt 0) { $g.DrawString('✦', $fBody, (Br '#5fd38d' $a), [single]($mx + $d * [math]::Cos($ang)), [single]($gy - 5 * $q + $d * [math]::Sin($ang) * 0.9 - 14)) }
      }
    }
    'error' {
      $g.FillPath((Br '#ff5f56'), (RoundPath ($mx + 2 * $q) ($gy - 14 * $q) (3 * $q) (3 * $q) (0.8 * $q)))
      $g.DrawString('!', $fMonoB, (Br '#1c1410'), [System.Drawing.RectangleF]::new([single]($mx + 2 * $q), [single]($gy - 14 * $q + 1.5 * $q - 9), [single](3 * $q), 20), $center)
    }
  }
}

# ---------- janela ----------
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'; $form.TopMost = $true; $form.ShowInTaskbar = $false
$form.StartPosition = 'Manual'; $form.BackColor = [System.Drawing.ColorTranslator]::FromHtml($BG)
$form.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($form, $true)
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$script:top = $wa.Top + 70 * $script:S
# config salva (top/expanded); CW_EXPAND tem prioridade
$CFG = "$env:USERPROFILE\.claude\claudinho-widget.json"
try {
  if (Test-Path -LiteralPath $CFG) {
    $sv = Get-Content -LiteralPath $CFG -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -ne $sv.top -and [double]$sv.top -ge $wa.Top -and [double]$sv.top -le ($wa.Bottom - 60)) { $script:top = [double]$sv.top }
    if (-not $env:CW_EXPAND -and $null -ne $sv.expanded) { $script:expanded = [bool]$sv.expanded }
  }
} catch { }
# userExp = escolha do usuario; auto-recolher nao a sobrescreve
$script:userExp = $script:expanded
function Save-Cfg {
  try {
    $d = Split-Path -Parent $CFG
    if (-not (Test-Path -LiteralPath $d)) { $null = New-Item -ItemType Directory -Path $d -Force }
    (@{ top = [int]$script:top; expanded = [bool]$script:userExp } | ConvertTo-Json -Compress) | Set-Content -LiteralPath $CFG -Encoding UTF8
  } catch { }
}

function Apply-Size {
  $w = [int][math]::Round($script:curW * $script:S); $h = [int][math]::Round($script:curH * $script:S)
  $script:top = [math]::Max($wa.Top, [math]::Min($script:top, $wa.Bottom - $h))
  $form.SetBounds($wa.Right - $w, [int]$script:top, $w, $h)
  $dp = DockPath $w $h (16 * $script:S); $oldR = $form.Region
  $form.Region = New-Object System.Drawing.Region $dp
  $dp.Dispose(); if ($oldR) { $oldR.Dispose() }
}
Apply-Size

$script:down = $null; $script:moved = $false
$form.Add_MouseDown({ if ($_.Button -eq 'Left') { $script:down = $_.Location; $script:moved = $false } })
$form.Add_MouseMove({
  if ($script:down -and $_.Button -eq 'Left') {
    $dy = $_.Y - $script:down.Y
    if ([math]::Abs($dy) -gt 3 -or $script:moved) { $script:moved = $true; $script:top += $dy; Apply-Size }
  }
})
# alvo de clique em px logicos: chevron (28x28) no expandido
function ChevRect { @(($form.Width / $script:S - 34), 4, 28, 28) }
function InChev($px, $py) { if ($script:e -le 0.5) { return $false }; $c = ChevRect; $xx = $px / $script:S; $yy = $py / $script:S; ($xx -ge $c[0] -and $xx -le ($c[0] + $c[2]) -and $yy -ge $c[1] -and $yy -le ($c[1] + $c[3])) }
$form.Add_MouseUp({
  if ($_.Button -eq 'Left') {
    if ($script:moved) { Save-Cfg }
    elseif (-not $script:expanded -or ($_.Y / $script:S) -lt 40) { $script:expanded = -not $script:expanded; $script:userExp = $script:expanded; $script:autoExp = $false; Save-Cfg }
  }
  $script:lastAct = $script:sw.Elapsed.TotalSeconds
  $script:down = $null; $script:moved = $false
})
$form.Add_FormClosing({ Save-Cfg })
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$null = $menu.Items.Add('Expandir / recolher', $null, { $script:expanded = -not $script:expanded; $script:userExp = $script:expanded; $script:autoExp = $false; Save-Cfg })
$null = $menu.Items.Add('Fechar', $null, { $form.Close() })
$form.ContextMenuStrip = $menu
$script:hits = @(); $script:tipTxt = ''
$tip = New-Object System.Windows.Forms.ToolTip
$tip.InitialDelay = 400
$form.Add_MouseMove({
  $script:hovC = (InChev $_.X $_.Y)
  $yy = $_.Y / $script:S; $txt = $(if ($script:hovC) { 'Recolher' } else { '' })
  $form.Cursor = $(if (-not $script:expanded -or $yy -lt 40) { [System.Windows.Forms.Cursors]::Hand } else { [System.Windows.Forms.Cursors]::Default })
  if (-not $script:hovC) {
    foreach ($h in $script:hits) { if ($yy -ge $h[0] -and $yy -le $h[1]) { $txt = [string]$h[2]; break } }
  }
  if ($txt -ne $script:tipTxt) { $script:tipTxt = $txt; $tip.SetToolTip($form, $txt) }
})

$form.Add_Paint({ try {
  $g = $_.Graphics
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
  $g.ScaleTransform($script:S, $script:S)
  $W = $form.Width / $script:S; $H = $form.Height / $script:S; $t = $script:sw.Elapsed.TotalSeconds
  $script:A = 255
  $s = $script:state
  if (-not $s) { $g.DrawString('Aguardando o Claude Code…', $fBody, (Br $DIM), 14, 14); return }
  if ($s.mode -ne $script:lastMode) {
    if ($script:lastMode -eq 'coding') { $script:codingEnd = $t }
    $script:introSkip = ($s.mode -eq 'coding' -and $script:codingEnd -gt 0 -and ($t - $script:codingEnd) -lt 8)
    $script:prevMode = $script:lastMode; $script:lastMode = $s.mode; $script:modeT0 = $t
  }
  $age = $t - $script:modeT0
  $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $e = $script:e
  $accent = [string]$s.color
  $loudWait = ($s.mode -eq 'waiting' -and $s.loud)
  $script:rm = ($script:reduce -or ($s.reduceMotion -eq $true))
  # pulsa ~3 ciclos ao entrar no loud e depois fica fixo na intensidade alta
  $pulse = 1.0
  if ($loudWait -and -not $script:rm -and $age -lt (3 * [math]::PI / 4.2)) { $pulse = [math]::Abs([math]::Sin($t * 4.2)) }

  # borda; amarelo so no loud ("precisa de voce")
  $ba = 255; $bwid = 1.5
  if ($loudWait) { $accent = '#f5c542'; $ba = [int](140 + 115 * $pulse); $bwid = 3.5 } else { $accent = $LINE }
  $dpb = DockPath ($W - 1) ($H - 1) 16
  $g.DrawPath((Pn $accent ([single]$bwid) $ba), $dpb); $dpb.Dispose()

  # cartao do palco aparece junto com a expansao
  if ($e -gt 0.04) {
    $script:A = [int](255 * $e)
    $g.FillPath((Br $CARD), (RoundPath 12 34 ($W - 24) 80 12))
    if ($loudWait) { $script:A = [int]($e * (25 + 30 * $pulse)); $g.FillPath((Br '#f5c542'), (RoundPath 12 34 ($W - 24) 80 12)) }
    $script:A = 255
  }

  # mascote cresce e desce continuamente entre os dois tamanhos
  $pp = 1.0 + 0.9 * $e; $gy = 60 + 42 * $e; $cx = ($W / 2) - 2 * (1 - $e)
  $range = [math]::Max(0, ($W / 2) - 26 * $pp - 4)
  Draw-Mascot $g $cx $gy $pp $s $t $age $range

  $spin = Spin $t ([string]$s.mode)

  if ($e -lt 0.5) {
    # ----- recolhido (some ao expandir) -----
    $script:A = [int](255 * (1 - 2 * $e))
    $nm = $(if ($s.short) { [string]$s.short } else { ([string]$s.name -split '/')[0] })
    $lbl = $(if ($s.labelShort) { [string]$s.labelShort } else { [string]$s.label })
    $gw = 14
    while ($nm.Length -gt 3 -and $g.MeasureString($nm, $fName).Width -gt ($W - 12 - $gw)) { $nm = $nm.Substring(0, $nm.Length - 2) + '…' }
    $nw = $g.MeasureString($nm, $fName).Width
    $x0 = ($W - ($nw + $gw)) / 2 - 4
    $ncol = if ($s.mode -eq 'idle') { $TEXT } else { [string]$s.color }
    $g.DrawString($spin, $fSpinS, (Br $ncol), ($x0 - 2), 67)
    $g.DrawString($nm, $fName, (Br $ncol), ($x0 + $gw), 68)
    $g.DrawString((ClipW $g $lbl $fSmall ($W - 12)), $fSmall, (Br $DIM), [System.Drawing.RectangleF]::new(2, 83, ($W - 4), 16), $center)
    # subagentes ativos: selo no canto; modelo vai no tooltip (nao cabe no recolhido)
    $nag = @($s.agents | Where-Object { $_ }).Count
    if ($nag -gt 0) {
      $bt = "$nag sub"; $bwd = $g.MeasureString($bt, $fSmall).Width + 8
      $g.FillPath((Br '#34332f'), (RoundPath 6 6 $bwd 18 9))
      $g.DrawString($bt, $fSmall, (Br $TEXT), 10, 7)
    }
    $tipC = (([string]$s.name -split '/')[0] + ' · ' + [string]$s.label)
    if ($s.model) { $tipC += ' · ' + [string]$s.model }
    if ($nag -gt 0) { $tipC += ' · ' + $(if ($nag -eq 1) { '1 subagente' } else { "$nag subagentes" }) }
    $script:hits = @(@(0, $H, $tipC))
  }
  if ($e -gt 0.5) {
    # ----- expandido (aparece aos poucos) -----
    $script:A = [int](255 * (2 * $e - 1))
    $g.FillEllipse((Br $CORAL), 16, 15, 9, 9)
    $proj = [string]$s.project; if (-not $proj) { $proj = 'Claudinho' }
    $g.DrawString((ClipW $g $proj $fBrand 92), $fBrand, (Br $TEXT), 30, 10)
    $g.DrawString('›', $fChev, (Br $(if ($script:hovC) { $TEXT } else { '#d6d3cc' })), [System.Drawing.RectangleF]::new(($W - 34), (-2), 28, 32), $center)

    $script:hits = @()
    # modelo da sessao, a direita do nome do projeto
    $mdl = [string]$s.model
    if ($mdl) {
      $g.DrawString((ClipW $g $mdl $fSmall 76), $fSmall, (Br $DIM), [System.Drawing.RectangleF]::new(124, 12, ($W - 124 - 36), 16), $right)
      $script:hits += , @(0, 30, ('modelo: ' + $mdl))
    }
    $ncol = if ($s.mode -eq 'idle') { $TEXT } else { [string]$s.color }
    $y = 122
    $g.DrawString($spin, $fSpin, (Br $ncol), 13, ($y + 1))
    $g.DrawString([string]$s.name, $fTitle, (Br $ncol), 36, $y)
    $y += 26
    if ($s.mode -eq 'waiting') {
      # o que esta sendo pedido (ferramenta + alvo) em destaque; sem o campo, cai no label
      $main = [string]$s.ask; if (-not $main) { $main = [string]$s.label }
      $g.DrawString((ClipW $g $main $fBody ($W - 32)), $fBody, (Br $TEXT), 16, $y)
      $script:hits += , @($y, ($y + 18), $main)
      $y += 20
      if ($s.waitSince -and [double]$s.waitSince -gt 0) {
        $g.DrawString(('aguardando há ' + (Dur ($nowMs - [double]$s.waitSince))), $fSmall, (Br $DIM), 16, $y); $y += 18
      }
    } else {
      $g.DrawString((ClipW $g ([string]$s.label) $fBody ($W - 32)), $fBody, (Br $DIM), 16, $y)
      $script:hits += , @($y, ($y + 18), [string]$s.label)
      $y += 22
    }
    Rect $g $LINE 16 $y ($W - 32) 1; $y += 9

    # contexto em destaque
    $ctx = $s.ctxPct
    $g.DrawString('Contexto', $fSmall, (Br $DIM), 16, ($y + 3))
    if ($null -ne $ctx) {
      $pt = '{0}%' -f [math]::Round($ctx)
      $g.DrawString($pt, $fMonoB, (Br $TEXT), [System.Drawing.RectangleF]::new(0, $y, ($W - 16), 20), $right)
      # tokens usados / janela, so se o mod informou
      if ($null -ne $s.ctxTok -and $null -ne $s.ctxWin) {
        $pw = $g.MeasureString($pt, $fMonoB).Width
        $g.DrawString(((KS $s.ctxTok) + ' / ' + (KS $s.ctxWin)), $fSmall, (Br $DIM), [System.Drawing.RectangleF]::new(0, ($y + 3), ($W - 16 - $pw - 6), 16), $right)
      }
    }
    else { $g.DrawString('sem dados', $fSmall, (Br $DIM), [System.Drawing.RectangleF]::new(0, ($y + 3), ($W - 16), 16), $right) }
    $y += 22
    $g.FillPath((Br $LINE), (RoundPath 16 $y ($W - 32) 9 4.5))
    if ($null -ne $ctx) {
      $fw = [math]::Max(9, ($W - 32) * [math]::Min(100, $ctx) / 100)
      $g.FillPath((Br $(if ($ctx -gt 85) { '#ff5f56' } elseif ($ctx -gt 65) { '#f5c542' } else { '#c9c6be' })), (RoundPath 16 $y $fw 9 4.5))
    }
    $y += 18
    Rect $g $LINE 16 $y ($W - 32) 1; $y += 9

    $cols = @(@('entrada', $(if ($s.tokens) { K $s.tokens.in } else { '—' }), $TEXT), @('saída', $(if ($s.tokens) { K $s.tokens.out } else { '—' }), $TEXT), @('custo', $(if ($null -ne $s.usd) { '$' + ([double]$s.usd).ToString('N2', [System.Globalization.CultureInfo]::GetCultureInfo('pt-BR')) } else { '—' }), $TEXT))
    $cw = ($W - 32) / 3
    for ($i = 0; $i -lt 3; $i++) {
      $g.DrawString($cols[$i][1], $fMonoB, (Br $cols[$i][2]), (16 + $i * $cw), $y)
      $g.DrawString($cols[$i][0], $fSmall, (Br $DIM), (16 + $i * $cw), ($y + 17))
    }
    if (-not $s.tokens) { $script:hits += , @($y, ($y + 36), 'tokens aparecem após o 1º turno') }
    else { $script:hits += , @($y, ($y + 36), ('cache: ' + (K $s.tokens.cache))) }
    $y += 38

    $turn = if ($s.mode -in 'thinking', 'coding', 'reading', 'error') { Dur ($nowMs - $s.turnStart) } else { '—' }
    $sdur = if ($s.sessionStart -and [double]$s.sessionStart -gt 0) { Dur ($nowMs - [double]$s.sessionStart) } else { '—' }
    $sess = 'sessão {0} · turno {1}' -f $sdur, $turn
    $g.DrawString((ClipW $g $sess $fSmall ($W - 28)), $fSmall, (Br $DIM), 16, ($y + 1))
    $y += 20
    Rect $g $LINE 16 $y ($W - 32) 1; $y += 9

    # chips: ate 2 linhas; o que nao couber vira "+N" (nunca some em silencio)
    $chips = New-Object System.Collections.ArrayList
    $row = 0; $x = 16; $over = 0
    foreach ($tp in @($s.top)) {
      if ($over -gt 0) { $over++; continue }
      $txt = '{0} ×{1}' -f $tp[0], $tp[1]
      $cwid = $g.MeasureString($txt, $fSmall).Width + 12
      if ($x + $cwid -gt $W - 14 -and $x -gt 16) { $row++; $x = 16 }
      if ($row -ge 2) { $over = 1; continue }
      [void]$chips.Add(@($txt, $row, $x, $cwid)); $x += $cwid + 6
    }
    while ($over -gt 0 -and $chips.Count -gt 0) {
      $lt = '+' + $over; $lw = $g.MeasureString($lt, $fSmall).Width + 12
      $lc = $chips[$chips.Count - 1]
      if ($lc[1] -eq 1 -and ($lc[2] + $lc[3] + 6 + $lw) -le ($W - 14)) { [void]$chips.Add(@($lt, 1, ($lc[2] + $lc[3] + 6), $lw)); break }
      if ($lc[1] -eq 0 -and $chips.Count -eq 1) { [void]$chips.Add(@($lt, 0, ($lc[2] + $lc[3] + 6), $lw)); break }
      $chips.RemoveAt($chips.Count - 1); $over++
    }
    $nrow = 1
    foreach ($ch in $chips) {
      if ($ch[1] + 1 -gt $nrow) { $nrow = $ch[1] + 1 }
      $cy = $y + $ch[1] * 26
      $g.FillPath((Br '#34332f'), (RoundPath $ch[2] $cy $ch[3] 22 11))
      $g.DrawString($ch[0], $fSmall, (Br $DIM), ($ch[2] + 6), ($cy + 3))
    }
    $y += 22 + ($nrow - 1) * 26 + 9
    Rect $g $LINE 16 $y ($W - 32) 1; $y += 9

    # subagentes ativos: contagem sempre visivel; ate 3 linhas com descricao e modelo
    $ags = @($s.agents | Where-Object { $_ })
    $g.DrawString('SUBAGENTES', $fSmall, (Br $DIM), 16, $y)
    $agTxt = $(if ($ags.Count -eq 0) { 'nenhum' } elseif ($ags.Count -eq 1) { '1 ativo' } else { "$($ags.Count) ativos" })
    $g.DrawString($agTxt, $fSmall, (Br $(if ($ags.Count -gt 0) { $TEXT } else { $DIM })), [System.Drawing.RectangleF]::new(0, $y, ($W - 16), 16), $right)
    $y += 18
    $shown = 0
    foreach ($ag in $ags) {
      if ($shown -ge 3) { break }
      $agM = [string]$ag.model; $agMW = 0
      if ($agM) {
        $agMW = $g.MeasureString($agM, $fSmall).Width + 6
        $g.DrawString($agM, $fSmall, (Br $DIM), [System.Drawing.RectangleF]::new(0, ($y + 1), ($W - 16), 16), $right)
      }
      $agD = [string]$ag.desc; if (-not $agD) { $agD = [string]$ag.type }
      $g.DrawString((ClipW $g $agD $fSmall ($W - 32 - $agMW)), $fSmall, (Br $TEXT), 16, ($y + 1))
      $script:hits += , @($y, ($y + 18), ([string]$ag.type + ' · ' + $agD + $(if ($agM) { ' · ' + $agM } else { '' })))
      $y += 18; $shown++
    }
    if ($ags.Count -gt 3) { $g.DrawString(('+' + ($ags.Count - 3) + ' em andamento'), $fSmall, (Br $DIM), 16, ($y + 1)); $y += 18 }
    $y += 4
    Rect $g $LINE 16 $y ($W - 32) 1; $y += 9

    $g.DrawString('ATIVIDADE RECENTE', $fSmall, (Br $DIM), 16, $y); $y += 18
    foreach ($h in ($s.history | Select-Object -First 3)) {
      $g.DrawString((Rel $nowMs $h.t), $fMono, (Br $DIM), 16, $y)
      $g.DrawString((ClipW $g ([string]$h.text) $fSmall ($W - 66)), $fSmall, (Br $TEXT), 60, ($y + 1))
      $script:hits += , @($y, ($y + 18), [string]$h.text)
      $y += 18
    }
    # altura do expandido acompanha o conteudo (timer aplica)
    if ($e -ge 0.99) { $script:hOpen = [math]::Ceiling($y + 12) }
  }
  $script:A = 255
} catch { Add-Content "$env:TEMP\cw-log.txt" ("PAINT: " + $_.Exception.Message + " @ " + $_.InvocationInfo.ScriptLineNumber) } finally { foreach ($p2 in $script:pp) { $p2.Dispose() }; $script:pp.Clear() } })

# ---------- timer: anima por TEMPO (nao por quadro), le o arquivo so quando muda ----------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 33
$script:tick = 0
$timer.Add_Tick({
  $script:tick++
  $now = $script:sw.Elapsed.TotalSeconds
  $dt = [math]::Min(0.1, $now - $script:lastT); $script:lastT = $now
  # consulta o arquivo de estado no max ~4x/s
  if (($now - $script:lastChk) -ge 0.25) {
    $script:lastChk = $now
    try {
      $fi = Get-Item -LiteralPath $StateFile -ErrorAction Stop
      if ($fi.LastWriteTimeUtc -ne $script:lastWrite) {
        $script:state = Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:lastWrite = $fi.LastWriteTimeUtc
      }
    } catch { }
  }
  # auto: expande ao entrar em waiting loud; recolhe apos ~10 s sem mouse (nao mexe no userExp salvo)
  $loudNow = [bool]($script:state -and $script:state.mode -eq 'waiting' -and $script:state.loud)
  if ($form.Bounds.Contains([System.Windows.Forms.Cursor]::Position) -or $script:down) { $script:lastAct = $now }
  if ($loudNow -and -not $script:prevLoud -and -not $script:expanded) { $script:expanded = $true; $script:autoExp = $true; $script:lastAct = $now; if ($script:rm) { $script:prog = 1.0 } }
  elseif (-not $env:CW_EXPAND -and $script:autoExp -and $script:expanded -and -not $loudNow -and ($now - $script:lastAct) -gt 10) { $script:expanded = $false; $script:autoExp = $false; if ($script:rm) { $script:prog = 0.0 } }
  $script:prevLoud = $loudNow
  $tgt = if ($script:expanded) { 1.0 } else { 0.0 }
  $moving = $false
  if ($script:prog -ne $tgt) {
    $step = $dt / 0.26
    if ($script:prog -lt $tgt) { $script:prog = [math]::Min($tgt, $script:prog + $step) } else { $script:prog = [math]::Max($tgt, $script:prog - $step) }
    $moving = $true
  }
  $pr = $script:prog; $e = $pr * $pr * (3 - 2 * $pr); $script:e = $e
  if ($moving) {
    $script:curW = $W_SHUT + ($W_OPEN - $W_SHUT) * $e; $script:curH = $H_SHUT + ($script:hOpen - $H_SHUT) * $e
    Apply-Size
    if ($timer.Interval -ne 16) { $timer.Interval = 16 }
  } else {
    if ($timer.Interval -ne 33) { $timer.Interval = 33 }
    # conteudo mudou (ex.: entrou em waiting): ajusta a altura do expandido
    if ($script:expanded -and $script:prog -ge 1.0 -and [math]::Abs($script:curH - $script:hOpen) -ge 1) { $script:curH = $script:hOpen; Apply-Size }
  }
  $quiet = ($script:state -and $script:state.mode -eq 'idle')
  if ($quiet -and -not $moving -and ($script:tick % 8) -ne 0) { return }
  $form.Invalidate()
})
$timer.Start()
[void][System.Windows.Forms.Application]::Run($form)
