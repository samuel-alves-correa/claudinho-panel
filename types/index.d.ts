export type Mode = 'thinking' | 'coding' | 'reading' | 'waiting' | 'idle' | 'done' | 'error'

export type St = {
  mode: Mode
  /** waiting que precisa de você agora (permissão/pergunta), não só "sua vez" */
  loud: boolean
  label: string
  since: number
  frame: number
  sessionStart: number
  turnStart: number
  flashUntil: number
  inTok: number
  outTok: number
  cacheTok: number
  hasUsage: boolean
  ctxPct: number | null
  usd: number | null
  counts: Record<string, number>
  history: { t: number; text: string }[]
  /** quando entrou em waiting (ms epoch); 0 fora de waiting */
  waitSince: number
  /** resumo do que esta sendo pedido: ferramenta + alvo curto */
  ask: string
  /** tokens usados e janela de contexto (so se session.usage informar) */
  ctxTok: number | null
  ctxWin: number | null
}

declare module 'claude-code' {
  interface PluginState {
    'claudinho-panel': { st: Shaped<St> }
  }
}
