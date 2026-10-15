import { useMemo, useState } from 'react';
import { Search, Plus, Download, ArrowUpRight, X } from 'lucide-react';
import { useDados } from '../lib/dados';
import { useNav } from '../App';
import { STATUS_INFO, TIPOS, type Item } from '../lib/types';
import { contar, diasDesdeInspecao, exportarXlsx, fimVidaUtil, fmtData, precisaReposicao, semAcento, situacaoVida } from '../lib/util';
import { SaidaModal } from './Movimentacoes';

export interface Filtro {
  q?: string;
  tipo?: string;
  status?: string;            // lista separada por vírgula
  local?: string;
  alerta?: 'vencida' | 'vence' | 'reposicao' | 'inspecao';
}

const ALERTAS: Record<NonNullable<Filtro['alerta']>, string> = {
  vencida: 'Vida útil vencida',
  vence: 'Vida útil vencendo',
  reposicao: 'Precisa reposição',
  inspecao: 'Inspeção > 90 dias',
};

type Col = 'equipamento' | 'codigo_almox' | 'patrimonio' | 'tipo' | 'localizacao' | 'status' | 'vida';
const POR_PAGINA = 50;

export function Inventario() {
  const { itens, podeEditar } = useDados();
  const nav = useNav();
  const [f, setF] = useState<Filtro>(nav.filtro);
  const [ord, setOrd] = useState<{ c: Col; asc: boolean }>({ c: 'equipamento', asc: true });
  const [pag, setPag] = useState(0);
  const [sel, setSel] = useState<Set<number>>(new Set());
  const [saida, setSaida] = useState(false);

  const locais = useMemo(() => contar(itens, (i) => i.localizacao).map((x) => x[0]).sort(), [itens]);

  const lista = useMemo(() => {
    const termos = semAcento(f.q || '').split(/\s+/).filter(Boolean);
    const sts = f.status?.split(',');
    const r = itens.filter((i) => {
      if (f.tipo && i.tipo !== f.tipo) return false;
      if (sts && !sts.includes(i.status)) return false;
      if (!sts && i.status === 'BAIXADO' && !f.q) return false;
      if (f.local && (i.localizacao || '—') !== f.local) return false;
      if (f.alerta === 'vencida' && situacaoVida(i) !== 'vencida') return false;
      if (f.alerta === 'vence' && situacaoVida(i) !== 'vence') return false;
      if (f.alerta === 'reposicao' && !precisaReposicao(i)) return false;
      if (f.alerta === 'inspecao') { const d = diasDesdeInspecao(i); if (d != null && d <= 90) return false; }
      if (termos.length) {
        const t = semAcento([i.equipamento, i.descricao, i.marca, i.modelo, i.numero_serie, i.patrimonio, i.codigo_almox, i.localizacao, i.observacoes].join(' '));
        if (!termos.every((x) => t.includes(x))) return false;
      }
      return true;
    });
    const val = (i: Item) => (ord.c === 'vida' ? fimVidaUtil(i) ?? 9999 : (i[ord.c] ?? '') as string | number);
    r.sort((a, b) => {
      const x = val(a), y = val(b);
      const c = typeof x === 'number' && typeof y === 'number' ? x - y : String(x).localeCompare(String(y), 'pt-BR', { numeric: true });
      return ord.asc ? c : -c;
    });
    return r;
  }, [itens, f, ord]);

  const paginas = Math.max(1, Math.ceil(lista.length / POR_PAGINA));
  const visiveis = lista.slice(pag * POR_PAGINA, (pag + 1) * POR_PAGINA);
  const muda = (p: Partial<Filtro>) => { setF((v) => ({ ...v, ...p })); setPag(0); };
  const ordena = (c: Col) => setOrd((o) => ({ c, asc: o.c === c ? !o.asc : true }));
  const th = (c: Col, rot: string) => (
    <th className="ord" onClick={() => ordena(c)}>{rot}{ord.c === c ? (ord.asc ? ' ▲' : ' ▼') : ''}</th>
  );
  const alterna = (id: number) => setSel((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; });
  const temFiltro = Object.values(f).some(Boolean);

  function exportar() {
    exportarXlsx('inventario-almoxarifado', lista.map((i) => ({
      'EQUIPAMENTO': i.equipamento, 'TIPO': i.tipo, 'STATUS': STATUS_INFO[i.status].rotulo, 'MARCA': i.marca, 'MODELO': i.modelo,
      'DESCRIÇÃO': i.descricao, 'Nº SÉRIE': i.numero_serie, 'PATRIMÔNIO': i.patrimonio, 'CÓDIGO ALMOX': i.codigo_almox,
      'LOCALIZAÇÃO': i.localizacao, 'DATA ENTRADA': i.data_entrada, 'VIDA ÚTIL (ANOS)': i.vida_util_anos, 'FIM VIDA ÚTIL': fimVidaUtil(i),
      'ÚLTIMA INSPEÇÃO': i.ultima_inspecao ? fmtData(i.ultima_inspecao) : '', 'ACESSÓRIOS': i.acessorios, 'OBSERVAÇÕES': i.observacoes, 'HISTÓRICO': i.historico,
    })));
  }

  return (
    <>
      <div className="topo">
        <div>
          <h1>Inventário</h1>
          <p>{lista.length.toLocaleString('pt-BR')} de {itens.length.toLocaleString('pt-BR')} itens</p>
        </div>
        <div className="acoes">
          {podeEditar && sel.size > 0 && (
            <button className="btn prim" onClick={() => setSaida(true)}><ArrowUpRight size={15} /> Saída de {sel.size} {sel.size === 1 ? 'item' : 'itens'}</button>
          )}
          <button className="btn" onClick={exportar}><Download size={15} /> Exportar Excel</button>
          {podeEditar && <button className="btn prim" onClick={() => nav.abrirItem('novo')}><Plus size={15} /> Novo item</button>}
        </div>
      </div>

      <div className="card">
        <div className="filtros">
          <div className="busca">
            <Search size={16} />
            <input className="inp" placeholder="Buscar por nome, código, patrimônio, série, marca, local…" value={f.q || ''}
              onChange={(e) => muda({ q: e.target.value })} autoFocus />
          </div>
          <select className="inp" value={f.tipo || ''} onChange={(e) => muda({ tipo: e.target.value || undefined })}>
            <option value="">Todos os tipos</option>
            {TIPOS.map((t) => <option key={t}>{t}</option>)}
          </select>
          <select className="inp" value={f.status || ''} onChange={(e) => muda({ status: e.target.value || undefined })}>
            <option value="">Status (ativos)</option>
            {Object.entries(STATUS_INFO).map(([k, v]) => <option key={k} value={k}>{v.rotulo}</option>)}
            <option value="MANUTENCAO,AVARIADO">Manutenção + avariado</option>
          </select>
          <select className="inp" value={f.local || ''} onChange={(e) => muda({ local: e.target.value || undefined })}>
            <option value="">Todos os locais</option>
            {locais.map((l) => <option key={l}>{l}</option>)}
          </select>
          <div className="chips">
            {(Object.keys(ALERTAS) as (keyof typeof ALERTAS)[]).map((a) => (
              <button key={a} className={'chip' + (f.alerta === a ? ' on' : '')} onClick={() => muda({ alerta: f.alerta === a ? undefined : a })}>{ALERTAS[a]}</button>
            ))}
          </div>
          {temFiltro && <button className="btn sm" onClick={() => { setF({}); setPag(0); }}><X size={14} /> Limpar</button>}
        </div>

        <div className="tabela-wrap so-desk">
          <table>
            <thead>
              <tr>
                {podeEditar && <th style={{ width: 36 }}>
                  <input type="checkbox" aria-label="Selecionar página"
                    checked={visiveis.length > 0 && visiveis.every((i) => sel.has(i.id))}
                    onChange={(e) => setSel((s) => { const n = new Set(s); visiveis.forEach((i) => (e.target.checked && i.status === 'DISPONIVEL' ? n.add(i.id) : n.delete(i.id))); return n; })} />
                </th>}
                {th('equipamento', 'Equipamento')}
                {th('codigo_almox', 'Código')}
                {th('patrimonio', 'Patrimônio')}
                {th('tipo', 'Tipo')}
                {th('localizacao', 'Localização')}
                {th('vida', 'Vida útil')}
                {th('status', 'Status')}
              </tr>
            </thead>
            <tbody>
              {visiveis.map((i) => (
                <tr key={i.id} className={sel.has(i.id) ? 'sel' : ''} onClick={() => nav.abrirItem(i.id)}>
                  {podeEditar && <td onClick={(e) => e.stopPropagation()}>
                    <input type="checkbox" disabled={i.status !== 'DISPONIVEL'} checked={sel.has(i.id)} onChange={() => alterna(i.id)} aria-label="Selecionar" />
                  </td>}
                  <td><div className="t1">{i.equipamento}</div><div className="t2">{[i.marca, i.modelo].filter(Boolean).join(' · ') || i.descricao}</div></td>
                  <td className="mono">{i.codigo_almox || '—'}</td>
                  <td className="mono">{i.patrimonio || '—'}</td>
                  <td>{i.tipo}</td>
                  <td>{i.localizacao || '—'}</td>
                  <td><Vida i={i} /></td>
                  <td><StatusPill s={i.status} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="lista-mobile">
          {visiveis.map((i) => (
            <div key={i.id} className="linha" onClick={() => nav.abrirItem(i.id)}>
              <div className="l1"><span className="t1" style={{ fontWeight: 600 }}>{i.equipamento}</span><StatusPill s={i.status} /></div>
              <div className="muted" style={{ fontSize: 12 }}>
                cód. {i.codigo_almox || '—'} · pat. {i.patrimonio || '—'} · {i.localizacao || 'sem local'}
              </div>
              <div><Vida i={i} /></div>
            </div>
          ))}
        </div>

        {lista.length === 0 && <div className="vazio">Nenhum item encontrado com esses filtros.</div>}
        {paginas > 1 && (
          <div className="paginacao">
            <span>Página {pag + 1} de {paginas}</span>
            <button className="btn sm" disabled={pag === 0} onClick={() => setPag(pag - 1)}>Anterior</button>
            <button className="btn sm" disabled={pag >= paginas - 1} onClick={() => setPag(pag + 1)}>Próxima</button>
          </div>
        )}
      </div>

      {saida && (
        <SaidaModal iniciais={itens.filter((i) => sel.has(i.id))} fechar={(ok) => { setSaida(false); if (ok) setSel(new Set()); }} />
      )}
    </>
  );
}

export function StatusPill({ s }: { s: Item['status'] }) {
  const i = STATUS_INFO[s];
  return <span className={'pill ' + i.cls}>{i.rotulo}</span>;
}

export function Vida({ i }: { i: Item }) {
  const fim = fimVidaUtil(i);
  const s = situacaoVida(i);
  if (fim == null) return <span className="muted">—</span>;
  const cls = s === 'vencida' ? 'bad' : s === 'vence' ? 'warn' : 'mute';
  return <span className={'pill ' + cls} title={`Entrada ${i.data_entrada || '?'} + ${i.vida_util_anos} anos`}>{s === 'vencida' ? 'Venceu' : 'Até'} {fim}</span>;
}
