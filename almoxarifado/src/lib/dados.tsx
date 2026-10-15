import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';
import { supabase } from './supabase';
import type { Item, Movimentacao, Papel } from './types';

interface Dados {
  email: string;
  papel: Papel;
  podeEditar: boolean;
  admin: boolean;
  itens: Item[];
  abertas: Movimentacao[];          // saídas ainda não devolvidas
  carregando: boolean;
  erro: string | null;
  recarregar: () => Promise<void>;
  aviso: (msg: string, erro?: boolean) => void;
}

const Ctx = createContext<Dados | null>(null);
export const useDados = () => useContext(Ctx)!;

async function todosItens() {
  const lote = 1000;
  const out: Item[] = [];
  for (let de = 0; ; de += lote) {
    const { data, error } = await supabase.from('itens').select('*').order('equipamento').order('id').range(de, de + lote - 1);
    if (error) throw error;
    out.push(...(data as Item[]));
    if (!data || data.length < lote) return out;
  }
}

export function DadosProvider({ email, children }: { email: string; children: ReactNode }) {
  const [papel, setPapel] = useState<Papel>('leitor');
  const [itens, setItens] = useState<Item[]>([]);
  const [abertas, setAbertas] = useState<Movimentacao[]>([]);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<string | null>(null);
  const [toast, setToast] = useState<{ msg: string; erro?: boolean } | null>(null);

  const aviso = useCallback((msg: string, erro?: boolean) => {
    setToast({ msg, erro });
    window.setTimeout(() => setToast(null), 3500);
  }, []);

  const recarregar = useCallback(async () => {
    try {
      const [its, mov, pp] = await Promise.all([
        todosItens(),
        supabase
          .from('movimentacoes')
          .select('*, itens(id, equipamento, codigo_almox, patrimonio, tipo, localizacao)')
          .is('devolvido_em', null)
          .order('saida_em', { ascending: false }),
        supabase.rpc('meu_papel'),
      ]);
      if (mov.error) throw mov.error;
      setItens(its);
      setAbertas(mov.data as Movimentacao[]);
      setPapel((pp.data as Papel) || 'leitor');
      setErro(null);
    } catch (e) {
      setErro((e as Error).message);
    } finally {
      setCarregando(false);
    }
  }, []);

  useEffect(() => {
    recarregar();
  }, [recarregar]);

  const valor: Dados = {
    email, papel, podeEditar: papel === 'admin' || papel === 'operador', admin: papel === 'admin',
    itens, abertas, carregando, erro, recarregar, aviso,
  };
  return (
    <Ctx.Provider value={valor}>
      {children}
      {toast && <div className={'toast' + (toast.erro ? ' bad' : '')} role="status">{toast.msg}</div>}
    </Ctx.Provider>
  );
}
