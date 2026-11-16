import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Mode, St } from '../types'
import { MASCOTS, sprite } from './mascots'

// Launcher e arquivo de estado ficam relativos a $.plugin.root (nada fixo por usuario).
const widgetCmd = ($: any): string => `${$.plugin.root}/widget/iniciar-widget.cmd`
const STOP_ARGV = [
  'powershell', '-NoProfile', '-Command',
  "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -like '*claudinho-widget*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }",
]
const IDLE_AFTER_MS = 120_000
const FLASH_MS = 4_000
const TICK_MS = 1000

const INITIAL: St = {
  mode: 'idle', loud: false, label: 'Ocioso', since: 0, frame: 0,
  sessionStart: 0, turnStart: 0, flashUntil: 0,
  inTok: 0, outTok: 0, cacheTok: 0, hasUsage: false,
  ctxPct: null, usd: null, counts: {}, history: [],
  waitSince: 0, ask: '', ctxTok: null, ctxWin: null,
}
// Troque a tag quando mudar os campos de St: ela descarta o que a versão antiga guardou.
const st = atom({ plugin: 'claudinho-panel', key: 'st' } as const, INITIAL, { shape: 'st-2' })

const READ = new Set(['Read', 'Grep', 'Glob', 'LS', 'WebSearch', 'WebFetch'])
const ASK = new Set(['AskUserQuestion', 'ExitPlanMode'])

const NAMES: Record<Mode, string> = {
  waiting: 'Aguardando você', coding: 'Codando', thinking: 'Pensando',
  reading: 'Lendo/pesquisando', idle: 'Ocioso', done: 'Terminou', error: 'Erro',
}
const EMOJI: Record<Mode, string> = {
  waiting: '🟡', coding: '💻', thinking: '🧠', reading: '🔍', idle: '😴', done: '✅', error: '❌',
}
const COLOR: Record<Mode, string> = {
  waiting: '#f5c542', coding: '#d97757', thinking: '#6cc4e8', reading: '#6cc4e8',
  idle: '#7d7a76', done: '#5fd38d', error: '#ff5f56',
}

function detail(tool: string, e: Record<string, unknown>): string {
  const s = (v: unknown) => (typeof v === 'string' ? v : '')
  const file = s(e.file_path) || s(e.notebook_path)
  const short = (t: string, n = 38) => (t.length > n ? t.slice(0, n - 1) + '…' : t)
  if (file) return `${tool} em ${short(file.replace(/\\/g, '/').split('/').slice(-2).join('/'))}`
  if (s(e.command)) return `${tool}: ${short(s(e.command).split('\n')[0] ?? '', 34)}`
  if (s(e.pattern)) return `${tool}: ${short(s(e.pattern), 30)}`
  if (s(e.query)) return `${tool}: ${short(s(e.query), 30)}`
  if (s(e.url)) return `${tool}: ${short(s(e.url), 30)}`
  return tool
}

// Alvo curto (max ~28 chars): arquivo, 2 primeiras palavras do comando, host da url. Sem segredos longos.
function target(e: Record<string, unknown>): string {
  const s = (v: unknown) => (typeof v === 'string' ? v : '')
  const cut = (t: string, n = 28) => (t.length > n ? t.slice(0, n - 1) + '…' : t)
  const file = s(e.file_path) || s(e.notebook_path)
  if (file) return cut(file.replace(/\\/g, '/').split('/').pop() ?? '')
  const cmd = s(e.command)
  if (cmd) return cut((cmd.split('\n')[0] ?? '').trim().split(/\s+/).slice(0, 2).join(' '))
  if (s(e.pattern)) return cut(s(e.pattern))
  if (s(e.query)) return cut(s(e.query))
  if (s(e.url)) return cut(s(e.url).replace(/^https?:\/\//, '').split('/')[0] ?? '')
  return ''
}
const withTarget = (tool: string, e: Record<string, unknown>) => {
  const t = target(e)
  return t ? `${tool} · ${t}` : tool
}
// Mensagens comuns do Claude Code em pt-BR; desconhecida passa como está.
function ptbr(m: string): string {
  const perm = /needs your permission to use (.+?)\.?$/i.exec(m)
  if (perm) return `precisa da sua permissão para usar ${perm[1]}`
  if (/needs your permission/i.test(m)) return 'precisa da sua permissão'
  if (/waiting for your input/i.test(m)) return 'aguardando sua resposta'
  return m
}

const hms = (ms: number) => new Date(ms).toTimeString().slice(0, 8)
const dur = (ms: number) => {
  const t = Math.max(0, Math.floor(ms / 1000))
  const m = Math.floor(t / 60)
  return m >= 60 ? `${Math.floor(m / 60)}h${String(m % 60).padStart(2, '0')}` : `${m}:${String(t % 60).padStart(2, '0')}`
}
const k = (n: number) => (n >= 1e6 ? (n / 1e6).toFixed(2) + 'M' : n >= 1e3 ? (n / 1e3).toFixed(1) + 'k' : String(n))

// O widget le este mesmo arquivo (iniciar-widget.cmd passa -StateFile; o padrao do .ps1 e o mesmo caminho).
const stateFile = ($: any): string => `${$.plugin.root}/claudinho-state.json`

// Publica o estado já "desenhado" num JSON para o widget externo (claudinho-widget.ps1).
async function publish($: any) {
  const s: St = await read($, st)
  const name = ((await $.store.get('mascot')) as string) || 'coral'
  const m = MASCOTS[name] ?? MASCOTS.coral!
  const now = await $.clock.now()
  const cwd: string = (await $.session.cwd().catch(() => '')) || ''
  const project = cwd.replace(/\\/g, '/').split('/').filter(Boolean).pop() ?? ''
  const out = {
    project, ts: now, mode: s.mode, loud: s.loud, label: s.label, name: NAMES[s.mode], emoji: EMOJI[s.mode],
    color: COLOR[s.mode], frame: s.frame, rows: sprite(s.mode, s.frame), palette: m.palette,
    sessionStart: s.sessionStart, turnStart: s.turnStart,
    tokens: s.hasUsage ? { in: s.inTok, out: s.outTok, cache: s.cacheTok } : null,
    ctxPct: s.ctxPct, usd: s.usd, ctxTok: s.ctxTok, ctxWin: s.ctxWin,
    ask: s.mode === 'waiting' ? s.ask : '', waitSince: s.mode === 'waiting' ? s.waitSince : 0,
    top: Object.entries(s.counts).sort((a, b) => b[1] - a[1]).slice(0, 5),
    history: s.history.slice(-6).reverse().map(h => ({ t: h.t, text: h.text })),
  }
  await $.fs.write(stateFile($),JSON.stringify(out)).catch(() => undefined)
}

// Atualiza o estado + a linha de status (plano B, sempre visível).
async function setMode($: any, mode: Mode, label: string, extra: Partial<St> = {}, loud = false) {
  const now = await $.clock.now()
  await update($, st, (s: St) => ({
    ...s, mode, loud, label, since: now,
    // waitSince reinicia ao entrar em waiting (ou ao trocar entre loud e nao-loud)
    waitSince: mode === 'waiting' ? (s.mode === 'waiting' && s.loud === loud ? s.waitSince : now) : 0,
    ask: mode === 'waiting' ? (extra.ask ?? (s.mode === 'waiting' ? s.ask : '')) : '',
    ...extra,
    flashUntil: mode === 'done' || mode === 'error' ? now + FLASH_MS : 0,
  }))
  await publish($)
  $.ui.status(`${EMOJI[mode]} ${NAMES[mode]}${label && label !== NAMES[mode] ? ' — ' + label : ''}`)
}

export const register: Register = on => {
  let cancelTick: (() => void) | undefined

  const log = (s: St, now: number, text: string) => [...s.history, { t: now, text }].slice(-8)

  on('session.start', async ($, e, next) => {
    const now = await $.clock.now()
    await update($, st, () => ({ ...INITIAL, counts: {}, history: [], sessionStart: now, since: now }))
    await $.command.register({ name: 'claudinho', description: 'Widget do Claudinho na borda da tela: on | off | mascote <nome> | lista' })
    await publish($)
    cancelTick?.()
    // 1x por segundo, e só mexe no estado quando há transição (nada de redesenhar à toa)
    const t = $.clock.every(TICK_MS, async () => {
      const n = await $.clock.now()
      const s = await read($, st)
      if ((s.mode === 'done' || s.mode === 'error') && n > s.flashUntil) {
        if (s.mode === 'done') await setMode($, 'waiting', 'sua vez de mandar mensagem')
        else await setMode($, 'thinking', 'continuando')
      } else if (s.mode === 'waiting' && !s.loud && n - s.since > IDLE_AFTER_MS) {
        await setMode($, 'idle', 'sem atividade')
      }
    })
    cancelTick = () => t.cancel()
    return next(e)
  })

  on('session.end', async ($, e, next) => { cancelTick?.(); return next(e) })

  // prompt enviado -> Pensando
  on('prompt.submit', async ($, e, next) => {
    const now = await $.clock.now()
    await setMode($, 'thinking', 'processando sua mensagem', { turnStart: now })
    return next(e)
  })

  // ferramenta vai rodar -> Codando / Lendo / Aguardando (pergunta)
  on('tool.call', async ($, e, next) => {
    const tool = e.tool as string
    const rec = e as unknown as Record<string, unknown>
    const text = detail(tool, rec)
    const now = await $.clock.now()
    await update($, st, (s: St) => ({
      ...s, counts: { ...s.counts, [tool]: (s.counts[tool] ?? 0) + 1 }, history: log(s, now, withTarget(tool, rec)),
    }))
    if (ASK.has(tool)) await setMode($, 'waiting', `${tool} — responda no chat`, { ask: `${tool} · ${tool === 'ExitPlanMode' ? 'aprovar plano' : 'pergunta'}` }, true)
    else if (READ.has(tool)) await setMode($, 'reading', text)
    else await setMode($, 'coding', text)
    return next(e)
  })

  // classic.PermissionRequest: o agente parou pedindo permissão
  on('classic.PermissionRequest', async ($, e, next) => {
    const inp = ((e as any).tool_input ?? {}) as Record<string, unknown>
    await setMode($, 'waiting', `permissão para ${e.tool_name}`, { ask: withTarget(String(e.tool_name), inp) }, true)
    return next(e)
  })
  // classic.Notification: avisos do Claude (permissão, "aguardando input")
  on('classic.Notification', async ($, e, next) => {
    const loud = e.notification_type !== 'idle_prompt'
    const msg = ptbr(e.message)
    // mantem o pedido ja conhecido (ferramenta + alvo) se a permissao veio antes
    const cur = await read($, st)
    await setMode($, 'waiting', msg.slice(0, 50), loud && !(cur.mode === 'waiting' && cur.loud) ? { ask: msg.slice(0, 40) } : {}, loud)
    return next(e)
  })
  // classic.PostToolUse: ferramenta terminou -> volta a Pensando (modelo lê o resultado)
  on('classic.PostToolUse', async ($, e, next) => {
    // mantém "Codando/Lendo" visível por pelo menos 1,5s, senão comandos rápidos nunca aparecem
    const cur = await read($, st)
    const now = await $.clock.now()
    const wait = 1500 - (now - cur.since)
    const since = cur.since
    if ((cur.mode === 'coding' || cur.mode === 'reading') && wait > 0) {
      $.clock.after(wait, async () => {
        const again = await read($, st)
        if (again.since === since) await setMode($, 'thinking', `resultado de ${e.tool_name}`)
      })
    } else {
      await setMode($, 'thinking', `resultado de ${e.tool_name}`)
    }
    return next(e)
  })
  // classic.PostToolUseFailure: ferramenta falhou -> Erro (alguns segundos)
  on('classic.PostToolUseFailure', async ($, e, next) => {
    const now = await $.clock.now()
    await update($, st, (s: St) => ({ ...s, history: log(s, now, `ERRO ${e.tool_name}`) }))
    await setMode($, 'error', `${e.tool_name} falhou`)
    return next(e)
  })
  // classic.Stop: turno acabou -> Terminou
  on('classic.Stop', async ($, e, next) => {
    await setMode($, 'done', 'turno concluído')
    return next(e)
  })

  // turn.complete: tokens do turno + contexto %/custo (session.usage)
  on('turn.complete', async ($, e, next) => {
    const u = e.usage
    const usage = await $.session.usage().catch(() => undefined)
    await update($, st, (s: St) => ({
      ...s,
      inTok: s.inTok + (u ? u.input_tokens + u.cache_creation_input_tokens : 0),
      cacheTok: s.cacheTok + (u ? u.cache_read_input_tokens : 0),
      outTok: s.outTok + (u ? u.output_tokens : 0),
      hasUsage: s.hasUsage || !!u,
      ctxPct: usage?.context.percent ?? s.ctxPct,
      ctxTok: usage?.context.tokens ?? s.ctxTok,
      ctxWin: usage?.context.window ?? s.ctxWin,
      usd: usage?.cost?.usd ?? s.usd,
    }))
    if (e.reason === 'error') await setMode($, 'error', 'turno terminou com erro')
    return next(e)
  })

  on('command.run', { command: 'claudinho' }, async ($, e) => {
    const [cmd, arg] = e.args.trim().split(/\s+/)
    if (cmd === 'off') {
      await $.process.run(STOP_ARGV)
      return { text: 'Widget fechado. /claudinho on para voltar.' }
    }
    if (cmd === 'on' || !cmd) {
      await $.process.run(STOP_ARGV) // evita widget duplicado
      await publish($)
      await $.process.run(['cmd', '/c', widgetCmd($)])
      return { text: 'Widget aberto na borda direita da tela.' }
    }
    if (cmd === 'lista') return { text: Object.entries(MASCOTS).map(([n, m]) => `${n} — ${m.label}`).join(', ') }
    if (cmd === 'mascote') {
      if (!arg || !MASCOTS[arg]) return { text: `Mascote inválido. Opções: ${Object.keys(MASCOTS).join(', ')}` }
      await $.store.set('mascot', arg)
      await publish($)
      return { text: `Mascote: ${arg}` }
    }
    return { text: 'Uso: /claudinho on | off | lista | mascote <nome>' }
  })
}
