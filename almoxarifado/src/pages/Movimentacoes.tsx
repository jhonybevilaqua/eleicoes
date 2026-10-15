import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { ArrowUpRight, ArrowDownLeft, Search, X, Download } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { useDados } from '../lib/dados';
import { useNav } from '../App';
import type { Item, Movimentacao } from '../lib/types';
import { exportarXlsx, fmtData, semAcento } from '../lib/util';

const SETORES = ['JORNALISMO', 'PRODUÇÃO', 'ENGENHARIA', 'PROGRAMAÇÃO', 'TI', 'OPERAÇÕES TÉCNICAS', 'EVENTOS', 'MARKETING', 'ÁUDIO', 'ILUMINAÇÃO'];

export function Movimentacoes() {
  const { abertas, podeEditar } = useDados();
  const { abrirItem } = useNav();
  const [aba, setAba] = useState<'fora' | 'hist'>('fora');
  const [nova, setNova] = useState(false);
  const [sel, setSel] = useState<Set<number>>(new Set());
  const [devolver, setDevolver] = useState<Movimentacao[] | null>(null);
  const [q, setQ] = useState('');
  const [hist, setHist] = useState<Movimentacao[] | null>(null);

  useEffect(() => {
    if (aba !== 'hist' || hist) return;
    supabase.from('movimentacoes').select('*, itens(id, equipamento, codigo_almox, patrimonio, tipo, localizacao)')
      .order('saida_em', { ascending: false }).limit(1000)
      .then(({ data }) => setHist((data as Movimentacao[]) || []));
  }, [aba, hist]);

  const agora = Date.now();
  const filtra = (l: Movimentacao[]) => {
    const t = semAcento(q).split(/\s+/).filter(Boolean);
    if (!t.length) return l;
    return l.filter((m) => {
      const s = semAcento([m.itens?.equipamento, m.itens?.codigo_almox, m.itens?.patrimonio, m.responsavel, m.setor, m.destino].join(' '));
      return t.every((x) => s.includes(x));
    });
  };
  const lista = useMemo(() => filtra(aba === 'fora' ? abertas : hist || []), [aba, abertas, hist, q]);

  // agrupa saídas abertas por lote para devolver o kit inteiro de uma vez
  const lotes = useMemo(() => {
    const m = new Map<string, Movimentacao[]>();
    abertas.forEach((x) => m.set(x.lote, [...(m.get(x.lote) || []), x]));
    return m;
  }, [abertas]);

  const alterna = (id: number) => setSel((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; });

  function exportar() {
    exportarXlsx(aba === 'fora' ? 'itens-fora' : 'movimentacoes', lista.map((m) => ({
      'EQUIPAMENTO': m.itens?.equipamento, 'CÓDIGO': m.itens?.codigo_almox, 'PATRIMÔNIO': m.itens?.patrimonio,
      'RESPONSÁVEL': m.responsavel, 'SETOR': m.setor, 'DESTINO/EVENTO': m.destino, 'SAÍDA': fmtData(m.saida_em, true),
      'PREVISÃO RETORNO': fmtData(m.previsao_retorno, true), 'DEVOLVIDO': fmtData(m.devolvido_em, true), 'CONDIÇÃO': m.condicao_retorno,
      'OBS. SAÍDA': m.obs_saida, 'OBS. RETORNO': m.obs_retorno, 'REGISTRADO POR': m.registrado_por, 'RECEBIDO POR': m.recebido_por,
    })));
  }

  return (
    <>
      <div className="topo">
        <div><h1>Saídas e devoluções</h1><p>{abertas.length} {abertas.length === 1 ? 'item fora' : 'itens fora'} do almoxarifado</p></div>
        <div className="acoes">
          {podeEditar && sel.size > 0 && aba === 'fora' && (
            <button className="btn prim" onClick={() => setDevolver(abertas.filter((m) => sel.has(m.id)))}><ArrowDownLeft size={15} /> Devolver {sel.size}</button>
          )}
          <button className="btn" onClick={exportar}><Download size={15} /> Exportar</button>
          {podeEditar && <button className="btn prim" onClick={() => setNova(true)}><ArrowUpRight size={15} /> Nova saída</button>}
        </div>
      </div>

      <div className="card">
        <div className="abas">
          <button className={'aba' + (aba === 'fora' ? ' on' : '')} onClick={() => setAba('fora')}>Fora agora ({abertas.length})</button>
          <button className={'aba' + (aba === 'hist' ? ' on' : '')} onClick={() => setAba('hist')}>Histórico</button>
        </div>
        <div className="filtros">
          <div className="busca"><Search size={16} />
            <input className="inp" placeholder="Buscar equipamento, código, responsável, setor, evento…" value={q} onChange={(e) => setQ(e.target.value)} /></div>
        </div>
        {aba === 'hist' && !hist ? <div className="carregando" style={{ minHeight: 200 }}><div className="spin" /></div> : (
          <div className="tabela-wrap">
            <table>
              <thead>
                <tr>
                  {podeEditar && aba === 'fora' && <th style={{ width: 36 }} />}
                  <th>Equipamento</th><th>Responsável</th><th className="so-desk">Destino / evento</th><th>Saída</th>
                  <th>{aba === 'fora' ? 'Previsão' : 'Devolução'}</th>
                  {podeEditar && aba === 'fora' && <th className="so-desk" />}
                </tr>
              </thead>
              <tbody>
                {lista.map((m) => {
                  const atrasado = !m.devolvido_em && m.previsao_retorno && new Date(m.previsao_retorno).getTime() < agora;
                  const kit = lotes.get(m.lote) || [];
                  return (
                    <tr key={m.id} className={sel.has(m.id) ? 'sel' : ''} onClick={() => abrirItem(m.item_id)}>
                      {podeEditar && aba === 'fora' && <td onClick={(e) => e.stopPropagation()}>
                        <input type="checkbox" checked={sel.has(m.id)} onChange={() => alterna(m.id)} aria-label="Selecionar" /></td>}
                      <td><div className="t1">{m.itens?.equipamento || '(item excluído)'}</div>
                        <div className="t2">cód. {m.itens?.codigo_almox || '—'} · pat. {m.itens?.patrimonio || '—'}</div></td>
                      <td>{m.responsavel}<div className="t2">{m.setor}</div></td>
                      <td className="so-desk">{m.destino || '—'}{m.obs_saida && <div className="t2">{m.obs_saida}</div>}</td>
                      <td>{fmtData(m.saida_em, true)}</td>
                      <td className={atrasado ? 'atrasado' : ''}>
                        {aba === 'fora' ? fmtData(m.previsao_retorno, true) : m.devolvido_em ? (
                          <>{fmtData(m.devolvido_em, true)}<div className="t2">{m.condicao_retorno}</div></>
                        ) : <span className="pill info">Fora</span>}
                      </td>
                      {podeEditar && aba === 'fora' && <td className="so-desk" onClick={(e) => e.stopPropagation()}>
                        <div className="row" style={{ flexWrap: 'nowrap' }}>
                          <button className="btn sm" onClick={() => setDevolver([m])}>Devolver</button>
                          {kit.length > 1 && <button className="btn sm" onClick={() => setDevolver(kit)} title="Devolver todos os itens que saíram juntos">Kit ({kit.length})</button>}
                        </div>
                      </td>}
                    </tr>
                  );
                })}
              </tbody>
            </table>
            {lista.length === 0 && <div className="vazio">{aba === 'fora' ? 'Nenhum item fora do almoxarifado.' : 'Nenhuma movimentação.'}</div>}
          </div>
        )}
      </div>

      {nova && <SaidaModal iniciais={[]} fechar={() => setNova(false)} />}
      {devolver && <DevolucaoModal movs={devolver} fechar={(ok) => { setDevolver(null); if (ok) { setSel(new Set()); setHist(null); } }} />}
    </>
  );
}

export function SaidaModal({ iniciais, fechar }: { iniciais: Item[]; fechar: (ok?: boolean) => void }) {
  const { itens, email, recarregar, aviso } = useDados();
  const [carrinho, setCarrinho] = useState<Item[]>(iniciais);
  const [busca, setBusca] = useState('');
  const [responsavel, setResponsavel] = useState('');
  const [setor, setSetor] = useState('');
  const [destino, setDestino] = useState('');
  const [previsao, setPrevisao] = useState('');
  const [obs, setObs] = useState('');
  const [salvando, setSalvando] = useState(false);

  const sugestoes = useMemo(() => {
    const t = semAcento(busca).split(/\s+/).filter(Boolean);
    if (!t.length) return [];
    return itens.filter((i) => {
      const s = semAcento([i.equipamento, i.codigo_almox, i.patrimonio, i.numero_serie, i.marca, i.modelo].join(' '));
      return t.every((x) => s.includes(x));
    }).slice(0, 30);
  }, [busca, itens]);

  async function salvar(e: FormEvent) {
    e.preventDefault();
    if (!carrinho.length) return aviso('Adicione pelo menos um item', true);
    setSalvando(true);
    const lote = crypto.randomUUID();
    const { error } = await supabase.from('movimentacoes').insert(carrinho.map((i) => ({
      item_id: i.id, lote, responsavel: responsavel.trim(), setor: setor.trim().toUpperCase() || null, destino: destino.trim() || null,
      previsao_retorno: previsao ? new Date(previsao).toISOString() : null, obs_saida: obs.trim() || null, registrado_por: email,
    })));
    setSalvando(false);
    if (error) return aviso(/mov_uma_saida_aberta|duplicate/.test(error.message) ? 'Algum item já está fora. Atualize a página.' : error.message, true);
    aviso(`Saída registrada: ${carrinho.length} ${carrinho.length === 1 ? 'item' : 'itens'}`);
    await recarregar();
    fechar(true);
  }

  return (
    <div className="fundo centro" onClick={() => fechar()}>
      <form className="modal" onClick={(e) => e.stopPropagation()} onSubmit={salvar}>
        <div className="d-head"><h2>Registrar saída</h2>
          <div className="acoes"><button type="button" className="btn icone" onClick={() => fechar()} aria-label="Fechar"><X size={18} /></button></div></div>
        <div className="d-body">
          <div className="stack">
            <div className="busca"><Search size={16} />
              <input className="inp" placeholder="Adicionar item: nome, código, patrimônio…" value={busca} onChange={(e) => setBusca(e.target.value)} autoFocus /></div>
            {sugestoes.length > 0 && (
              <div className="sugestoes">
                {sugestoes.map((i) => (
                  <button type="button" key={i.id} disabled={i.status !== 'DISPONIVEL' || carrinho.some((c) => c.id === i.id)}
                    onClick={() => { setCarrinho((c) => [...c, i]); setBusca(''); }}>
                    <b>{i.equipamento}</b> <span className="muted">· cód. {i.codigo_almox || '—'} · pat. {i.patrimonio || '—'} · {i.localizacao || ''}</span>
                    {i.status !== 'DISPONIVEL' && <span className="pill warn" style={{ marginLeft: 6 }}>indisponível</span>}
                  </button>
                ))}
              </div>
            )}
            <div className="carrinho">
              {carrinho.map((i) => (
                <div key={i.id} className="ln"><b>{i.equipamento}</b><span className="muted">cód. {i.codigo_almox || '—'}</span>
                  <button type="button" className="btn sm icone x" onClick={() => setCarrinho((c) => c.filter((x) => x.id !== i.id))} aria-label="Remover"><X size={14} /></button></div>
              ))}
              {!carrinho.length && <div className="muted">Nenhum item adicionado.</div>}
            </div>
          </div>
          <div className="grid-form">
            <label className="campo"><span>Responsável *</span><input className="inp" required value={responsavel} onChange={(e) => setResponsavel(e.target.value)} placeholder="Quem retira" /></label>
            <label className="campo"><span>Setor</span><input className="inp" list="l-setores" value={setor} onChange={(e) => setSetor(e.target.value)} /></label>
            <label className="campo"><span>Destino / evento / pauta</span><input className="inp" value={destino} onChange={(e) => setDestino(e.target.value)} /></label>
            <label className="campo"><span>Previsão de retorno</span><input className="inp" type="datetime-local" value={previsao} onChange={(e) => setPrevisao(e.target.value)} /></label>
            <label className="campo full"><span>Observações</span><textarea className="inp" value={obs} onChange={(e) => setObs(e.target.value)} /></label>
          </div>
          <datalist id="l-setores">{SETORES.map((s) => <option key={s} value={s} />)}</datalist>
        </div>
        <div className="d-foot">
          <button type="button" className="btn" onClick={() => fechar()}>Cancelar</button>
          <button className="btn prim" disabled={salvando || !carrinho.length}>{salvando ? 'Salvando…' : `Confirmar saída (${carrinho.length})`}</button>
        </div>
      </form>
    </div>
  );
}

export function DevolucaoModal({ movs, fechar }: { movs: Movimentacao[]; fechar: (ok?: boolean) => void }) {
  const { email, recarregar, aviso } = useDados();
  const [cond, setCond] = useState<'OK' | 'AVARIADO' | 'MANUTENCAO'>('OK');
  const [obs, setObs] = useState('');
  const [salvando, setSalvando] = useState(false);

  async function salvar(e: FormEvent) {
    e.preventDefault();
    setSalvando(true);
    const { error } = await supabase.from('movimentacoes')
      .update({ devolvido_em: new Date().toISOString(), condicao_retorno: cond, obs_retorno: obs.trim() || null, recebido_por: email })
      .in('id', movs.map((m) => m.id));
    setSalvando(false);
    if (error) return aviso(error.message, true);
    aviso(`Devolução registrada: ${movs.length} ${movs.length === 1 ? 'item' : 'itens'}`);
    await recarregar();
    fechar(true);
  }

  return (
    <div className="fundo centro" onClick={() => fechar()}>
      <form className="modal" onClick={(e) => e.stopPropagation()} onSubmit={salvar}>
        <div className="d-head"><h2>Registrar devolução</h2>
          <div className="acoes"><button type="button" className="btn icone" onClick={() => fechar()} aria-label="Fechar"><X size={18} /></button></div></div>
        <div className="d-body">
          <div className="carrinho">
            {movs.map((m) => <div key={m.id} className="ln"><b>{m.itens?.equipamento}</b><span className="muted">cód. {m.itens?.codigo_almox || '—'} · com {m.responsavel}</span></div>)}
          </div>
          <div className="campo"><span>Condição na devolução</span>
            <div className="chips">
              {([['OK', 'OK'], ['AVARIADO', 'Avariado'], ['MANUTENCAO', 'Enviar p/ manutenção']] as const).map(([k, r]) => (
                <button type="button" key={k} className={'chip' + (cond === k ? ' on' : '')} onClick={() => setCond(k)}>{r}</button>
              ))}
            </div>
          </div>
          <label className="campo"><span>Observações {cond !== 'OK' && '(descreva o problema)'}</span>
            <textarea className="inp" value={obs} onChange={(e) => setObs(e.target.value)} required={cond !== 'OK'} /></label>
        </div>
        <div className="d-foot">
          <button type="button" className="btn" onClick={() => fechar()}>Cancelar</button>
          <button className="btn prim" disabled={salvando}>{salvando ? 'Salvando…' : 'Confirmar devolução'}</button>
        </div>
      </form>
    </div>
  );
}
