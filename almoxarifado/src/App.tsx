import { createContext, useContext, useEffect, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { LayoutDashboard, Package, ArrowLeftRight, Users, FileUp, LogOut, Menu, History, KeyRound } from 'lucide-react';
import { supabase, emailCorporativo } from './lib/supabase';
import { DadosProvider, useDados } from './lib/dados';
import { Logo } from './Logo';
import { BotaoTema } from './Tema';
import { Login } from './pages/Login';
import { Painel } from './pages/Painel';
import { Inventario, type Filtro } from './pages/Inventario';
import { Movimentacoes } from './pages/Movimentacoes';
import { Atividade } from './pages/Atividade';
import { Usuarios } from './pages/Usuarios';
import { Importar } from './pages/Importar';
import { ItemDrawer } from './pages/ItemDrawer';
import { SenhaModal } from './pages/Usuarios';

type Pagina = 'painel' | 'inventario' | 'movimentacoes' | 'atividade' | 'usuarios' | 'importar';

interface Nav {
  ir: (p: Pagina, filtro?: Filtro) => void;
  abrirItem: (id: number | 'novo') => void;
  filtro: Filtro;
}
const NavCtx = createContext<Nav | null>(null);
export const useNav = () => useContext(NavCtx)!;

export default function App() {
  const [sessao, setSessao] = useState<Session | null | undefined>(undefined);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSessao(data.session));
    const { data } = supabase.auth.onAuthStateChange((_e, s) => setSessao(s));
    return () => data.subscription.unsubscribe();
  }, []);

  if (sessao === undefined) return <div className="carregando"><div className="spin" /></div>;
  const email = sessao?.user.email || '';
  if (!sessao || !emailCorporativo(email)) {
    if (sessao) supabase.auth.signOut();
    return <Login />;
  }
  return (
    <DadosProvider email={email}>
      <Shell />
    </DadosProvider>
  );
}

function paginaDoHash(): Pagina {
  const h = window.location.hash.replace('#/', '') as Pagina;
  return ['painel', 'inventario', 'movimentacoes', 'atividade', 'usuarios', 'importar'].includes(h) ? h : 'painel';
}

function Shell() {
  const { email, papel, admin, carregando, erro, abertas, itens } = useDados();
  const [pagina, setPagina] = useState<Pagina>(paginaDoHash);
  const [filtro, setFiltro] = useState<Filtro>({});
  const [menu, setMenu] = useState(false);
  const [item, setItem] = useState<number | 'novo' | null>(null);
  const [senha, setSenha] = useState(false);

  useEffect(() => {
    const f = () => setPagina(paginaDoHash());
    window.addEventListener('hashchange', f);
    return () => window.removeEventListener('hashchange', f);
  }, []);

  const nav: Nav = {
    ir: (p, f) => {
      setFiltro(f || {});
      window.location.hash = '/' + p;
      setPagina(p);
      setMenu(false);
      window.scrollTo(0, 0);
    },
    abrirItem: setItem,
    filtro,
  };

  const links: { p: Pagina; rot: string; Icone: typeof Package; cont?: number; so?: boolean }[] = [
    { p: 'painel', rot: 'Painel', Icone: LayoutDashboard },
    { p: 'inventario', rot: 'Inventário', Icone: Package, cont: itens.length },
    { p: 'movimentacoes', rot: 'Saídas e devoluções', Icone: ArrowLeftRight, cont: abertas.length },
    { p: 'atividade', rot: 'Atividade', Icone: History },
    { p: 'usuarios', rot: 'Usuários', Icone: Users, so: !admin },
    { p: 'importar', rot: 'Importar planilha', Icone: FileUp, so: !admin },
  ];

  const papelRot = { admin: 'Administrador', operador: 'Operador', leitor: 'Somente leitura' }[papel];

  return (
    <NavCtx.Provider value={nav}>
      <div className="app">
        <div className={'veu' + (menu ? ' aberta' : '')} onClick={() => setMenu(false)} />
        <aside className={'side' + (menu ? ' aberta' : '')}>
          <div className="marca"><Logo /></div>
          <div className="sub">Almoxarifado Técnico</div>
          {links.filter((l) => !l.so).map(({ p, rot, Icone, cont }) => (
            <button key={p} className={'nav-btn' + (pagina === p ? ' ativo' : '')} onClick={() => nav.ir(p)}>
              <Icone size={17} /> {rot}
              {!!cont && p === 'movimentacoes' && <span className="cont">{cont}</span>}
            </button>
          ))}
          <div className="rodape">
            <div className="quem"><b>{email.split('@')[0]}</b>{papelRot}</div>
            <BotaoTema comTexto />
            <button className="nav-btn" onClick={() => { setSenha(true); setMenu(false); }}><KeyRound size={17} /> Alterar senha</button>
            <button className="nav-btn" onClick={() => supabase.auth.signOut()}><LogOut size={17} /> Sair</button>
          </div>
        </aside>
        <div>
          <div className="mobile-bar">
            <button className="btn icone" onClick={() => setMenu(true)} aria-label="Menu"><Menu size={18} /></button>
            <Logo />
            <div style={{ marginLeft: 'auto' }}><BotaoTema /></div>
          </div>
          <main className="main">
            {erro && <div className="aviso bad" style={{ marginBottom: 16 }}>Erro ao carregar dados: {erro}</div>}
            {carregando ? (
              <div className="carregando"><div className="spin" /></div>
            ) : (
              <>
                {pagina === 'painel' && <Painel />}
                {pagina === 'inventario' && <Inventario key={JSON.stringify(filtro)} />}
                {pagina === 'movimentacoes' && <Movimentacoes />}
                {pagina === 'atividade' && <Atividade />}
                {pagina === 'usuarios' && admin && <Usuarios />}
                {pagina === 'importar' && admin && <Importar />}
              </>
            )}
          </main>
        </div>
      </div>
      {item != null && <ItemDrawer id={item} fechar={() => setItem(null)} />}
      {senha && <SenhaModal fechar={() => setSenha(false)} />}
    </NavCtx.Provider>
  );
}
