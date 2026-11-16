# Claudinho: notch preto na borda direita da tela (sempre no topo): mascote + linhas de uso (5 h, 7 d, contexto, subagentes).
# Mouse: passar num item abre o balao dele (~180 ms); clique num item fixa/solta o balao; duplo clique no mascote reduz/expande;
#   arrastar na vertical muda a posicao; botao direito = menu. A janela nao rouba o foco nem aparece no Alt+Tab.
# Le <StateDir>\<sessionId>.json (um por sessao, gravados pelo mod), relendo so o que mudou; mostra a sessao mais urgente.
# Config em %USERPROFILE%\.claude\claudinho-widget.json (top, compact, reduceMotion; o balao fixado nao persiste); PID em %USERPROFILE%\.claude\claudinho-widget.pid.
# Variaveis de ambiente: CW_REDUCE_MOTION=1 (ou reduceMotion no estado) desliga pulso, giros e pulos do mascote.
#   Depuracao: CW_PIN=mascot|limits|ctx|sub inicia com o balao daquele item fixado; CW_TOP=<px> forca a posicao vertical;
#   CW_COMPACT=0|1 forca expandido/reduzido; CW_NO_PID=1 nao grava nem apaga o arquivo .pid (testes com outro widget aberto);
#   CW_CFG=<arquivo> usa outro arquivo de config (testes sem mexer na config do usuario).
param([string]$StateDir = (Join-Path $env:USERPROFILE '.claude\claudinho\state'))

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Text;
using System.Windows.Forms;
using System.Runtime.InteropServices;
namespace Cw {
  // janela que nao ativa ao mostrar nem ao clicar (WS_EX_NOACTIVATE) e fica fora do Alt+Tab (WS_EX_TOOLWINDOW)
  public class NForm : Form {
    public NForm() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true); }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
      get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x00000080; return cp; }
    }
    protected override void WndProc(ref Message m) {
      if (m.Msg == 0x0021) { m.Result = (IntPtr)3; return; }   // WM_MOUSEACTIVATE -> MA_NOACTIVATE
      base.WndProc(ref m);
    }
  }
  public static class W {
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int k);
    [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint a, uint b, ref int c, uint d);
    [DllImport("user32.dll", EntryPoint = "SystemParametersInfo")] static extern bool SpiRect(uint a, uint b, ref RECT c, uint d);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    // resolucao do relogio do processo (Sleep de 1 ms na Pulse)
    [DllImport("winmm.dll")] public static extern uint timeBeginPeriod(uint p);
    [DllImport("winmm.dll")] public static extern uint timeEndPeriod(uint p);
    // "Efeitos de animacao" do Windows (SPI_GETCLIENTAREAANIMATION)
    public static bool Animations() { int a = 1; return !(SystemParametersInfo(0x1042, 0, ref a, 0) && a == 0); }
    // area de trabalho do monitor principal, sem cache (SPI_GETWORKAREA)
    public static Rectangle WorkArea() {
      RECT r = new RECT();
      if (!SpiRect(0x30, 0, ref r, 0)) return Screen.PrimaryScreen.WorkingArea;
      return Rectangle.FromLTRB(r.L, r.T, r.R, r.B);
    }
    // 1 = a janela em primeiro plano cobre o monitor principal inteiro; 0 = nao; -1 = nao sabe (mantem como esta)
    public static int Fullscreen(int self) {
      IntPtr h = GetForegroundWindow();
      if (h == IntPtr.Zero) return -1;
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid == (uint)self) return -1;
      StringBuilder sb = new StringBuilder(64); GetClassName(h, sb, 64); string c = sb.ToString();
      if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd") return 0;
      if (IsZoomed(h)) return 0;   // maximizada (com barra de tarefas oculta tambem cobre a tela)
      RECT r; if (!GetWindowRect(h, out r)) return -1;
      int cx = GetSystemMetrics(0), cy = GetSystemMetrics(1);
      return (r.L <= 0 && r.T <= 0 && r.R >= cx && r.B >= cy) ? 1 : 0;
    }
  }
  // timer de quadros: o Timer do WinForms arredonda para o tick do sistema (~15,6 ms), entao 33 ms viram ~47 ms (21 fps).
  // Esta conta o tempo numa thread propria e dispara Tick na thread da janela (BeginInvoke), um por vez (sem fila).
  public class Pulse {
    readonly Control owner; volatile int iv = 33; volatile bool run, pending;
    System.Threading.Thread th;
    public event EventHandler Tick;
    public Pulse(Control c) { owner = c; }
    public int Interval { get { return iv; } set { iv = Math.Max(1, value); } }
    public void Start() {
      if (run) return; run = true; W.timeBeginPeriod(1);
      th = new System.Threading.Thread(Loop); th.IsBackground = true; th.Start();
    }
    public void Stop() { if (!run) return; run = false; W.timeEndPeriod(1); }
    void Loop() {
      var sw = System.Diagnostics.Stopwatch.StartNew(); double next = iv;
      while (run) {
        double wait = next - sw.Elapsed.TotalMilliseconds;
        if (wait > 1) { System.Threading.Thread.Sleep((int)wait); continue; }
        if (wait > 0) { System.Threading.Thread.Sleep(0); continue; }
        next += iv; if (next < sw.Elapsed.TotalMilliseconds) next = sw.Elapsed.TotalMilliseconds + iv;   // atrasou: nao acumula
        if (pending || !owner.IsHandleCreated) continue;
        pending = true;
        try { owner.BeginInvoke(new MethodInvoker(Fire)); } catch { pending = false; }
      }
    }
    void Fire() { pending = false; if (!run) return; var h = Tick; if (h != null) h(this, EventArgs.Empty); }
  }
}
'@
[void][Cw.W]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()
$gs0 = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $script:S = $gs0.DpiX / 96.0; $gs0.Dispose()
$script:wa = [Cw.W]::WorkArea()

# ---------- paleta (contraste >= 3:1 sobre preto nos elementos graficos) ----------
$BLACK = '#000000'; $TEXT = '#faf9f5'; $DIM = '#a09d96'; $LINE = '#262626'
$TRK = '#5e5e5e'; $TRKO = '#8a8a8a'          # trilho das barras; trilho do item com balao aberto
$QUIET = '#6b6b66'; $QUIETO = '#9a9a94'      # anel neutro; anel neutro com balao aberto
$GRN = '#5fd38d'; $AMB = '#f5c542'; $RED = '#ff5f56'; $SUBC = '#f472b6'
$BLACKC = [System.Drawing.ColorTranslator]::FromHtml($BLACK)

$script:state = $null; $script:vm = $null; $script:viewVer = 0
$script:sess = @{}; $script:selKey = ''; $script:liveN = 0; $script:everState = $false; $script:lastPal = $null
$script:ack = @{}; $script:ackVer = 0; $script:ackPending = $false; $script:forceView = $false; $script:lastGc = -999.0
$script:brushes = @{}
$script:pens = @{}
$script:memo = @{}   # textos cortados/medidos; limpo quando o estado exibido muda
$script:sw = [System.Diagnostics.Stopwatch]::StartNew()
$script:lastMode = ''; $script:prevMode = ''; $script:codingEnd = 0.0; $script:introSkip = $false
$script:modeT0 = 0.0
$script:lastT = 0.0; $script:lastChk = -1.0; $script:lastScr = 0.0; $script:lastFs = -1.0
$script:lastAct = 0.0; $script:prevLoud = $false; $script:alertKey = ''; $script:dismissKey = ''
$script:rm = $false; $script:reducePref = $false
$script:reduce = ($env:CW_REDUCE_MOTION -eq '1')
try { if (-not [Cw.W]::Animations()) { $script:reduce = $true } } catch { }

# geometria do notch (px logicos)
$NW = 72.0; $FL = 24.0; $RAD = 18.0        # largura da faixa, alargamento concavo (expandido), raio dos cantos esquerdos
$FLC = 14.0; $MR = 32.0                    # alargamento no modo reduzido; raio do anel do mascote
$script:flare = $FL
$BWID = 250.0; $ARW = 12.0; $GAPW = 4.0    # balao: largura, comprimento da seta, vao ate a faixa
# layout interno do balao
$BM = 16.0; $BCW = $BWID - 2 * $BM          # margem e largura util (218)
$BTOP = 14.0; $BBOT = 12.0                  # folga em cima e embaixo
$LH_HEAD = 28.0; $LH_BODY = 22.0; $LH_SMALL = 18.0; $LH_WRAP = 20.0; $LH_SEP = 10.0
$HOVER_IN = 0.18; $HOVER_OUT = 0.4          # atraso para abrir / fechar o balao por hover (s)
$DBL = [System.Windows.Forms.SystemInformation]::DoubleClickTime / 1000.0
$script:items = New-Object System.Collections.ArrayList
$script:curH = 0.0; $script:tgtH = 0.0
$script:hov = ''; $script:hovCand = ''; $script:hovCandAt = 0.0
$script:pinned = ''; $script:alert = $false; $script:leaveAt = 0.0; $script:openKey = ''; $script:compact = $false
$script:balH = 0.0; $script:balKey = ''; $script:geo = $null; $script:shapeKey = ''; $script:boundsKey = ''; $script:inval = $true
$script:down = $false; $script:moved = $false; $script:clickK = ''; $script:clickT = -9.0; $script:pinBefore = ''
$script:pt = [System.Globalization.CultureInfo]::GetCultureInfo('pt-BR')

# ---------- log: uma linha por mensagem distinta a cada 60 s; arquivo limitado a ~200 KB ----------
$LOG = Join-Path $env:TEMP 'cw-log.txt'
$script:logT = @{}
function Log([string]$m) {
  $now = $script:sw.Elapsed.TotalSeconds
  if ($script:logT.ContainsKey($m) -and ($now - $script:logT[$m]) -lt 60) { return }
  if ($script:logT.Count -gt 200) { $script:logT.Clear() }
  $script:logT[$m] = $now
  try {
    $fi = New-Object System.IO.FileInfo $LOG
    if ($fi.Exists -and $fi.Length -gt 200KB) {
      $all = [System.IO.File]::ReadAllText($LOG)
      [System.IO.File]::WriteAllText($LOG, $all.Substring([math]::Max(0, $all.Length - 100KB)))
    }
    [System.IO.File]::AppendAllText($LOG, ('{0:yyyy-MM-dd HH:mm:ss} {1}{2}' -f (Get-Date), $m, [Environment]::NewLine))
  } catch { }
}

function Br([string]$hex, [int]$a = 255) {
  $a = [int]([math]::Min(255, [math]::Max(16, [math]::Round($a / 16.0) * 16)))
  $k = "$hex|$a"
  $b = $script:brushes[$k]
  if (-not $b) {
    $c = [System.Drawing.ColorTranslator]::FromHtml($hex)
    $b = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($a, $c))
    $script:brushes[$k] = $b
  }
  $b
}
function Pn([string]$hex, [single]$w, [int]$a = 255) {
  $a = [int]([math]::Min(255, [math]::Max(16, [math]::Round($a / 16.0) * 16)))
  $k = "$hex|$w|$a"
  $p = $script:pens[$k]
  if (-not $p) {
    $c = [System.Drawing.ColorTranslator]::FromHtml($hex)
    $p = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($a, $c)), $w
    $p.StartCap = 'Round'; $p.EndCap = 'Round'; $p.LineJoin = 'Round'
    $script:pens[$k] = $p
  }
  $p
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

function F([string]$n, [double]$sz, $st = 'Regular') { New-Object System.Drawing.Font($n, [single]($sz * 96 / 72), [System.Drawing.FontStyle]$st, [System.Drawing.GraphicsUnit]::Pixel) }
$fHead = (F 'Segoe UI' 11 'Bold')
$fName = (F 'Segoe UI' 8.5 'Bold')
$fBody = (F 'Segoe UI' 9.5)
$fSmall = (F 'Segoe UI' 9)
$fRing = (F 'Segoe UI' 9 'Bold')
$fMono = (F 'Consolas' 9)
$fMonoB = (F 'Consolas' 11 'Bold')
$center = New-Object System.Drawing.StringFormat; $center.Alignment = 'Center'; $center.FormatFlags = 'NoWrap'
$left = New-Object System.Drawing.StringFormat; $left.FormatFlags = 'NoWrap'
$right = New-Object System.Drawing.StringFormat; $right.Alignment = 'Far'; $right.FormatFlags = 'NoWrap'
# superficie so para medir texto fora do Paint (mesma escala do Paint, para medir igual)
$script:mg = [System.Drawing.Graphics]::FromImage((New-Object System.Drawing.Bitmap 1, 1))
$script:mg.TextRenderingHint = 'ClearTypeGridFit'
$script:mg.ScaleTransform([single]$script:S, [single]$script:S)

function NowMs { [double][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
function Num($x) { if ($null -eq $x) { return 0.0 }; try { [double]$x } catch { 0.0 } }
function IsHex([string]$s) { $s -match '^#[0-9a-fA-F]{6}$' }
# duracao unica para tudo: "45 s", "12 min", "1 h 05"
function Dur([double]$ms) {
  $t = [long][math]::Floor([math]::Max(0, $ms) / 1000)
  if ($t -lt 60) { return ('{0} s' -f $t) }
  $m = [long][math]::Floor($t / 60)
  if ($m -lt 60) { return ('{0} min' -f $m) }
  '{0} h {1:00}' -f [long][math]::Floor($m / 60), ($m % 60)
}
# historico: "agora" nos primeiros 5 s, depois a mesma duracao
function Rel([double]$nowMs, $t) { $d = $nowMs - (Num $t); if ($d -lt 5000) { 'agora' } else { Dur $d } }
# numero curto sem casas inuteis (pt-BR): 70k, 1,2M
function KS($n) { $n = Num $n; if ($n -ge 1e6) { ($n / 1e6).ToString('0.#', $script:pt) + 'M' } elseif ($n -ge 1e3) { ($n / 1e3).ToString('0', $script:pt) + 'k' } else { $n.ToString('0', $script:pt) } }
function K($n) { $n = Num $n; if ($n -ge 1e6) { ($n / 1e6).ToString('N2', $script:pt) + 'M' } elseif ($n -ge 1e3) { ($n / 1e3).ToString('N1', $script:pt) + 'k' } else { $n.ToString('0', $script:pt) } }
# "reinicia em 51 min" / "reinicia em 3 h 20" / "reinicia qui 00:00"
function ResetTxt([double]$ms, [double]$nowMs) {
  if ($ms -le 0) { return '' }
  $d = $ms - $nowMs
  if ($d -le 0) { return 'reiniciando' }
  if ($d -lt 86400000) { if ($d -ge 60000) { $d = [math]::Ceiling($d / 60000) * 60000 }; return ('reinicia em ' + (Dur $d)) }
  $dt = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$ms).LocalDateTime
  $dias = 'dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'
  'reinicia {0} {1:HH:mm}' -f $dias[[int]$dt.DayOfWeek], $dt
}
# um so par de limiares (barras, numero e aviso do modo reduzido): verde < 75, ambar 75-89, vermelho >= 90
function Band([double]$p) { if ($p -ge 90) { $RED } elseif ($p -ge 75) { $AMB } else { $GRN } }

# largura medida (com cache)
function MW($g, [string]$s, $font) {
  $k = 'w|' + $font.GetHashCode() + '|' + $s
  $r = $script:memo[$k]
  if ($null -eq $r) { $r = $g.MeasureString($s, $font).Width; $script:memo[$k] = $r }
  $r
}
# corta pelo tamanho real do texto, com "…" (cache por texto + fonte + largura)
function ClipW($g, [string]$s, $font, [double]$max) {
  $k = 'c|' + $font.GetHashCode() + '|' + $max + '|' + $s
  $r = $script:memo[$k]
  if ($null -ne $r) { return $r }
  if ($g.MeasureString($s, $font).Width -le $max) { $r = $s }
  else {
    $lo = 1; $hi = $s.Length - 1
    while ($lo -lt $hi) {
      $m2 = [int][math]::Ceiling(($lo + $hi) / 2.0)
      if ($g.MeasureString($s.Substring(0, $m2) + '…', $font).Width -le $max) { $lo = $m2 } else { $hi = $m2 - 1 }
    }
    $r = $s.Substring(0, [math]::Max(1, $lo)).TrimEnd() + '…'
  }
  $script:memo[$k] = $r
  $r
}
# quebra em ate $maxN linhas; se sobrar texto, a ultima termina em "…"
function Wrap($g, [string]$s, $font, [double]$max, [int]$maxN) {
  $k = 'r|' + $font.GetHashCode() + '|' + $max + '|' + $maxN + '|' + $s
  $r = $script:memo[$k]
  if ($null -ne $r) { return $r }
  $out = New-Object System.Collections.ArrayList
  $words = New-Object System.Collections.ArrayList
  foreach ($w0 in ($s -split '\s+')) { if ($w0) { [void]$words.Add($w0) } }
  $acc = ''; $i = 0
  while ($i -lt $words.Count -and $out.Count -lt $maxN) {
    $wd = [string]$words[$i]
    $try = $(if ($acc) { $acc + ' ' + $wd } else { $wd })
    if ($g.MeasureString($try, $font).Width -le $max) { $acc = $try; $i++; continue }
    if ($acc) { [void]$out.Add($acc); $acc = ''; continue }
    # palavra sozinha maior que a linha: quebra no meio
    $n = $wd.Length - 1
    while ($n -gt 1 -and $g.MeasureString($wd.Substring(0, $n), $font).Width -gt $max) { $n-- }
    [void]$out.Add($wd.Substring(0, $n)); $words[$i] = $wd.Substring($n)
  }
  if ($acc -and $out.Count -lt $maxN) { [void]$out.Add($acc); $acc = '' }
  if ($i -lt $words.Count -and $out.Count -gt 0) {
    $rest = ($words.GetRange($i, $words.Count - $i).ToArray()) -join ' '
    $out[$out.Count - 1] = ClipW $g ([string]$out[$out.Count - 1] + ' ' + $rest) $font $max
  }
  $r = $out.ToArray()
  $script:memo[$k] = $r
  $r
}

function Mix([string]$a, [string]$b, [double]$k) {
  $x = [System.Drawing.ColorTranslator]::FromHtml($a); $y = [System.Drawing.ColorTranslator]::FromHtml($b)
  '#{0:x2}{1:x2}{2:x2}' -f [int]($x.R + ($y.R - $x.R) * $k), [int]($x.G + ($y.G - $x.G) * $k), [int]($x.B + ($y.B - $x.B) * $k)
}

# ---------- o bichinho (pixel-art como no app do Claude), animado por tempo ----------
# Poses: de frente, virando, agachado. Unico adereço: o notebook no Codando (o anel ao redor comunica o estado).
# Desenha um retangulo em "unidades de pixel" do bichinho (usa $script:mgx e $script:mu definidos em Draw-Mascot)
# (pincel opaco por cor num mapa direto: chamar Br aqui custava ~3x mais por retangulo, e sao ~20 por quadro)
$script:ubr = @{}
function U($hex, $x, $y, $w, $h) {
  $b = $script:ubr[$hex]; if (-not $b) { $b = Br $hex; $script:ubr[$hex] = $b }
  $u = $script:mu; $script:mgx.FillRectangle($b, [single]($x * $u), [single]($y * $u), [single]($w * $u), [single]($h * $u))
}
function Draw-Mascot($g, [single]$cx, [single]$gy, [single]$p, $v, [double]$t, [double]$age, [double]$range) {
  $mode = [string]$v.mode; $loud = [bool]$v.loud
  $B = $v.B; $shade = $v.shade; $deep = $v.deep
  $u = [math]::Max(1.0, [math]::Round(2.0 * $p * $script:S)) / $script:S    # alinhado ao pixel do dispositivo; 1 "pixel" do bichinho; corpo de frente = 16 x 16 pixels (+ bracos)
  $script:mu = $u; $script:mgx = $g
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
      'offline' { $eyes = 'closed' }   # Claude Code fechado: parado, sem respirar
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

# ---------- estado: um JSON por sessao em $StateDir ----------
function SidOf($e) { if ($e.sid) { $e.sid } else { $e.path } }
function DoneUnacked($o, [string]$sid) {
  $da = Num $o.doneAt
  if ($da -le 0) { return $false }
  $m = [string]$o.mode
  if (-not (($m -eq 'waiting' -and -not $o.loud) -or $m -eq 'idle')) { return $false }
  -not ($script:ack.ContainsKey($sid) -and $script:ack[$sid] -ge $da)
}
# urgencia: waiting+loud > error > thinking/coding/reading > done (ou terminou nao visto) > waiting > idle
function Rank($o, [string]$sid) {
  $m = [string]$o.mode
  if ($m -eq 'waiting' -and $o.loud) { return 6 }
  if ($m -eq 'error') { return 5 }
  if ($m -eq 'thinking' -or $m -eq 'coding' -or $m -eq 'reading') { return 4 }
  if ($m -eq 'done' -or (DoneUnacked $o $sid)) { return 3 }
  if ($m -eq 'waiting') { return 2 }
  1
}
# lista a pasta, rele so o que mudou, descarta sessoes mortas e escolhe a exibida; $true se a escolha/conteudo mudou
function Scan-State([double]$nowMs) {
  $files = $null
  try { if ([System.IO.Directory]::Exists($StateDir)) { $files = [System.IO.Directory]::GetFiles($StateDir, '*.json') } } catch { }
  $seen = @{}
  if ($files) {
    foreach ($f in $files) {
      if (-not $f.EndsWith('.json')) { continue }
      $seen[$f] = 1
      $e = $script:sess[$f]
      if (-not $e) { $e = @{ path = $f; wt = [datetime]::MinValue; fwt = [datetime]::MinValue; st = $null; sid = ''; alive = $false }; $script:sess[$f] = $e }
      try {
        $wt = [System.IO.File]::GetLastWriteTimeUtc($f); $e.fwt = $wt
        if ($wt -ne $e.wt) {
          # leitura parcial / JSON invalido: cai no catch e tenta de novo no proximo ciclo
          $o = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8))
          if ($o -and $o.mode) { $e.st = $o; $e.sid = [string]$o.sid; $script:everState = $true }
          $e.wt = $wt
        }
      } catch { }
    }
  }
  $gc = (($script:sw.Elapsed.TotalSeconds - $script:lastGc) -ge 60)
  if ($gc) { $script:lastGc = $script:sw.Elapsed.TotalSeconds }
  $live = 0; $best = $null; $bestE = $null; $bestR = -1; $bestTs = -1.0
  foreach ($f in @($script:sess.Keys)) {
    if (-not $seen.ContainsKey($f)) { $script:sess.Remove($f); continue }
    $e = $script:sess[$f]; $o = $e.st
    $ts = 0.0; if ($o) { $ts = Num $o.ts }
    $alive = ($o -and $o.offline -ne $true -and ($nowMs - $ts) -le 20000)
    $e.alive = $alive
    if (-not $alive) {
      # morta ha mais de 1 h: apaga o arquivo
      # nunca interpretada (JSON corrompido): apaga com mais de 2 min sem escrita (guarda contra gravacao em andamento)
      $stale = $(if ($o) { ([datetime]::UtcNow - $e.fwt).TotalHours -gt 1 -and ($nowMs - $ts) -gt 3600000 } else { ([datetime]::UtcNow - $e.fwt).TotalMinutes -gt 2 })
      if ($gc -and $stale) {
        try { [System.IO.File]::Delete($f); $script:sess.Remove($f) } catch { }
      }
      continue
    }
    $live++
    $sid = SidOf $e
    $r = Rank $o $sid
    if ($r -gt $bestR -or ($r -eq $bestR -and $ts -gt $bestTs)) { $bestR = $r; $bestTs = $ts; $best = $o; $bestE = $e }
  }
  $script:state = $best; $script:liveN = $live
  if ($best) { $script:stateSid = SidOf $bestE; if ($best.palette) { $script:lastPal = $best.palette } } else { $script:stateSid = '' }
  $k = '{0}|{1}|{2}|{3}|{4}' -f $(if ($bestE) { $bestE.path + '|' + $bestE.wt.Ticks } else { '' }), $live, $script:ackVer, $script:everState, $bestR
  if ($k -ne $script:selKey) { $script:selKey = $k; return $true }
  $false
}
# o usuario viu o widget: reconhece o "terminou" de todas as sessoes vivas
function Ack-All {
  foreach ($e in @($script:sess.Values)) {
    if ($e.alive -and $e.st) { $da = Num $e.st.doneAt; if ($da -gt 0) { $script:ack[(SidOf $e)] = $da } }
  }
  $script:ackVer++; $script:forceView = $true
}
function Calc-Rm { $script:rm = ($script:reduce -or $script:reducePref -or ($script:vm -and $script:vm.rmState)) }

# tudo o que so depende do estado exibido: calculado uma vez por mudanca, nao por quadro
function Update-View([double]$nowMs) {
  $script:memo.Clear()
  $script:viewVer++
  $cur = $script:state
  $v = @{
    off = $true; mode = 'offline'; loud = $false; name = ''; ncol = $TEXT; shortTxt = ''; scol = $DIM; ring = 'quiet'; col = $TEXT
    rows = (New-Object System.Collections.ArrayList); agents = @(); agentsN = 0; hist = @(); top = @(); lim = @{}
    warn = ''; doneShow = $false; doneAt = 0.0; nextExp = 0.0; alertKey = ''; summary = ''; moreTxt = ''; rmState = $false
  }
  $B = '#d97757'; $D = '#a8553a'
  $pal = $script:lastPal
  if ($pal) { if (IsHex ([string]$pal.B)) { $B = [string]$pal.B }; if (IsHex ([string]$pal.D)) { $D = [string]$pal.D } }
  $v.B = $B; $v.shade = Mix $B $D 0.4; $v.deep = Mix $D '#1c1410' 0.6
  if (-not $cur) {
    $v.shortTxt = 'Fechado'
    if ($script:everState) { $v.offTitle = 'Claude Code fechado'; $v.offHint = 'volta sozinho quando uma sessão abrir' }
    else { $v.offTitle = 'Aguardando o Claude Code…'; $v.offHint = 'abra uma sessão com o mod ativo' }
  } else {
    $v.off = $false
    $mode = [string]$cur.mode; $loud = [bool]$cur.loud
    $v.mode = $mode; $v.loud = $loud
    $col = [string]$cur.color; if (-not (IsHex $col)) { $col = $TEXT }
    $v.col = $col
    $nm = [string]$cur.name; if (-not $nm) { $nm = 'Claudinho' }
    $v.name = $nm
    $v.ncol = $(if ($mode -eq 'idle') { $TEXT } else { $col })
    $sh = [string]$cur.short; if (-not $sh) { $sh = ($nm -split '/')[0] }
    $v.shortTxt = ClipW $script:mg $sh $fName ($NW - 4)
    $v.scol = $(if ($mode -eq 'idle') { $DIM } else { $col })
    $v.project = [string]$cur.project
    $v.label = [string]$cur.label
    $v.model = [string]$cur.model; if (-not $v.model) { $v.model = '—' }
    $v.main = [string]$cur.ask; if (-not $v.main) { $v.main = $v.label }
    $v.waitSince = Num $cur.waitSince
    $v.sessStart = Num $cur.sessionStart
    $v.turnStart = $(if ($mode -eq 'thinking' -or $mode -eq 'coding' -or $mode -eq 'reading' -or $mode -eq 'error') { Num $cur.turnStart } else { 0.0 })
    $v.rmState = ($cur.reduceMotion -eq $true)
    $v.alertKey = '{0}|{1}|{2}' -f $script:stateSid, $v.waitSince, $cur.ask
    # limites: sem leitura = nao aparece; janela ja reiniciou sem leitura nova = "—" (stale)
    foreach ($l in @($cur.limits)) {
      if (-not $l -or $null -eq $l.pct) { continue }
      $kd = [string]$l.kind
      if ($v.lim.ContainsKey($kd)) { continue }
      $ra = Num $l.resetsAt
      $stale = ($ra -gt 0 -and $ra -lt $nowMs)
      $pc = $null; if (-not $stale) { $pc = [math]::Max(0, [math]::Min(100, (Num $l.pct))) }
      $v.lim[$kd] = @{ pct = $pc; reset = $ra; stale = $stale }
      if (-not $stale -and $ra -gt 0 -and ($v.nextExp -le 0 -or $ra -lt $v.nextExp)) { $v.nextExp = $ra }
    }
    $v.ctx = $null; if ($null -ne $cur.ctxPct) { $v.ctx = [math]::Max(0, [math]::Min(100, (Num $cur.ctxPct))) }
    $ags = New-Object System.Collections.ArrayList
    foreach ($a in @($cur.agents)) { if ($a) { [void]$ags.Add($a) } }
    $v.agents = $ags; $v.agentsN = $ags.Count
    $hl = New-Object System.Collections.ArrayList
    foreach ($hi in @($cur.history)) { if ($hi -and $hl.Count -lt 3) { [void]$hl.Add($hi) } }
    $v.hist = $hl
    $tl = New-Object System.Collections.ArrayList
    foreach ($tp in @($cur.top)) { if ($tp) { [void]$tl.Add(('{0} ×{1}' -f $tp[0], $tp[1])) } }
    $v.top = $tl
    $tk = $cur.tokens
    $v.tokIn = $(if ($tk) { K $tk.in } else { '—' }); $v.tokOut = $(if ($tk) { K $tk.out } else { '—' })
    $v.cacheTxt = $(if ($tk) { 'cache ' + (K $tk.cache) } else { 'tokens aparecem após o 1º turno' })
    $v.usdT = $(if ($null -ne $cur.usd) { 'US$ ' + (Num $cur.usd).ToString('N2', $script:pt) } else { '—' })
    $v.ctxTokT = $(if ($null -ne $cur.ctxTok -and $null -ne $cur.ctxWin) { (KS $cur.ctxTok) + ' / ' + (KS $cur.ctxWin) } else { '' })
    # aviso do modo reduzido: o maior entre 5 h, 7 d e contexto
    $mx = -1.0
    foreach ($kd in 'five_hour', 'seven_day') { $l = $v.lim[$kd]; if ($l -and $null -ne $l.pct) { $mx = [math]::Max($mx, $l.pct) } }
    if ($null -ne $v.ctx) { $mx = [math]::Max($mx, $v.ctx) }
    if ($mx -ge 75) { $v.warn = Band $mx }
    # "terminou" persistente ate o usuario passar o mouse
    $v.doneAt = Num $cur.doneAt
    $v.doneShow = DoneUnacked $cur $script:stateSid
    if ($mode -eq 'waiting' -and $loud) { $v.ring = 'loud' }
    elseif ($mode -eq 'error') { $v.ring = 'error' }
    elseif ($mode -eq 'done' -or $v.doneShow) { $v.ring = 'done' }
    elseif ($mode -eq 'thinking' -or $mode -eq 'coding' -or $mode -eq 'reading') { $v.ring = 'spin' }
    # linhas de uso (expandido) e resumo para o balao do mascote (reduzido)
    $parts = New-Object System.Collections.ArrayList
    foreach ($spec in @(@('five_hour', '5h'), @('seven_day', '7d'))) {
      $l = $v.lim[$spec[0]]
      if (-not $l) { continue }
      $rw = @{ k = $spec[0]; bal = 'limits'; lab = $spec[1]; val = '—'; vcol = $TEXT; pv = $null; fill = $GRN }
      if ($null -ne $l.pct) { $rw.pv = $l.pct; $rw.val = '{0}%' -f [math]::Round($l.pct); $rw.fill = Band $l.pct; if ($l.pct -ge 75) { $rw.vcol = $rw.fill } }
      [void]$v.rows.Add($rw); [void]$parts.Add(('{0} {1}' -f $spec[1], $rw.val))
    }
    $rw = @{ k = 'ctx'; bal = 'ctx'; lab = 'ctx'; val = '—'; vcol = $TEXT; pv = $null; fill = $GRN }
    if ($null -ne $v.ctx) { $rw.pv = $v.ctx; $rw.val = '{0}%' -f [math]::Round($v.ctx); $rw.fill = Band $v.ctx; if ($v.ctx -ge 75) { $rw.vcol = $rw.fill }; [void]$parts.Add(('ctx {0}' -f $rw.val)) }
    [void]$v.rows.Add($rw)
    if ($v.agentsN -gt 0) {
      [void]$v.rows.Add(@{ k = 'sub'; bal = 'sub'; lab = 'sub'; val = [string]$v.agentsN; vcol = $SUBC; pv = $null; fill = $SUBC })
      [void]$parts.Add(('{0} sub' -f $v.agentsN))
    }
    $v.summary = $parts.ToArray() -join ' · '
    if ($script:liveN -gt 1) { $n = $script:liveN - 1; $v.moreTxt = $(if ($n -eq 1) { '+1 sessão' } else { '+{0} sessões' -f $n }) }
  }
  $script:vm = $v
  Calc-Rm
  $script:balKey = ''; $script:inval = $true
}

# ---------- itens da faixa ----------
function Find-Item([string]$key) {
  foreach ($it in $script:items) { if ($it.k -eq $key) { return $it } }
  if ($key -eq 'five_hour') { foreach ($it in $script:items) { if ($it.k -eq 'seven_day') { return $it } } }
  if ($key -eq 'seven_day') { foreach ($it in $script:items) { if ($it.k -eq 'five_hour') { return $it } } }
  $null
}
function Rebuild-Items {
  $v = $script:vm
  $script:items.Clear()
  # reduzido: so a bolinha do mascote, sem o nome do estado (a cor do anel ja diz), com menos folga e alargamento menor
  $script:flare = $(if ($script:compact) { $FLC } else { $FL })
  $padV = $(if ($script:compact) { 7.0 } else { 14.0 })
  $mh = $(if ($script:compact) { 2 * $MR + 4 } else { 2 * $MR + 24 })
  $y = $script:flare + $padV
  $lastGap = 12.0
  [void]$script:items.Add(@{ k = 'mascot'; bal = 'mascot'; y = $y; h = $mh; cy = ($y + $MR + 2); pad = 6.0 }); $y += $mh + $lastGap
  # expandido: bloco de uso em linhas (rotulo, valor e barra fina); o detalhe fica no balao
  if (-not $script:compact -and $v -and -not $v.off -and $v.rows.Count -gt 0) {
    $y += 4   # folga da linha separadora
    foreach ($rw in $v.rows) {
      [void]$script:items.Add(@{ k = $rw.k; bal = $rw.bal; y = $y; h = 22.0; cy = ($y + 11.0); pad = 4.0; row = $rw })
      $lastGap = 8.0; $y += 22 + $lastGap
    }
  }
  $script:tgtH = $y - $lastGap + $padV + $script:flare
  if ($script:curH -le 0) { $script:curH = $script:tgtH }
  $script:inval = $true
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
function Sep($g, [double]$y) { if ($script:dr) { Rect $g $LINE $BM $y $BCW 1 } }
# chips das ferramentas: ate 2 linhas; o que nao couber vira "+N" (nunca some em silencio)
function Chips($g, $tops) {
  $r = $script:memo['chips']
  if ($null -ne $r) { return ,$r }
  $chips = New-Object System.Collections.ArrayList
  $row = 0; $x = $BM; $over = 0; $lim = $BWID - $BM
  foreach ($ct in $tops) {
    if ($over -gt 0) { $over++; continue }
    $cwid = (MW $g $ct $fSmall) + 8
    if ($x + $cwid -gt $lim -and $x -gt $BM) { $row++; $x = $BM }
    if ($row -ge 2) { $over = 1; continue }
    [void]$chips.Add(@($ct, $row, $x, $cwid)); $x += $cwid + 6
  }
  while ($over -gt 0 -and $chips.Count -gt 0) {
    $lt = '+' + $over; $lw = (MW $g $lt $fSmall) + 8
    $lc = $chips[$chips.Count - 1]
    if (($lc[2] + $lc[3] + 6 + $lw) -le $lim) { [void]$chips.Add(@($lt, $lc[1], ($lc[2] + $lc[3] + 6), $lw)); break }
    $chips.RemoveAt($chips.Count - 1); $over++
  }
  $script:memo['chips'] = $chips
  ,$chips
}

function Draw-Balloon($g, [string]$bal, [bool]$dr, [double]$nowMs) {
  $script:dr = $dr
  $v = $script:vm; $y = $BTOP
  if ($v.off) {
    Tx $g $v.offTitle $fHead $TEXT $BM $y; $y += $LH_HEAD
    Tx $g (ClipW $g $v.offHint $fSmall $BCW) $fSmall $DIM $BM $y $BCW; $y += $LH_SMALL
    return ($y + $BBOT)
  }
  switch ($bal) {
    'mascot' {
      Tx $g $v.name $fHead $v.ncol $BM $y
      $nw = (MW $g $v.name $fHead) - 4; $pw = $BCW - $nw - 8
      if ($v.project -and $pw -gt 30) { Tx $g (ClipW $g $v.project $fBody $pw) $fBody $DIM ($BM + $nw + 8) ($y + 2) $pw }
      $y += $LH_HEAD
      if ($v.doneShow) { Tx $g ('terminou há ' + (Dur ($nowMs - $v.doneAt))) $fSmall $GRN $BM $y; $y += $LH_SMALL }
      if ($v.mode -eq 'waiting') {
        foreach ($wl in (Wrap $g $v.main $fBody $BCW 3)) { Tx $g $wl $fBody $TEXT $BM $y $BCW; $y += $LH_WRAP }
        if ($v.waitSince -gt 0) { Tx $g ('aguardando há ' + (Dur ($nowMs - $v.waitSince))) $fSmall $DIM $BM $y; $y += $LH_SMALL }
      } else {
        Tx $g (ClipW $g $v.label $fBody $BCW) $fBody $DIM $BM $y $BCW; $y += $LH_BODY
      }
      Sep $g ($y + 2); $y += $LH_SEP
      Tx $g 'Modelo' $fSmall $DIM $BM ($y + 1)
      Tx $g (ClipW $g $v.model $fBody 150) $fBody $TEXT $BM $y $BCW $right; $y += $LH_BODY
      $turn = $(if ($v.turnStart -gt 0) { Dur ($nowMs - $v.turnStart) } else { '—' })
      $sdur = $(if ($v.sessStart -gt 0) { Dur ($nowMs - $v.sessStart) } else { '—' })
      Tx $g ('sessão {0} · turno {1}' -f $sdur, $turn) $fSmall $DIM $BM $y; $y += $LH_BODY
      if ($v.moreTxt) { Tx $g $v.moreTxt $fSmall $DIM $BM ($y - 2); $y += $LH_SMALL }
      # reduzido: as linhas de uso estao escondidas, entao o resumo delas vem aqui
      if ($script:compact -and $v.summary) { Tx $g (ClipW $g $v.summary $fSmall $BCW) $fSmall $TEXT $BM $y $BCW; $y += $LH_BODY }
      Sep $g ($y + 2); $y += $LH_SEP
      Tx $g 'ATIVIDADE RECENTE' $fSmall $DIM $BM $y; $y += $LH_WRAP
      if ($v.hist.Count -eq 0) { Tx $g 'nada ainda' $fSmall $DIM $BM $y; $y += $LH_SMALL }
      foreach ($hi in $v.hist) {
        Tx $g (Rel $nowMs $hi.t) $fMono $DIM $BM $y
        Tx $g (ClipW $g ([string]$hi.text) $fSmall ($BCW - 50)) $fSmall $TEXT ($BM + 50) ($y + 1) ($BCW - 50)
        $y += $LH_SMALL
      }
    }
    'limits' {
      Tx $g 'Limites de uso' $fHead $TEXT $BM $y; $y += $LH_HEAD
      $first = $true
      foreach ($spec in @(@('five_hour', 'Sessão de 5 h'), @('seven_day', 'Semana'), @('spend_limit', 'Limite de gasto'))) {
        $lm = $v.lim[$spec[0]]
        if (-not $lm) { continue }
        if (-not $first) { $y += 8 }; $first = $false
        Tx $g $spec[1] $fBody $TEXT $BM $y
        $rt = $(if ($lm.stale) { 'janela reiniciou' } else { ResetTxt $lm.reset $nowMs })
        if ($rt) { Tx $g $rt $fSmall $DIM $BM ($y + 1) $BCW $right }
        $y += $LH_BODY
        if ($null -ne $lm.pct) {
          Bar $g $BM $y $BCW $lm.pct (Band $lm.pct); $y += 14
          Tx $g ('{0}% usado' -f [math]::Round($lm.pct)) $fSmall $DIM $BM $y
        } else {
          Bar $g $BM $y $BCW $null $GRN; $y += 14
          Tx $g '— aguardando leitura nova' $fSmall $DIM $BM $y
        }
        $y += $LH_SMALL
      }
    }
    'ctx' {
      Tx $g 'Contexto' $fHead $TEXT $BM $y; $y += $LH_HEAD
      if ($null -ne $v.ctx) {
        Tx $g ('{0}%' -f [math]::Round($v.ctx)) $fMonoB $TEXT $BM $y
        if ($v.ctxTokT) { Tx $g $v.ctxTokT $fSmall $DIM $BM ($y + 2) $BCW $right }
      } else { Tx $g 'sem dados' $fSmall $DIM $BM ($y + 2) }
      $y += 24
      Bar $g $BM $y $BCW $v.ctx $(if ($null -ne $v.ctx) { Band $v.ctx } else { $DIM }); $y += 18
      Sep $g $y; $y += $LH_SEP
      $cols = @(@('entrada', $v.tokIn), @('saída', $v.tokOut), @('custo', $v.usdT))
      for ($i = 0; $i -lt 3; $i++) {
        Tx $g $cols[$i][1] $fMonoB $TEXT ($BM + $i * 76) $y
        Tx $g $cols[$i][0] $fSmall $DIM ($BM + $i * 76) ($y + 17)
      }
      $y += 40
      Tx $g $v.cacheTxt $fSmall $DIM $BM $y
      $y += $LH_BODY
      Sep $g $y; $y += $LH_SEP
      Tx $g 'FERRAMENTAS' $fSmall $DIM $BM $y; $y += $LH_WRAP
      $chips = Chips $g $v.top
      if ($chips.Count -eq 0) { Tx $g 'nenhuma ainda' $fSmall $DIM $BM $y; $y += $LH_WRAP }
      else {
        $nrow = 1
        foreach ($ch in $chips) {
          if ($ch[1] + 1 -gt $nrow) { $nrow = $ch[1] + 1 }
          $cyy = $y + $ch[1] * 26
          if ($script:dr) { $g.FillPath((Br $LINE), (RoundPath $ch[2] $cyy $ch[3] 22 11)) }
          Tx $g $ch[0] $fSmall $DIM ($ch[2] + 4) ($cyy + 3)
        }
        $y += 22 + ($nrow - 1) * 26
      }
    }
    'sub' {
      Tx $g ('Subagentes · ' + $v.agentsN) $fHead $TEXT $BM $y; $y += $LH_HEAD
      $shown = 0
      foreach ($ag in $v.agents) {
        if ($shown -ge 5) { break }
        $am = [string]$ag.model; $amw = 0
        if ($am) { $am = ClipW $g $am $fSmall 80; $amw = (MW $g $am $fSmall) + 6; Tx $g $am $fSmall $DIM $BM ($y + 1) $BCW $right }
        $ad = [string]$ag.desc; if (-not $ad) { $ad = [string]$ag.type }
        Tx $g (ClipW $g $ad $fBody ($BCW - $amw)) $fBody $TEXT $BM $y ($BCW - $amw)
        $y += $LH_BODY; $shown++
      }
      if ($v.agentsN -gt 5) { Tx $g ('+' + ($v.agentsN - 5) + ' em andamento') $fSmall $DIM $BM $y; $y += $LH_WRAP }
    }
  }
  $y + $BBOT
}

# ---------- janela ----------
$form = New-Object Cw.NForm
$form.FormBorderStyle = 'None'; $form.TopMost = $true; $form.ShowInTaskbar = $false
$form.StartPosition = 'Manual'; $form.BackColor = $BLACKC
$script:top = $script:wa.Top + 70 * $script:S
# config salva: posicao, modo reduzido e reduzir movimento (o balao fixado nao persiste; "pin" de configs antigas e ignorado)
$CFG = $(if ($env:CW_CFG) { $env:CW_CFG } else { "$env:USERPROFILE\.claude\claudinho-widget.json" })
$PIDF = "$env:USERPROFILE\.claude\claudinho-widget.pid"
try {
  if (Test-Path -LiteralPath $CFG) {
    $sv = Get-Content -LiteralPath $CFG -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -ne $sv.top -and [double]$sv.top -ge $script:wa.Top -and [double]$sv.top -le ($script:wa.Bottom - 60)) { $script:top = [double]$sv.top }
    if ($null -ne $sv.compact) { $script:compact = [bool]$sv.compact }
    if ($null -ne $sv.reduceMotion) { $script:reducePref = [bool]$sv.reduceMotion }
  }
} catch { }
if ($env:CW_TOP) { try { $script:top = [double]$env:CW_TOP } catch { } }
if ($env:CW_COMPACT) { $script:compact = ($env:CW_COMPACT -eq '1') }
$pinMap = @{ mascot = 'mascot'; limits = 'five_hour'; ctx = 'ctx'; sub = 'sub' }
if ($env:CW_PIN -and $pinMap.ContainsKey($env:CW_PIN)) { $script:pinned = $pinMap[$env:CW_PIN] }
function Save-Cfg {
  try {
    $d = Split-Path -Parent $CFG
    if (-not (Test-Path -LiteralPath $d)) { $null = New-Item -ItemType Directory -Path $d -Force }
    (@{ top = [int]$script:top; compact = [bool]$script:compact; reduceMotion = [bool]$script:reducePref } | ConvertTo-Json -Compress) | Set-Content -LiteralPath $CFG -Encoding UTF8
  } catch { }
}
# PID para o mod fechar so este processo
$usePid = ($env:CW_NO_PID -ne '1')
if ($usePid) {
  try {
    $d0 = Split-Path -Parent $PIDF
    if (-not (Test-Path -LiteralPath $d0)) { $null = New-Item -ItemType Directory -Path $d0 -Force }
    [System.IO.File]::WriteAllText($PIDF, [string]$PID)
  } catch { }
}

# calcula a geometria (janela + faixa + balao) e so recria a Region quando a forma muda
function Apply-Geo {
  $k = $script:S; $wa = $script:wa
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
  if ($bx -ne $script:boundsKey) { $script:boundsKey = $bx; $form.SetBounds($wa.Right - $wPx, $wy, $wPx, $hPx); $script:inval = $true }
  $script:geo = @{
    lw = $wPx / $k; lh = $hPx / $k; sx = ($wPx - $nwPx) / $k; sy = ($topPx - $wy) / $k; sh = $shPx / $k
    open = [bool]$it; by = ($bTop - $wy) / $k; bh = $balPx / $k; tipY = ($tipPx - $wy) / $k; item = $it
  }
  $sk = '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}' -f $wPx, $hPx, ($topPx - $wy), $shPx, ($bTop - $wy), $balPx, ($tipPx - $wy), $script:flare, $k
  if ($sk -ne $script:shapeKey) {
    $script:shapeKey = $sk; $script:inval = $true
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
# area de trabalho e DPI podem mudar (resolucao, barra de tarefas, escala): reconsulta barata a cada 2 s
function Check-Screen {
  $r = [Cw.W]::WorkArea()
  $gs = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $s2 = $gs.DpiX / 96.0; $gs.Dispose()
  if ($s2 -ne $script:S) {
    $script:S = $s2
    $script:mg.ResetTransform(); $script:mg.ScaleTransform([single]$s2, [single]$s2)
    $script:boundsKey = ''; $script:shapeKey = ''; $script:forceView = $true
  }
  if (-not $r.Equals($script:wa)) { $script:wa = $r; $script:boundsKey = ''; $script:shapeKey = ''; $script:inval = $true }
}

function Hit-Item([double]$lx, [double]$ly) {
  $geo = $script:geo
  if (-not $geo -or $lx -lt $geo.sx) { return $null }
  foreach ($it in $script:items) {
    if ($ly -ge ($geo.sy + $it.y - $it.pad) -and $ly -le ($geo.sy + $it.y + $it.h + $it.pad)) { return $it }
  }
  $null
}

function Toggle-Compact { $script:compact = -not $script:compact; $script:balKey = ''; Rebuild-Items; Save-Cfg }
function Dismiss-Alert { $script:dismissKey = $script:alertKey; $script:alert = $false; $script:hov = ''; $script:hovCand = ''; $script:inval = $true }
# clique num item: fixa/solta o balao dele; segundo clique rapido no mascote = duplo clique (desfaz o pino e reduz/expande)
function Click-Item($it) {
  $k = [string]$it.k; $tNow = $script:sw.Elapsed.TotalSeconds
  if ($k -eq 'mascot' -and $script:clickK -eq 'mascot' -and ($tNow - $script:clickT) -le $DBL) {
    $script:pinned = $script:pinBefore; $script:clickK = ''; $script:hov = ''; $script:hovCand = ''
    Toggle-Compact; return
  }
  $script:clickK = $k; $script:clickT = $tNow; $script:pinBefore = $script:pinned
  if ($script:pinned -eq $k) { $script:pinned = ''; $script:hov = ''; $script:hovCand = '' }
  else { $script:pinned = $k; $script:hov = $k; $script:hovCand = $k }
  $script:inval = $true
  Save-Cfg
}

$form.Add_MouseDown({
  if ($_.Button -ne 'Left' -or -not $script:geo) { return }
  if (($_.X / $script:S) -ge $script:geo.sx) {
    $script:down = $true; $script:moved = $false
    $script:downY = [System.Windows.Forms.Cursor]::Position.Y; $script:topDown = $script:top
    $script:downHit = Hit-Item ($_.X / $script:S) ($_.Y / $script:S)
  } elseif ($script:alert) { Dismiss-Alert }   # clique no balao de alerta dispensa
  else { $script:pinned = ''; $script:hov = ''; $script:hovCand = ''; $script:inval = $true }   # clique no balao aberto fecha
})
$form.Add_MouseMove({
  if ($script:down) {
    $d = [System.Windows.Forms.Cursor]::Position.Y - $script:downY
    if ([math]::Abs($d) -gt 3 -or $script:moved) { $script:moved = $true; $script:top = $script:topDown + $d; Apply-Geo }
    return
  }
  $hit = Hit-Item ($_.X / $script:S) ($_.Y / $script:S)
  $script:leaveAt = 0.0
  if ($hit) {
    if ($script:hovCand -ne $hit.k) { $script:hovCand = [string]$hit.k; $script:hovCandAt = $script:sw.Elapsed.TotalSeconds }
    $form.Cursor = [System.Windows.Forms.Cursors]::Hand
  } else { $form.Cursor = [System.Windows.Forms.Cursors]::Default }
})
$form.Add_MouseUp({
  if ($_.Button -eq 'Left' -and $script:down) {
    if ($script:moved) { Save-Cfg }
    elseif ($script:alert) { Dismiss-Alert }
    elseif ($script:downHit) { Click-Item $script:downHit }
  }
  $script:lastAct = $script:sw.Elapsed.TotalSeconds
  $script:down = $false; $script:moved = $false; $script:downHit = $null
})
$form.Add_FormClosing({
  $timer.Stop()
  if ($usePid) { try { if ([System.IO.File]::Exists($PIDF) -and ([System.IO.File]::ReadAllText($PIDF).Trim() -eq [string]$PID)) { [System.IO.File]::Delete($PIDF) } } catch { } }
})
# menu: os rotulos dizem o que vai acontecer no estado atual
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miCompact = New-Object System.Windows.Forms.ToolStripMenuItem 'Reduzir'
$miCompact.Add_Click({ Toggle-Compact })
$miPin = New-Object System.Windows.Forms.ToolStripMenuItem 'Fixar balão'
$miPin.Add_Click({
  if ($script:pinned) { $script:pinned = ''; $script:hov = ''; $script:hovCand = '' } else { $script:pinned = $(if ($script:openKey) { $script:openKey } else { 'mascot' }) }
  $script:inval = $true; Save-Cfg
})
$miRm = New-Object System.Windows.Forms.ToolStripMenuItem 'Reduzir movimento'
$miRm.Add_Click({ $script:reducePref = -not $script:reducePref; Calc-Rm; $script:inval = $true; Save-Cfg })
$miClose = New-Object System.Windows.Forms.ToolStripMenuItem 'Fechar'
$miClose.Add_Click({ $form.Close() })
$menu.Items.AddRange([System.Windows.Forms.ToolStripItem[]]@($miCompact, $miPin, $miRm, (New-Object System.Windows.Forms.ToolStripSeparator), $miClose))
$menu.Add_Opening({
  $miCompact.Text = $(if ($script:compact) { 'Expandir' } else { 'Reduzir' })
  $miPin.Text = $(if ($script:pinned) { 'Soltar balão' } else { 'Fixar balão' })
  $miRm.Checked = ($script:reducePref -or $script:reduce)
  $miRm.Enabled = (-not $script:reduce)   # forcado pelo Windows ou por CW_REDUCE_MOTION
})
$form.ContextMenuStrip = $menu

# anel do mascote: circulo inteiro ou arco (a partir de $start, sentido horario)
function Ring($g, [double]$cx, [double]$cy, [double]$r, [double]$w, [string]$hex, [int]$a = 255) {
  $g.DrawEllipse((Pn $hex ([single]$w) $a), [single]($cx - $r), [single]($cy - $r), [single](2 * $r), [single](2 * $r))
}
function Arc($g, [double]$cx, [double]$cy, [double]$r, [double]$w, [string]$hex, [double]$start, [double]$sweep) {
  $g.DrawArc((Pn $hex ([single]$w)), [single]($cx - $r), [single]($cy - $r), [single](2 * $r), [single](2 * $r), [single]$start, [single]$sweep)
}

# camada fixa (fundo, nome, linhas de uso e balao) em pixels do dispositivo: o PowerShell e o gargalo, entao ela
# so e redesenhada quando muda (forma, estado, item aberto ou, com balao de tempos, a cada segundo); o Paint copia e anima por cima
$script:lay = $null; $script:layKey = ''
function Draw-Static($g, $geo, $v, [string]$openK, [double]$nowMs) {
  $sepDone = $false
  foreach ($it in $script:items) {
    $iy = $geo.sy + $it.y
    if ($it.k -eq 'mascot') {
      if (-not $script:compact) { $g.DrawString($v.shortTxt, $fName, (Br $v.scol), [System.Drawing.RectangleF]::new([single]$geo.sx, [single]($iy + 2 * $MR + 8), [single]$NW, 16), $center) }
      continue
    }
    # linhas de uso: rotulo a esquerda, valor a direita, barra fina embaixo (a barra de subagentes anima no Paint)
    $rw = $it.row
    $x0 = $geo.sx + 10; $w0 = $NW - 20
    if (-not $sepDone) { $sepDone = $true; Rect $g $LINE $x0 ($iy - 9) $w0 1 }
    $g.FillPath((Br $(if ($openK -eq $it.k) { $TRKO } else { $TRK })), (RoundPath $x0 ($iy + 18) $w0 4 2))
    if ($it.k -ne 'sub' -and $null -ne $rw.pv -and $rw.pv -gt 0) {
      $g.FillPath((Br $rw.fill), (RoundPath $x0 ($iy + 18) ([math]::Max(4, $w0 * $rw.pv / 100)) 4 2))
    }
    $g.DrawString($rw.lab, $fSmall, (Br $DIM), [single]($x0 - 3), [single]($iy - 1))
    $g.DrawString($rw.val, $fRing, (Br $rw.vcol), [System.Drawing.RectangleF]::new([single]$x0, [single]($iy - 1), [single]($w0 + 3), 16), $right)
  }
  if ($geo.open) {
    $stg = $g.Save()
    $g.TranslateTransform(0, [single]$geo.by)
    [void](Draw-Balloon $g ([string]$geo.item.bal) $true $nowMs)
    $g.Restore($stg)
  }
}

$form.Add_Paint({ try {
  $g = $_.Graphics
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
  $geo = $script:geo; $v = $script:vm
  if (-not $geo -or -not $v) { $g.Clear($BLACKC); return }
  $nowMs = NowMs
  $openK = $(if ($geo.open) { [string]$geo.item.k } else { '' })
  # o fundo preto ja e a faixa e o balao (a Region recorta a forma); so os baloes com tempos ("ha 5 s", "reinicia em") mudam sozinhos
  $tb = ''; if ($geo.open -and -not $v.off -and ($geo.item.bal -eq 'mascot' -or $geo.item.bal -eq 'limits')) { $tb = [math]::Floor($nowMs / 1000) }
  $cs = $form.ClientSize
  $lk = '{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $script:shapeKey, $cs.Width, $cs.Height, $script:viewVer, $script:compact, $openK, $tb
  if ($lk -ne $script:layKey -or -not $script:lay) {
    if ($script:lay) { $script:lay.Dispose(); $script:lay = $null }
    $script:layKey = $lk
    $script:lay = New-Object System.Drawing.Bitmap ([math]::Max(1, $cs.Width)), ([math]::Max(1, $cs.Height)), ([System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $gl = [System.Drawing.Graphics]::FromImage($script:lay)
    try {
      $gl.Clear($BLACKC)   # opaco: o ClearType precisa de fundo solido para ficar igual ao desenho direto
      $gl.SmoothingMode = 'AntiAlias'; $gl.TextRenderingHint = 'ClearTypeGridFit'
      $gl.ScaleTransform($script:S, $script:S)
      Draw-Static $gl $geo $v $openK $nowMs
    } finally { $gl.Dispose() }
  }
  $g.CompositingMode = 'SourceCopy'; $g.InterpolationMode = 'NearestNeighbor'
  $g.DrawImage($script:lay, 0, 0, $script:lay.Width, $script:lay.Height)
  $g.CompositingMode = 'SourceOver'
  $g.ScaleTransform($script:S, $script:S)
  $t = $script:sw.Elapsed.TotalSeconds
  $mode = [string]$v.mode
  if ($mode -ne $script:lastMode) {
    if ($script:lastMode -eq 'coding') { $script:codingEnd = $t }
    $script:introSkip = ($mode -eq 'coding' -and $script:codingEnd -gt 0 -and ($t - $script:codingEnd) -lt 8)
    $script:prevMode = $script:lastMode; $script:lastMode = $mode; $script:modeT0 = $t
  }
  $age = $t - $script:modeT0
  # pulsa ~3 ciclos ao entrar no loud e depois fica fixo na intensidade alta
  $pulse = 1.0
  if ($v.ring -eq 'loud' -and -not $script:rm -and $age -lt (3 * [math]::PI / 4.2)) { $pulse = [math]::Abs([math]::Sin($t * 4.2)) }
  $spinA = $(if ($script:rm) { -90.0 } else { ($t * 240) % 360 })

  # partes animadas: anel + mascote (+ selo) e a barra de subagentes
  $ccx = $geo.sx + $NW / 2
  foreach ($it in $script:items) {
    $iy = $geo.sy + $it.y; $icy = $geo.sy + $it.cy
    $isOpen = ($openK -eq $it.k)
    if ($it.k -eq 'mascot') {
      $rr = $MR; $rk = $v.ring
      if ($rk -eq 'spin') { Ring $g $ccx $icy $rr 2.5 $TRK; Arc $g $ccx $icy $rr 2.5 $v.col $spinA 100 }
      elseif ($rk -eq 'loud') { Ring $g $ccx $icy $rr 3.5 $AMB ([int](140 + 115 * $pulse)) }
      elseif ($rk -eq 'done') { Ring $g $ccx $icy $rr 2.5 $GRN }
      elseif ($rk -eq 'error') { Ring $g $ccx $icy $rr 2.5 $RED }
      else { Ring $g $ccx $icy $rr 2.5 $(if ($isOpen) { $QUIETO } else { $QUIET }) }
      $u0 = [math]::Max(1.0, [math]::Round(2.0 * 0.9 * $script:S)) / $script:S
      Draw-Mascot $g $ccx ($icy + 8 * $u0) 0.9 $v $t $age 4.0
      if ($script:compact) {
        # linhas escondidas: selo "!" no anel quando 5 h, 7 d ou contexto estao perto do limite (forma + cor)
        if ($v.warn) {
          $dx = $rr * 0.7071; $px = $ccx + $dx; $py = $icy - $dx
          $g.FillEllipse((Br $BLACK), [single]($px - 8.5), [single]($py - 8.5), 17, 17)
          $g.FillEllipse((Br $v.warn), [single]($px - 6.5), [single]($py - 6.5), 13, 13)
          Rect $g $BLACK ($px - 0.9) ($py - 4.3) 1.8 5.2
          Rect $g $BLACK ($px - 0.9) ($py + 2.2) 1.8 1.8
        }
      }
      continue
    }
    if ($it.k -eq 'sub') {
      $x0 = $geo.sx + 10; $w0 = $NW - 20
      $sx0 = $(if ($script:rm) { 0.0 } else { ($w0 - 18) * (0.5 + 0.5 * [math]::Sin($t * 3)) })
      $g.FillPath((Br $SUBC), (RoundPath ($x0 + $sx0) ($iy + 18) $(if ($script:rm) { $w0 } else { 18 }) 4 2))
    }
  }
} catch { Log ("PAINT: " + $_.Exception.Message + " @ " + $_.InvocationInfo.ScriptLineNumber) } finally { foreach ($p2 in $script:pp) { $p2.Dispose() }; $script:pp.Clear() } })

# ---------- timer: anima por TEMPO (nao por quadro), le os arquivos so quando mudam ----------
$timer = New-Object Cw.Pulse $form   # ~30 fps reais (ver Cw.Pulse)
$timer.Interval = 33
$script:tick = 0
$timer.Add_Tick({ try {
  $script:tick++
  $now = $script:sw.Elapsed.TotalSeconds
  $dt = [math]::Min(0.1, $now - $script:lastT); $script:lastT = $now
  $nowMs = NowMs
  if (($now - $script:lastScr) -ge 2.0) { $script:lastScr = $now; Check-Screen }
  # consulta a pasta de estado no max ~4x/s
  if (($now - $script:lastChk) -ge 0.25) {
    $script:lastChk = $now
    $ch = Scan-State $nowMs
    if ($ch -or $script:forceView -or ($script:vm.nextExp -gt 0 -and $nowMs -ge $script:vm.nextExp)) {
      $script:forceView = $false; Update-View $nowMs; Rebuild-Items
    }
  }
  # tela cheia no monitor principal: esconde ate sair
  if (($now - $script:lastFs) -ge 0.5) {
    $script:lastFs = $now
    $fs = [Cw.W]::Fullscreen($PID)
    if ($fs -eq 1 -and $form.Visible) { $menu.Close(); $form.Hide() }
    elseif ($fs -eq 0 -and -not $form.Visible) { $form.Show(); $script:inval = $true }
  }
  if (-not $form.Visible) { return }
  $v = $script:vm
  $cp = [System.Windows.Forms.Cursor]::Position
  $inB = $form.Bounds.Contains($cp)
  # o menu nao fecha sozinho quando a janela nunca e ativada: fecha ao clicar fora dele
  if ($menu.Visible -and -not $menu.Bounds.Contains($cp) -and -not $inB -and ((([Cw.W]::GetAsyncKeyState(1) -bor [Cw.W]::GetAsyncKeyState(2)) -band 0x8000) -ne 0)) { $menu.Close() }
  # alerta (waiting + loud): abre o balao do mascote; um clique dispensa ate o proximo alerta; ao sair, fecha ~10 s depois sem mouse
  $loudNow = ($v.ring -eq 'loud')
  if ($inB -or $script:down) { $script:lastAct = $now }
  if ($loudNow) {
    if ($v.alertKey -ne $script:dismissKey) {
      if (-not $script:alert -or $v.alertKey -ne $script:alertKey) { $script:lastAct = $now }
      $script:alert = $true
    } else { $script:alert = $false }
    $script:alertKey = $v.alertKey
  }
  elseif ($script:prevLoud) { $script:lastAct = $now }
  elseif ($script:alert -and ($now - $script:lastAct) -gt 10) { $script:alert = $false }
  $script:prevLoud = $loudNow
  # mouse fora da faixa e do balao (posicao real do cursor; MouseLeave se perde quando a janela muda de forma)
  $inside = $false
  if ($inB) { $rgn = $form.Region; $inside = ((-not $rgn) -or $rgn.IsVisible($form.PointToClient($cp))) }
  # clique fora do widget (em outra janela, que o form nao recebe): solta o balao fixado
  $btn = ((([Cw.W]::GetAsyncKeyState(1) -bor [Cw.W]::GetAsyncKeyState(2)) -band 0x8000) -ne 0)
  if ($btn -and -not $script:btnDown -and -not $inside -and -not $menu.Visible -and $script:pinned) {
    $script:pinned = ''; $script:hov = ''; $script:hovCand = ''; $script:inval = $true
  }
  $script:btnDown = $btn
  if ($inside -or $script:down -or $menu.Visible) { $script:leaveAt = 0.0; if ($v.doneShow) { $script:ackPending = $true } }
  elseif (($script:hov -or $script:hovCand -or $script:ackPending) -and $script:leaveAt -le 0) { $script:leaveAt = $now }
  # saiu: fecha o balao apos ~400 ms (e reconhece o "terminou" visto)
  if ($script:leaveAt -gt 0 -and ($now - $script:leaveAt) -gt $HOVER_OUT) {
    $script:hov = ''; $script:hovCand = ''; $script:leaveAt = 0.0
    if ($script:ackPending) { $script:ackPending = $false; Ack-All }
  }
  # entrou: abre depois de ~180 ms parado num item (ou na hora, se ja havia balao de hover aberto)
  if ($inside -and $script:hovCand -and $script:hovCand -ne $script:hov -and ($script:hov -or ($now - $script:hovCandAt) -ge $HOVER_IN)) { $script:hov = $script:hovCand }
  # qual item esta aberto: mouse > fixado (ou o mascote, se o fixado nao existe agora) > alerta
  $itOpen = $null
  if ($script:hov) { $itOpen = Find-Item $script:hov }
  if (-not $itOpen -and $script:pinned -and -not $v.off) { $itOpen = Find-Item $script:pinned; if (-not $itOpen) { $itOpen = Find-Item 'mascot' } }
  if (-not $itOpen -and $script:alert) { $itOpen = Find-Item 'mascot' }
  $ok = $(if ($itOpen) { [string]$itOpen.k } else { '' })
  if ($ok -ne $script:openKey) { $script:openKey = $ok; $script:inval = $true }
  # altura do balao (mede so quando o item ou o estado muda)
  if ($itOpen) {
    $bk = '{0}|{1}|{2}|{3}' -f $itOpen.bal, $script:viewVer, $script:S, $script:compact
    if ($bk -ne $script:balKey) {
      $script:balKey = $bk
      $script:balH = [math]::Ceiling((Draw-Balloon $script:mg ([string]$itOpen.bal) $false $nowMs))
    }
  }
  # altura da faixa acompanha os itens (suave, ou direto com reducao de movimento)
  $moving = $false
  if ($script:curH -ne $script:tgtH) {
    if ($script:rm -or [math]::Abs($script:tgtH - $script:curH) -lt 0.5) { $script:curH = $script:tgtH }
    else { $script:curH += ($script:tgtH - $script:curH) * [math]::Min(1.0, $dt * 14); $moving = $true }
    $script:inval = $true
  }
  Apply-Geo
  $iv = $(if ($moving) { 16 } else { 33 })
  if ($timer.Interval -ne $iv) { $timer.Interval = $iv }
  # parado de verdade (offline, ocioso, ou "Sua vez" depois do aceno): redesenha devagar em vez de 30 fps
  $calm = ($v.off -or $v.mode -eq 'idle' -or ($v.mode -eq 'waiting' -and -not $v.loud -and $script:lastMode -eq 'waiting' -and ($now - $script:modeT0) -gt 3.2))
  if ($calm -and $v.agentsN -gt 0 -and -not $script:compact) { $calm = $false }   # barra de subagentes anima
  $every = $(if ($v.off) { 30 } else { 8 })
  if ($calm -and -not $script:inval -and ($script:tick % $every) -ne 0) { return }
  $script:inval = $false
  $form.Invalidate()
} catch { Log ("TICK: " + $_.Exception.Message + " @ " + $_.InvocationInfo.ScriptLineNumber) } })
[void](Scan-State (NowMs)); Update-View (NowMs); Rebuild-Items; Apply-Geo
$timer.Start()
[void][System.Windows.Forms.Application]::Run($form)
