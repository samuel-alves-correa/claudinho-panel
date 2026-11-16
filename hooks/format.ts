// Funções puras de texto usadas por register.tsx (sem acesso a `$`).
import type { St } from '../types'

// Corta em n caracteres; o que passar vira "…" no fim (o total nunca passa de n).
export const ellipsis = (t: string, n: number): string => (t.length > n ? t.slice(0, n - 1) + '…' : t)

const str = (v: unknown): string => (typeof v === 'string' ? v : '')

// "Edit em pasta/arquivo.ts", "Bash: npm test"...
export function detail(tool: string, e: Record<string, unknown>): string {
  const file = str(e.file_path) || str(e.notebook_path)
  if (file) return `${tool} em ${ellipsis(file.replace(/\\/g, '/').split('/').slice(-2).join('/'), 38)}`
  if (str(e.command)) return `${tool}: ${ellipsis(str(e.command).split('\n')[0] ?? '', 34)}`
  if (str(e.pattern)) return `${tool}: ${ellipsis(str(e.pattern), 30)}`
  if (str(e.query)) return `${tool}: ${ellipsis(str(e.query), 30)}`
  if (str(e.url)) return `${tool}: ${ellipsis(str(e.url), 30)}`
  return tool
}

// Alvo curto (max ~28 chars): arquivo, 2 primeiras palavras do comando, host da url. Sem segredos longos.
export function target(e: Record<string, unknown>): string {
  const cut = (t: string) => ellipsis(t, 28)
  const file = str(e.file_path) || str(e.notebook_path)
  if (file) return cut(file.replace(/\\/g, '/').split('/').pop() ?? '')
  const cmd = str(e.command)
  if (cmd) return cut((cmd.split('\n')[0] ?? '').trim().split(/\s+/).slice(0, 2).join(' '))
  if (str(e.pattern)) return cut(str(e.pattern))
  if (str(e.query)) return cut(str(e.query))
  if (str(e.url)) return cut(str(e.url).replace(/^https?:\/\//, '').split('/')[0] ?? '')
  return ''
}

export const withTarget = (tool: string, e: Record<string, unknown>): string => {
  const t = target(e)
  return t ? `${tool} · ${t}` : tool
}

// Mensagens comuns do Claude Code em pt-BR; desconhecida passa como está.
export function ptbr(m: string): string {
  const perm = /needs your permission to use (.+?)\.?$/i.exec(m)
  if (perm) return `precisa da sua permissão para usar ${perm[1]}`
  if (/needs your permission/i.test(m)) return 'precisa da sua permissão'
  if (/waiting for your input/i.test(m)) return 'aguardando sua resposta'
  return m
}

// "claude-fable-5-2" -> "Fable 5.2"; o que não reconhecer passa como está.
export function prettyModel(id: string): string {
  const m = id.replace(/^claude-/, '').replace(/-\d{8}$/, '')
  const p = /^([a-z]+)-(\d+)(?:-(\d+))?(.*)$/.exec(m)
  if (!p) return id
  const fam = p[1] ?? ''
  return `${fam.charAt(0).toUpperCase()}${fam.slice(1)} ${p[2]}${p[3] ? '.' + p[3] : ''}${p[4] ?? ''}`
}

// Janelas de limite de uso como o widget desenha: % usado e quando reinicia (ms epoch; 0 = sem data).
export function limitsOf(usage: unknown): St['limits'] {
  const rows = ((usage as { rateLimits?: unknown } | undefined)?.rateLimits ?? []) as {
    kind: string; percentUsed: number; resetsAt?: string
  }[]
  return rows.map(r => ({ kind: r.kind, pct: r.percentUsed, resetsAt: r.resetsAt ? Date.parse(r.resetsAt) || 0 : 0 }))
}
