import * as XLSX from 'xlsx';
import type { Item } from './types';

export const ANO_ATUAL = new Date().getFullYear();
const DIA = 86400000;

export function fimVidaUtil(i: Pick<Item, 'ano_entrada' | 'vida_util_anos'>) {
  return i.ano_entrada && i.vida_util_anos ? i.ano_entrada + i.vida_util_anos : null;
}

/** 'vencida' | 'vence' (este ano ou próximo) | 'ok' | null (sem dados) */
export function situacaoVida(i: Pick<Item, 'ano_entrada' | 'vida_util_anos'>) {
  const fim = fimVidaUtil(i);
  if (fim == null) return null;
  if (fim < ANO_ATUAL) return 'vencida';
  if (fim <= ANO_ATUAL + 1) return 'vence';
  return 'ok';
}

export function precisaReposicao(i: Pick<Item, 'observacoes' | 'historico'>) {
  const t = `${i.observacoes || ''} ${i.historico || ''}`.toUpperCase();
  return /AGUARDANDO REPOSI|NECESSIDADE DE REPOSI/.test(t);
}

export function diasDesdeInspecao(i: Pick<Item, 'ultima_inspecao'>) {
  if (!i.ultima_inspecao) return null;
  return Math.floor((Date.now() - new Date(i.ultima_inspecao + 'T12:00:00').getTime()) / DIA);
}

export function fmtData(s: string | null | undefined, hora = false) {
  if (!s) return '—';
  const d = new Date(s.length === 10 ? s + 'T12:00:00' : s);
  if (isNaN(d.getTime())) return s;
  return hora
    ? d.toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' })
    : d.toLocaleDateString('pt-BR');
}

export function hojeISO() {
  const d = new Date();
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
}

export function semAcento(s: string) {
  return s.normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase();
}

export function contar<T>(lista: T[], chave: (x: T) => string | null | undefined) {
  const m = new Map<string, number>();
  for (const x of lista) {
    const k = chave(x) || '—';
    m.set(k, (m.get(k) || 0) + 1);
  }
  return [...m.entries()].sort((a, b) => b[1] - a[1]);
}

export function exportarXlsx(nome: string, linhas: Record<string, unknown>[]) {
  const ws = XLSX.utils.json_to_sheet(linhas);
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Dados');
  XLSX.writeFile(wb, `${nome}-${hojeISO()}.xlsx`);
}
