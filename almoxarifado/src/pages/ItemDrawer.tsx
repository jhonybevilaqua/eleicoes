import { useEffect, useState, type FormEvent } from 'react';
import { X, Pencil, Copy, Trash2, ClipboardCheck, ArrowUpRight, ArrowDownLeft } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { useDados } from '../lib/dados';
import { STATUS_INFO, TIPOS, type Evento, type Item, type ItemNovo, type Status } from '../lib/types';
import { fimVidaUtil, fmtData, hojeISO, precisaReposicao } from '../lib/util';
import { StatusPill, Vida } from './Inventario';
import { DevolucaoModal, SaidaModal } from './Movimentacoes';

const VAZIO: ItemNovo = {
  equipamento: '', tipo: 'VÍDEO', marca: null, modelo: null, descricao: null, numero_serie: null, patrimonio: null,
  codigo_almox: null, data_entrada: null, ano_entrada: new Date().getFullYear(), vida_util_anos: 5, localizacao: null,
  acessorios: null, observacoes: null, historico: null, ultima_inspecao: null, status: 'DISPONIVEL',
};

export function ItemDrawer({ id, fechar }: { id: number | 'novo'; fechar: () => void }) {
  const { itens, abertas, podeEditar, admin, recarregar, aviso } = useDados();
  const item = id === 'novo' ? null : itens.find((i) => i.id === id) || null;
  const [modo, setModo] = useState<'ver' | 'editar' | 'novo'>(id === 'novo' ? 'novo' : 'ver');
  const [base, setBase] = useState<ItemNovo>(VAZIO);
  const [eventos, setEventos] = useState<Evento[]>([]);
  const [saida, setSaida] = useState(false);
  const [devolver, setDevolver] = useState(false);
  const aberta = item ? abertas.find((m) => m.item_id === item.id) : undefined;

  useEffect(() => {
    if (!item) return;
    supabase.from('eventos').select('*').eq('item_id', item.id).order('created_at', { ascending: false }).limit(100)
      .then(({ data }) => setEventos((data as Evento[]) || []));
  }, [item?.id, item?.updated_at]);

  useEffect(() => {
    const esc = (e: KeyboardEvent) => e.key === 'Escape' && fechar();
    window.addEventListener('keydown', esc);
    return () => window.removeEventListener('keydown', esc);
  }, [fechar]);

  async function atualizar(campos: Partial<Item>, msg: string) {
    const { error } = await supabase.from('itens').update(campos).eq('id', item!.id);
    if (error) return aviso(error.message, true);
    aviso(msg);
    recarregar();
  }

  async function excluir() {
    if (!confirm(`Excluir "${item!.equipamento}" definitivamente? Prefira o status "Baixado" para manter o histórico.`)) return;
    const { error } = await supabase.from('itens').delete().eq('id', item!.id);
    if (error) return aviso(error.message, true);
    aviso('Item excluído');
    fechar();
    recarregar();
  }

  if (modo !== 'ver' || !item) {
    const inicial = modo === 'editar' && item ? item : base;
    return (
      <div className="fundo" onClick={fechar}>
        <div className="drawer" onClick={(e) => e.stopPropagation()}>
          <FormItem inicial={inicial} editandoId={modo === 'editar' ? item?.id : undefined}
            cancelar={() => (item ? setModo('ver') : fechar())}
            salvo={() => { recarregar(); item && modo === 'editar' ? setModo('ver') : fechar(); }} />
        </div>
      </div>
    );
  }

  const fim = fimVidaUtil(item);
  return (
    <div className="fundo" onClick={fechar}>
      <div className="drawer" onClick={(e) => e.stopPropagation()}>
        <div className="d-head">
          <div>
            <h2>{item.equipamento}</h2>
            <div className="row" style={{ marginTop: 6 }}>
              <StatusPill s={item.status} /><span className="pill mute">{item.tipo}</span><Vida i={item} />
              {precisaReposicao(item) && <span className="pill bad">Precisa reposição</span>}
            </div>
          </div>
          <div className="acoes"><button className="btn icone" onClick={fechar} aria-label="Fechar"><X size={18} /></button></div>
        </div>

        <div className="d-body">
          {aberta && (
            <div className="aviso info">
              Fora desde {fmtData(aberta.saida_em, true)} com <b>{aberta.responsavel}</b>
              {aberta.setor && ` (${aberta.setor})`}{aberta.destino && ` · ${aberta.destino}`}
              {aberta.previsao_retorno && <> · retorno previsto {fmtData(aberta.previsao_retorno, true)}</>}
            </div>
          )}

          {podeEditar && (
            <div className="row">
              {item.status === 'DISPONIVEL' && <button className="btn prim sm" onClick={() => setSaida(true)}><ArrowUpRight size={14} /> Registrar saída</button>}
              {aberta && <button className="btn prim sm" onClick={() => setDevolver(true)}><ArrowDownLeft size={14} /> Registrar devolução</button>}
              <button className="btn sm" onClick={() => atualizar({ ultima_inspecao: hojeISO() }, 'Inspeção registrada')}><ClipboardCheck size={14} /> Inspecionado hoje</button>
              <button className="btn sm" onClick={() => setModo('editar')}><Pencil size={14} /> Editar</button>
              <button className="btn sm" onClick={() => { const { id: _i, created_at: _c, updated_at: _u, updated_by: _b, ...resto } = item; setBase({ ...resto, numero_serie: null, patrimonio: null, codigo_almox: null, status: 'DISPONIVEL' }); setModo('novo'); }}>
                <Copy size={14} /> Duplicar
              </button>
              {!aberta && (
                <select className="inp" style={{ width: 'auto', height: 30 }} value={item.status}
                  onChange={(e) => atualizar({ status: e.target.value as Status }, 'Status alterado')}>
                  {(Object.keys(STATUS_INFO) as Status[]).filter((s) => s !== 'EM_USO').map((s) => <option key={s} value={s}>{STATUS_INFO[s].rotulo}</option>)}
                </select>
              )}
              {admin && <button className="btn sm perigo" onClick={excluir}><Trash2 size={14} /> Excluir</button>}
            </div>
          )}

          <dl className="dl">
            <dt>Código almox.</dt><dd className="mono">{item.codigo_almox || '—'}</dd>
            <dt>Patrimônio</dt><dd className="mono">{item.patrimonio || '—'}</dd>
            <dt>Nº de série</dt><dd className="mono">{item.numero_serie || '—'}</dd>
            <dt>Marca / modelo</dt><dd>{[item.marca, item.modelo].filter(Boolean).join(' · ') || '—'}</dd>
            <dt>Descrição</dt><dd>{item.descricao || '—'}</dd>
            <dt>Localização</dt><dd>{item.localizacao || '—'}</dd>
            <dt>Entrada</dt><dd>{item.data_entrada || '—'}</dd>
            <dt>Vida útil</dt><dd>{item.vida_util_anos ? `${item.vida_util_anos} anos${fim ? ` · até ${fim}` : ''}` : '—'}</dd>
            <dt>Última inspeção</dt><dd>{fmtData(item.ultima_inspecao)}</dd>
            <dt>Acessórios</dt><dd>{item.acessorios || '—'}</dd>
            <dt>Observações</dt><dd>{item.observacoes || '—'}</dd>
            <dt>Histórico (planilha)</dt><dd>{item.historico || '—'}</dd>
            <dt>Atualizado</dt><dd className="muted">{fmtData(item.updated_at, true)}{item.updated_by ? ` · ${item.updated_by}` : ''}</dd>
          </dl>

          <div>
            <h3 style={{ marginBottom: 10 }}>Linha do tempo</h3>
            {eventos.length === 0 ? <div className="muted">Sem eventos registrados no sistema.</div> : (
              <div className="tl">
                {eventos.map((e) => (
                  <div key={e.id} className="ev">
                    <span className="pt" />
                    <div><b>{e.acao}</b> {e.detalhe && <span>— {e.detalhe}</span>}
                      <div className="q">{fmtData(e.created_at, true)} · {e.usuario || 'sistema'}</div></div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
      {saida && <SaidaModal iniciais={[item]} fechar={() => setSaida(false)} />}
      {devolver && aberta && <DevolucaoModal movs={[aberta]} fechar={() => setDevolver(false)} />}
    </div>
  );
}

function FormItem({ inicial, editandoId, cancelar, salvo }: { inicial: ItemNovo; editandoId?: number; cancelar: () => void; salvo: () => void }) {
  const { itens, aviso } = useDados();
  const [v, setV] = useState<ItemNovo>(() => {
    const { id: _i, created_at: _c, updated_at: _u, updated_by: _b, ...r } = inicial as Item;
    return r;
  });
  const [salvando, setSalvando] = useState(false);
  const locais = [...new Set(itens.map((i) => i.localizacao).filter(Boolean))].sort() as string[];
  const nomes = [...new Set(itens.map((i) => i.equipamento))].sort();
  const marcas = [...new Set(itens.map((i) => i.marca).filter(Boolean))].sort() as string[];

  const set = <K extends keyof ItemNovo>(k: K) => (e: { target: { value: string } }) => {
    const raw = e.target.value;
    const num = k === 'ano_entrada' || k === 'vida_util_anos';
    setV((s) => ({ ...s, [k]: raw === '' ? null : num ? Number(raw) : raw }));
  };

  async function salvar(e: FormEvent) {
    e.preventDefault();
    setSalvando(true);
    const dados = { ...v, equipamento: v.equipamento.trim().toUpperCase() };
    const r = editandoId
      ? await supabase.from('itens').update(dados).eq('id', editandoId)
      : await supabase.from('itens').insert(dados);
    setSalvando(false);
    if (r.error) return aviso(r.error.message, true);
    aviso(editandoId ? 'Item atualizado' : 'Item cadastrado');
    salvo();
  }

  const txt = (k: keyof ItemNovo, rot: string, extra: Record<string, unknown> = {}) => (
    <label className="campo"><span>{rot}</span>
      <input className="inp" value={(v[k] as string | number | null) ?? ''} onChange={set(k)} {...extra} /></label>
  );

  return (
    <form onSubmit={salvar} style={{ display: 'contents' }}>
      <div className="d-head">
        <h2>{editandoId ? 'Editar item' : 'Novo item'}</h2>
        <div className="acoes"><button type="button" className="btn icone" onClick={cancelar} aria-label="Fechar"><X size={18} /></button></div>
      </div>
      <div className="d-body">
        <div className="grid-form">
          <div className="full">{txt('equipamento', 'Equipamento *', { required: true, list: 'l-nomes' })}</div>
          <label className="campo"><span>Tipo</span>
            <select className="inp" value={v.tipo} onChange={set('tipo')}>{TIPOS.map((t) => <option key={t}>{t}</option>)}</select></label>
          {txt('localizacao', 'Localização', { list: 'l-locais' })}
          {txt('marca', 'Marca', { list: 'l-marcas' })}
          {txt('modelo', 'Modelo')}
          {txt('codigo_almox', 'Código almox.')}
          {txt('patrimonio', 'Patrimônio')}
          {txt('numero_serie', 'Nº de série')}
          {txt('data_entrada', 'Data de entrada (texto)', { placeholder: 'ex.: 15/03/2026' })}
          {txt('ano_entrada', 'Ano de entrada', { type: 'number', min: 1990, max: 2100 })}
          {txt('vida_util_anos', 'Vida útil (anos)', { type: 'number', min: 0, max: 50 })}
          {txt('ultima_inspecao', 'Última inspeção', { type: 'date' })}
          <label className="campo full"><span>Descrição detalhada</span><textarea className="inp" value={v.descricao ?? ''} onChange={set('descricao')} /></label>
          <label className="campo full"><span>Acessórios</span><textarea className="inp" value={v.acessorios ?? ''} onChange={set('acessorios')} /></label>
          <label className="campo full"><span>Observações</span><textarea className="inp" value={v.observacoes ?? ''} onChange={set('observacoes')} /></label>
          <label className="campo full"><span>Histórico</span><textarea className="inp" value={v.historico ?? ''} onChange={set('historico')} /></label>
        </div>
        <datalist id="l-nomes">{nomes.map((n) => <option key={n} value={n} />)}</datalist>
        <datalist id="l-locais">{locais.map((n) => <option key={n} value={n} />)}</datalist>
        <datalist id="l-marcas">{marcas.map((n) => <option key={n} value={n} />)}</datalist>
      </div>
      <div className="d-foot">
        <button type="button" className="btn" onClick={cancelar}>Cancelar</button>
        <button className="btn prim" disabled={salvando}>{salvando ? 'Salvando…' : 'Salvar'}</button>
      </div>
    </form>
  );
}
