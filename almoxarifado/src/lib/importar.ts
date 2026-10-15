import * as XLSX from 'xlsx';
import type { ItemNovo } from './types';
import { semAcento } from './util';

// Cabeçalho da planilha (sem acento) -> campo do sistema
const COLUNAS: Record<string, keyof ItemNovo> = {
  'EQUIPAMENTO': 'equipamento',
  'DATA ENTRADA DO ITEM NO ALMOX.': 'data_entrada',
  'PREVISAO VALIDADE/DURACAO ITEM': 'vida_util_anos',
  'MARCA': 'marca',
  'DESCRICAO DETALHADA': 'descricao',
  'MODELO': 'modelo',
  'N° SERIE': 'numero_serie',
  'PATRIMONIO': 'patrimonio',
  'CODIGO ALMOX': 'codigo_almox',
  'ACESSORIOS': 'acessorios',
  'OBSERVACOES': 'observacoes',
  'HISTORICO DO ITEM': 'historico',
  'LOCALIZACAO': 'localizacao',
  'INSPECAO E ENSAIO': 'ultima_inspecao',
  'TIPO': 'tipo',
  'ESTA FORA DA SALA': 'status',
};

const limpa = (v: unknown) => {
  if (v == null) return null;
  const s = String(v).replace(/\r/g, '').trim();
  return s === '' || s === '-' ? null : s;
};

const umaLinha = (v: unknown) => limpa(v)?.replace(/\s*\n\s*/g, ' ').replace(/\s+/g, ' ') ?? null;

function tipo(v: unknown) {
  const t = semAcento(umaLinha(v) || '');
  if (t.startsWith('VIDEO')) return 'VÍDEO';
  if (t.startsWith('AUDIO')) return 'ÁUDIO';
  if (t.startsWith('ILUMIN')) return 'ILUMINAÇÃO';
  return 'OUTROS';
}

function local(v: unknown) {
  let s = umaLinha(v);
  if (!s) return null;
  s = s.replace(/^\*/, '').replace(/[–—]/g, '-').toUpperCase().trim();
  s = s.replace(/\bARMARIO\b/g, 'ARMÁRIO').replace(/^ACIMA DO /, 'ACIMA ');
  s = s.replace(/\s*-\s*(\d+)\b/g, (_, n: string) => ' - ' + n.padStart(3, '0'));
  return s;
}

const p2 = (n: number) => String(n).padStart(2, '0');

function entrada(v: unknown): { texto: string | null; ano: number | null } {
  if (v instanceof Date && !isNaN(v.getTime())) {
    return { texto: `${p2(v.getDate())}/${p2(v.getMonth() + 1)}/${v.getFullYear()}`, ano: v.getFullYear() };
  }
  const texto = umaLinha(v);
  const m = texto?.match(/(19|20)\d{2}/);
  return { texto, ano: m ? Number(m[0]) : null };
}

function inspecao(v: unknown): string | null {
  if (v instanceof Date && !isNaN(v.getTime())) return `${v.getFullYear()}-${p2(v.getMonth() + 1)}-${p2(v.getDate())}`;
  const datas = [...(limpa(v) || '').matchAll(/(\d{1,2})\/(\d{1,2})\/(\d{2,4})/g)];
  const m = datas[datas.length - 1];
  if (!m) return null;
  const ano = m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3]);
  return `${ano}-${p2(Number(m[2]))}-${p2(Number(m[1]))}`;
}

export async function lerPlanilha(arquivo: File): Promise<ItemNovo[]> {
  const wb = XLSX.read(await arquivo.arrayBuffer(), { cellDates: true });
  const ws = wb.Sheets[wb.SheetNames[0]];
  const linhas = XLSX.utils.sheet_to_json<unknown[]>(ws, { header: 1, defval: null, raw: true });
  const iCab = linhas.findIndex((l) => l.some((c) => semAcento(String(c ?? '')).trim() === 'EQUIPAMENTO'));
  if (iCab < 0) throw new Error('Não encontrei a coluna "EQUIPAMENTO" na primeira aba.');

  const mapa = new Map<number, keyof ItemNovo>();
  linhas[iCab].forEach((c, i) => {
    const campo = COLUNAS[semAcento(String(c ?? '')).replace(/\s+/g, ' ').trim()];
    if (campo) mapa.set(i, campo);
  });

  const itens: ItemNovo[] = [];
  for (const l of linhas.slice(iCab + 1)) {
    const bruto: Partial<Record<keyof ItemNovo, unknown>> = {};
    mapa.forEach((campo, i) => (bruto[campo] = l[i]));
    const equipamento = umaLinha(bruto.equipamento);
    if (!equipamento) continue;
    const ent = entrada(bruto.data_entrada);
    const vida = String(bruto.vida_util_anos ?? '').match(/\d+/);
    const fora = semAcento(String(bruto.status ?? '')).trim();
    itens.push({
      equipamento: equipamento.toUpperCase(),
      tipo: tipo(bruto.tipo),
      marca: umaLinha(bruto.marca)?.toUpperCase() ?? null,
      modelo: umaLinha(bruto.modelo),
      descricao: umaLinha(bruto.descricao),
      numero_serie: umaLinha(bruto.numero_serie),
      patrimonio: limpa(bruto.patrimonio),
      codigo_almox: umaLinha(bruto.codigo_almox),
      data_entrada: ent.texto,
      ano_entrada: ent.ano,
      vida_util_anos: vida ? Number(vida[0]) : null,
      localizacao: local(bruto.localizacao),
      acessorios: limpa(bruto.acessorios),
      observacoes: limpa(bruto.observacoes),
      historico: limpa(bruto.historico),
      ultima_inspecao: inspecao(bruto.ultima_inspecao),
      status: fora && fora !== 'NAO' && fora !== 'N' ? 'EM_USO' : 'DISPONIVEL',
    });
  }
  return itens;
}
