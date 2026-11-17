import { atom, read, update } from 'claude-code'
import type { Hook, Register } from 'claude-code'

import type { AskKind, Mode, St } from '../types'
import { detail, ellipsis, limitsOf, prettyModel, ptbr, target, withTarget } from './format'
import { MASCOTS } from './mascots'

// Tipo do `$` dos hooks (o mesmo em todos os eventos).
type Dollar = Parameters<Hook<'session.start'>>[0]

// Launcher relativo a $.plugin.root; estado em pasta fixa ~/.claude/claudinho/state (nada fixo por usuario).
const widgetCmd = ($: Dollar): string => `${$.plugin.root}/widget/iniciar-widget.cmd`
// O widget grava o próprio PID em ~/.claude/claudinho-widget.pid; só ele é encerrado (e só se ainda for um powershell).
const STOP_ARGV = [
  'powershell', '-NoProfile', '-Command',
  "$f = Join-Path $env:USERPROFILE '.claude/claudinho-widget.pid'; if (Test-Path $f) { try { $id = 0; if ([int]::TryParse((Get-Content $f -TotalCount 1).Trim(), [ref]$id)) { $p = Get-Process -Id $id -ErrorAction SilentlyContinue; if ($p -and $p.ProcessName -eq 'powershell') { Stop-Process -Id $id -Force } } } catch {}; Remove-Item $f -Force -ErrorAction SilentlyContinue }",
]
const IDLE_AFTER_MS = 120_000
const FLASH_MS = 4_000
const TICK_MS = 1000
const HEARTBEAT_MS = 5_000
const LIMITS_EVERY_MS = 60_000
const ASK_MAX = 200

const INITIAL: St = {
  mode: 'idle', loud: false, label: 'Ocioso', since: 0,
  sessionStart: 0, turnStart: 0, flashUntil: 0, doneAt: 0,
  inTok: 0, outTok: 0, cacheTok: 0, hasUsage: false,
  ctxPct: null, usd: null, counts: {}, history: [],
  waitSince: 0, ask: '', ctxTok: null, ctxWin: null, labelShort: 'Ocioso',
  agentModels: {}, limits: [], busy: false, failAt: 0, askKind: '', tool: '',
}
// Troque a tag quando mudar os campos de St: ela descarta o que a versão antiga guardou.
const st = atom({ plugin: 'claudinho-panel', key: 'st' } as const, INITIAL, { shape: 'st-9' })

const READ = new Set(['Read', 'Grep', 'Glob', 'LS', 'WebSearch', 'WebFetch'])
// Ferramentas que pedem algo a você: label da linha de status e texto do pedido.
const ASKS: Record<string, { label: string; ask: string; kind: AskKind }> = {
  AskUserQuestion: { label: 'pergunta para você', ask: 'Pergunta para você', kind: 'pergunta' },
  ExitPlanMode: { label: 'plano aguardando aprovação', ask: 'Aprovar o plano', kind: 'plano' },
}

const NAMES: Record<Mode, string> = {
  waiting: 'Aguardando você', coding: 'Codando', thinking: 'Pensando',
  reading: 'Lendo/pesquisando', idle: 'Ocioso', done: 'Terminou', error: 'Erro', agents: 'Agentes',
}
const EMOJI: Record<Mode, string> = {
  waiting: '🟡', coding: '💻', thinking: '🧠', reading: '🔍', idle: '😴', done: '✅', error: '❌', agents: '🤖',
}
const COLOR: Record<Mode, string> = {
  waiting: '#f5c542', coding: '#d97757', thinking: '#6cc4e8', reading: '#a78bfa',
  idle: '#7d7a76', done: '#5fd38d', error: '#ff5f56', agents: '#f472b6',   // agents = cor dos subagentes ($SUBC do widget)
}
const SHORT: Record<Mode, string> = {
  waiting: 'Responda', coding: 'Codando', thinking: 'Pensando', reading: 'Lendo',
  idle: 'Ocioso', done: 'Terminou', error: 'Erro', agents: 'Agentes',
}
// waiting sem loud = "sua vez" (neutro); com loud = permissão/pergunta pendente (amarelo, alerta)
const nameOf = (mode: Mode, loud: boolean): string => (mode === 'waiting' && !loud ? 'Sua vez' : NAMES[mode])
const colorOf = (mode: Mode, loud: boolean): string => (mode === 'waiting' && !loud ? '#faf9f5' : COLOR[mode])
const emojiOf = (mode: Mode, loud: boolean): string => (mode === 'waiting' && !loud ? '💬' : EMOJI[mode])
const shortOf = (mode: Mode, loud: boolean): string => (mode === 'waiting' && !loud ? 'Sua vez' : SHORT[mode])

// Subagentes/teammates que ainda estão rodando (terminados saem da lista).
const ACTIVE = new Set(['pending', 'running', 'waiting'])
async function activeAgents($: Dollar): Promise<{ id: string; type: string; desc: string }[]> {
  const list = ((await $.agent.list().catch(() => [])) ?? []) as { id: string; type: string; description: string; status: string }[]
  return list.filter(a => ACTIVE.has(a.status)).map(a => ({ id: a.id, type: a.type, desc: a.description }))
}

// Estado exibido (derivado, não guardado): com subagente rodando, Sua vez/Ocioso viram 'agents' (não é alerta).
// Terminou, Pensando, Codando, Lendo, Erro e os alertas continuam como estão.
const agentsLabel = (n: number): string => (n === 1 ? '1 subagente trabalhando' : `${n} subagentes trabalhando`)
const shownMode = (s: St, nAgents: number): Mode => (nAgents > 0 && (s.mode === 'idle' || (s.mode === 'waiting' && !s.loud)) ? 'agents' : s.mode)
// quantos subagentes ativos o último publish viu (a linha de status usa)
let agentCount = 0

// Evento vindo do loop de um subagente/teammate (tool.call e turn.complete trazem agentId; os classic, agent_id).
const fromSub = (e: unknown): boolean => {
  const r = e as { agentId?: string; agent_id?: string }
  return r.agentId !== undefined || r.agent_id !== undefined
}
// Subagente destravou um pedido de permissão: volta ao que a conversa principal estava fazendo.
async function resumeMain($: Dollar) {
  const s: St = await read($, st)
  if (!(s.mode === 'waiting' && s.loud)) return
  if (s.busy) await setMode($, 'thinking', 'continuando')
  else await setMode($, 'waiting', 'sua vez de mandar mensagem')
}

// Um arquivo por sessão: o widget lista a pasta e usa `ts` como heartbeat.
// Pasta fixa (não muda com a versão do plugin): %USERPROFILE%\.claude\claudinho\state.
async function stateFile($: Dollar, sid: string): Promise<string | undefined> {
  const home = (await $.env.get('USERPROFILE')) || (await $.env.get('HOME'))
  return home ? `${home.replace(/\\/g, '/')}/.claude/claudinho/state/${sid}.json` : undefined
}

// Sessões já encerradas: publish tardio (timer, tick em andamento, spawn) não ressuscita o arquivo.
const ended = new Set<string>()
// Timer pendente do backToThinking (cancelado no session.end).
let pendingBack: { cancel: () => void } | undefined
// Falha de escrita é avisada uma vez por sequência de falhas, não a cada tick.
let writeWarned = false

// Publica o estado já "desenhado" num JSON para o widget externo (claudinho-widget.ps1).
// offline = sessão encerrada (o widget tira a sessão da lista).
async function publish($: Dollar, offline = false, sidOverride = '') {
  const sid = sidOverride || String(await $.session.id())
  if (offline) ended.add(sid)
  else if (ended.has(sid)) return
  const s: St = await read($, st)
  const name = ((await $.store.get('mascot')) as string) || 'coral'
  const m = MASCOTS[name] ?? MASCOTS.coral!
  const now = await $.clock.now()
  const cwd: string = (await $.session.cwd().catch(() => '')) || ''
  const project = cwd.replace(/\\/g, '/').split('/').filter(Boolean).pop() ?? ''
  const model = prettyModel(String((await $.session.model().catch(() => '')) || ''))
  const agents = offline ? [] : (await activeAgents($)).map(a => {
    const am = s.agentModels[a.id]
    return { type: a.type, desc: a.desc, model: am ? prettyModel(am) : '' }
  })
  // "terminou há X" só faz sentido enquanto a sessão está parada depois do turno
  agentCount = agents.length
  const dm = shownMode(s, agents.length)
  const showDone = s.mode === 'done' || (dm !== 'agents' && (s.mode === 'idle' || (s.mode === 'waiting' && !s.loud)))
  const out = {
    sid, offline, model, agents, limits: s.limits ?? [],
    project, ts: now, mode: dm, loud: s.loud, label: dm === 'agents' ? agentsLabel(agents.length) : s.label,
    labelShort: dm === 'agents' ? agentsLabel(agents.length) : s.labelShort || s.label,
    name: nameOf(dm, s.loud), short: shortOf(dm, s.loud),
    color: colorOf(dm, s.loud), palette: m.palette,
    sessionStart: s.sessionStart, turnStart: s.turnStart, doneAt: showDone ? s.doneAt : 0,
    tokens: s.hasUsage ? { in: s.inTok, out: s.outTok, cache: s.cacheTok } : null,
    ctxPct: s.ctxPct, usd: s.usd, ctxTok: s.ctxTok, ctxWin: s.ctxWin,
    ask: dm === 'waiting' ? s.ask : '', waitSince: dm === 'waiting' ? s.waitSince : 0,
    askKind: dm === 'waiting' && s.loud ? s.askKind : '', failAt: s.failAt,
    tool: dm === 'coding' || dm === 'reading' ? s.tool : '',
    top: Object.entries(s.counts).sort((a, b) => b[1] - a[1]).slice(0, 5),
    history: s.history.slice(-6).reverse().map(h => ({ t: h.t, text: h.text })),
  }
  // a sessão pode ter acabado durante os awaits acima
  if (!offline && ended.has(sid)) return
  // $.fs não tem rename/delete: escrita direta, não atômica.
  // $.fs.write cria a pasta se não existir.
  try {
    const file = await stateFile($, sid)
    if (!file) throw new Error('USERPROFILE/HOME não definidos')
    await $.fs.write(file, JSON.stringify(out))
    writeWarned = false
  } catch (err) {
    if (!writeWarned) {
      writeWarned = true
      try { $.ui.log(`claudinho: falha ao gravar estado do widget: ${String(err)}`) } catch { /* nunca lança */ }
    }
  }
}

// Atualiza o estado + a linha de status (plano B, sempre visível).
async function setMode($: Dollar, mode: Mode, label: string, extra: Partial<St> = {}, loud = false) {
  const now = await $.clock.now()
  const prev: St = await read($, st)
  // som só na transição para o alerta (waiting+loud), não a cada atualização do alerta
  const alertNow = mode === 'waiting' && loud && !(prev.mode === 'waiting' && prev.loud)
  await update($, st, (s: St) => ({
    ...s, mode, loud, label, labelShort: extra.labelShort ?? label, since: now,
    sessionStart: s.sessionStart || now,
    // waitSince reinicia ao entrar em waiting (ou ao trocar entre loud e nao-loud)
    waitSince: mode === 'waiting' ? (s.mode === 'waiting' && s.loud === loud ? s.waitSince : now) : 0,
    ask: mode === 'waiting' ? (extra.ask ?? (s.mode === 'waiting' ? s.ask : '')) : '',
    askKind: mode === 'waiting' && loud ? (extra.askKind ?? (s.mode === 'waiting' && s.loud ? s.askKind : '')) : '',
    tool: '',
    ...extra,
    flashUntil: mode === 'done' || mode === 'error' ? now + FLASH_MS : 0,
  }))
  await publish($)
  await refreshStatus($)
  if (alertNow) await playAlert($)
}

// Som de alerta (Windows: som do sistema; $.audio.play não toca em Windows). Opt-out: /claudinho som off.
async function playAlert($: Dollar) {
  try {
    if ((await $.store.get('sound')) === 'off') return
    const os = (await $.env.get('OS')) || ''
    if (!os.toLowerCase().includes('windows')) return
    // sem await: o som não atrasa o estado; o sleep deixa o powershell vivo até o som tocar
    void $.process.run(['powershell', '-NoProfile', '-Command',
      '[System.Media.SystemSounds]::Exclamation.Play(); Start-Sleep -Milliseconds 1200']).catch(() => undefined)
  } catch { /* som é só um extra: nunca atrapalha */ }
}

// Abre o widget (sem fechar um existente: o mutex do widget evita duplicata).
async function launchWidget($: Dollar) {
  await publish($)
  await $.process.run(['cmd', '/c', widgetCmd($)])
}

// Linha de status (plano B): estado exibido + label; com subagente rodando, Sua vez/Ocioso viram Agentes.
async function refreshStatus($: Dollar) {
  const s: St = await read($, st)
  const dm = shownMode(s, agentCount)
  const nm = nameOf(dm, s.loud)
  const label = dm === 'agents' ? agentsLabel(agentCount) : s.label
  $.ui.status(`${emojiOf(dm, s.loud)} ${nm}${label && label !== nm ? ' — ' + label : ''}`)
}

// Ferramenta da conversa principal terminou (ou falhou): volta a Pensando, mas deixa
// "Codando/Lendo" visível por pelo menos 1,5 s, senão comandos rápidos nunca aparecem.
async function backToThinking($: Dollar, tool: string) {
  const cur = await read($, st)
  const now = await $.clock.now()
  const wait = 1500 - (now - cur.since)
  const since = cur.since
  pendingBack?.cancel()
  pendingBack = undefined
  if ((cur.mode === 'coding' || cur.mode === 'reading') && wait > 0) {
    pendingBack = $.clock.after(wait, async () => {
      pendingBack = undefined
      const again = await read($, st)
      if (again.since === since) await setMode($, 'thinking', `resultado de ${tool}`)
    })
  } else {
    await setMode($, 'thinking', `resultado de ${tool}`)
  }
}

export const register: Register = on => {
  let cancelTick: (() => void) | undefined
  let agentSig = ''
  let limitsAt = 0
  let publishedAt = 0
  // o alerta atual veio de um pedido de permissão de subagente (só esse um subagente pode destravar)
  let subAsk = false

  const log = (s: St, now: number, text: string) => [...s.history, { t: now, text }].slice(-8)

  on('session.start', async ($, e, next) => {
    const now = await $.clock.now()
    await update($, st, () => ({ ...INITIAL, counts: {}, history: [], sessionStart: now, since: now }))
    await $.command.register({ name: 'claudinho', description: 'Widget do Claudinho na borda da tela: on | off | auto on|off | som on|off | mascote <nome> | lista' })
    await publish($)
    publishedAt = now
    // abre o widget sozinho (opt-out: /claudinho auto off ou CW_AUTOSTART=0)
    try {
      const envOff = ((await $.env.get('CW_AUTOSTART')) || '').trim() === '0'
      if (!envOff && (await $.store.get('auto')) !== 'off') await launchWidget($)
    } catch { /* nunca impede a sessão de iniciar */ }
    cancelTick?.()
    // 1x por segundo; só mexe no estado quando há transição e republica a cada 5 s (heartbeat: `ts`)
    const t = $.clock.every(TICK_MS, async () => {
      const n = await $.clock.now()
      const s = await read($, st)
      const act = await activeAgents($)
      if ((s.mode === 'done' || s.mode === 'error') && n > s.flashUntil) {
        if (s.mode === 'done') await setMode($, 'waiting', 'sua vez de mandar mensagem')
        else if (s.busy) await setMode($, 'thinking', 'continuando')
        else await setMode($, 'waiting', 'sua vez de mandar mensagem')
      } else if (s.mode === 'waiting' && !s.loud && act.length === 0 && n - s.since > IDLE_AFTER_MS) {   // com subagente rodando não vira Ocioso
        await setMode($, 'idle', 'sem atividade')
      }
      // subagente começou ou terminou: republica para o widget atualizar a lista
      const sig = act.map(a => a.id).join(',')
      let dirty = sig !== agentSig
      const acabaram = dirty && agentSig !== '' && sig === ''
      agentSig = sig
      // o último subagente terminou: volta a Sua vez normalmente (reinicia o relógio do Ocioso)
      if (acabaram && (s.mode === 'waiting' || s.mode === 'idle') && !s.loud) await setMode($, 'waiting', 'sua vez de mandar mensagem')
      // limites: relê 1x por minuto, senão só mudam quando um turno termina
      if (n - limitsAt >= LIMITS_EVERY_MS) {
        limitsAt = n
        const usage = await $.session.usage().catch(() => undefined)
        if (usage?.rateLimits?.length) {
          const fresh = limitsOf(usage)
          if (JSON.stringify(fresh) !== JSON.stringify(s.limits ?? [])) {
            await update($, st, (x: St) => ({ ...x, limits: fresh }))
            dirty = true
          }
        }
      }
      if (dirty || n - publishedAt >= HEARTBEAT_MS) {
        await publish($)
        publishedAt = n
        if (dirty) await refreshStatus($)   // linha de status acompanha Agentes <-> Sua vez
      }
    })
    cancelTick = () => t.cancel()
    return next(e)
  })

  // Sem API para apagar arquivo: marca a sessão encerrada como offline. Em /clear o processo
  // continua com outro id (e sem session.start): marca só o id antigo e mantém o tick.
  // Publish tardio do id antigo vira no-op (ver `ended` em publish).
  on('session.end', async ($, e, next) => {
    if (e.reason !== 'clear') cancelTick?.()
    pendingBack?.cancel()
    pendingBack = undefined
    await publish($, true, e.sessionId).catch(() => undefined) // nunca impede a saída
    if (e.reason === 'clear') {
      // conversa nova: zera contagens/histórico, mas mantém os limites (são da conta)
      try {
        const now = await $.clock.now()
        await update($, st, (s: St) => ({ ...INITIAL, counts: {}, history: [], sessionStart: now, since: now, limits: s.limits ?? [] }))
        agentSig = ''
        subAsk = false
        // se o id novo já valer, publica agora; senão (id ainda o antigo, publish vira no-op)
        // zera publishedAt para o próximo tick (1 s) publicar o id novo
        await publish($)
        const cur = String(await $.session.id())
        publishedAt = cur === e.sessionId ? 0 : now
      } catch { /* nunca impede o /clear */ }
    }
    return next(e)
  })

  // subagente iniciado: anota em qual modelo ele roda (a lista de agentes não traz o modelo)
  on('agent.spawn', async ($, e, next) => {
    const r = await next(e)
    try {
      const id = (r as { agentId?: string }).agentId
      const mdl = (r as { model?: string }).model
      if (id && mdl) {
        await update($, st, (s: St) => ({
          ...s, agentModels: Object.fromEntries([...Object.entries(s.agentModels ?? {}), [id, mdl] as [string, string]].slice(-20)),
        }))
        await publish($)
      }
    } catch { /* só informativo: nunca atrapalha o spawn */ }
    return r
  })

  // prompt enviado -> Pensando (zera o "terminou há X")
  on('prompt.submit', async ($, e, next) => {
    if (fromSub(e)) return next(e)
    const now = await $.clock.now()
    await setMode($, 'thinking', 'processando sua mensagem', { turnStart: now, busy: true, doneAt: 0 })
    return next(e)
  })

  // ferramenta vai rodar -> Codando / Lendo / Aguardando (pergunta)
  on('tool.call', async ($, e, next) => {
    const tool = e.tool as string
    const rec = e as unknown as Record<string, unknown>
    const text = detail(tool, rec)
    const now = await $.clock.now()
    const sub = fromSub(e)
    await update($, st, (s: St) => ({
      ...s, counts: { ...s.counts, [tool]: (s.counts[tool] ?? 0) + 1 },
      history: log(s, now, (sub ? '↳ ' : '') + withTarget(tool, rec)),
    }))
    // ferramenta de subagente: conta e entra no histórico, mas não troca o estado do mascote
    if (sub) { await publish($); return next(e) }
    const asks = ASKS[tool]
    if (asks) {
      subAsk = false
      await setMode($, 'waiting', asks.label, { ask: asks.ask, askKind: asks.kind }, true)
    } else {
      const labelShort = target(rec) || tool
      await setMode($, READ.has(tool) ? 'reading' : 'coding', text, { labelShort, tool })
    }
    return next(e)
  })

  // tool.run: a chamada foi liberada (permissão concedida) e vai rodar -> sai do alerta de permissão.
  // Perguntas/planos (ASKS) não: a ferramenta roda justamente esperando a sua resposta.
  on('tool.run', async ($, e, next) => {
    try {
      const tool = e.tool as string
      if (!ASKS[tool]) {
        if (fromSub(e)) {
          if (subAsk) { subAsk = false; await resumeMain($) }
        } else {
          const s: St = await read($, st)
          if (s.mode === 'waiting' && s.loud && (s.askKind === 'permissao' || s.askKind === 'aviso')) {
            const rec = e as unknown as Record<string, unknown>
            await setMode($, READ.has(tool) ? 'reading' : 'coding', detail(tool, rec), { labelShort: target(rec) || tool, tool })
          }
        }
      }
    } catch { /* só informativo */ }
    return next(e)
  })

  // classic.PermissionRequest: o agente parou pedindo permissão
  on('classic.PermissionRequest', async ($, e, next) => {
    const inp = ((e as { tool_input?: unknown }).tool_input ?? {}) as Record<string, unknown>
    subAsk = fromSub(e)
    await setMode($, 'waiting', `permissão para ${e.tool_name}`, { ask: ellipsis(withTarget(String(e.tool_name), inp), ASK_MAX), askKind: 'permissao' }, true)
    return next(e)
  })
  // classic.Notification: avisos do Claude (permissão, "aguardando input")
  on('classic.Notification', async ($, e, next) => {
    const loud = e.notification_type !== 'idle_prompt'
    const msg = ptbr(e.message)
    // mantem o pedido ja conhecido (ferramenta + alvo) se a permissao veio antes
    const cur = await read($, st)
    await setMode($, 'waiting', ellipsis(msg, 50), loud && !(cur.mode === 'waiting' && cur.loud) ? { ask: ellipsis(msg, ASK_MAX), askKind: 'aviso' } : {}, loud)
    return next(e)
  })
  // classic.PostToolUse: ferramenta terminou -> volta a Pensando (modelo lê o resultado)
  on('classic.PostToolUse', async ($, e, next) => {
    if (fromSub(e)) { if (subAsk) { subAsk = false; await resumeMain($) }; return next(e) }
    await backToThinking($, e.tool_name)
    return next(e)
  })
  // classic.PostToolUseFailure: só entra no histórico; o modo se comporta como no PostToolUse
  // (o modo 'error' é só para turno que termina com erro)
  on('classic.PostToolUseFailure', async ($, e, next) => {
    const now = await $.clock.now()
    const sub = fromSub(e)
    // failAt só para a conversa principal: o widget transforma em cena do inseto
    await update($, st, (s: St) => ({ ...s, failAt: sub ? s.failAt : now, history: log(s, now, `${sub ? '↳ ' : ''}falhou: ${e.tool_name}`) }))
    if (sub) { if (subAsk) { subAsk = false; await resumeMain($) }; await publish($); return next(e) }
    await backToThinking($, e.tool_name)
    return next(e)
  })
  // classic.Stop: turno acabou -> Terminou (e guarda quando, para o "terminou há X")
  on('classic.Stop', async ($, e, next) => {
    if (fromSub(e)) return next(e)
    const now = await $.clock.now()
    await setMode($, 'done', 'turno concluído', { busy: false, doneAt: now })
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
      limits: usage?.rateLimits?.length ? limitsOf(usage) : s.limits,
    }))
    await publish($)
    // turno principal que acaba com erro: o turno terminou, então não está mais ocupado
    if (e.reason === 'error' && !fromSub(e)) await setMode($, 'error', 'turno terminou com erro', { busy: false })
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
      await launchWidget($)
      return { text: 'Widget aberto na borda direita da tela.' }
    }
    if (cmd === 'auto' || cmd === 'som') {
      const key = cmd === 'auto' ? 'auto' : 'sound'
      const what = cmd === 'auto' ? 'Abrir o widget ao iniciar a sessão' : 'Som de alerta'
      if (arg !== 'on' && arg !== 'off') {
        const cur = ((await $.store.get(key)) as string) === 'off' ? 'off' : 'on'
        return { text: `${what}: ${cur}. Uso: /claudinho ${cmd} on | off` }
      }
      await $.store.set(key, arg)
      return { text: `${what}: ${arg}` }
    }
    if (cmd === 'lista') return { text: Object.entries(MASCOTS).map(([n, m]) => `${n} — ${m.label}`).join(', ') }
    if (cmd === 'mascote') {
      if (!arg || !MASCOTS[arg]) return { text: `Mascote inválido. Opções: ${Object.keys(MASCOTS).join(', ')}` }
      await $.store.set('mascot', arg)
      await publish($)
      return { text: `Mascote: ${arg}` }
    }
    return { text: 'Uso: /claudinho on | off | auto on|off | som on|off | lista | mascote <nome>' }
  })
}
