import { useState, type FormEvent } from 'react';
import { Mail, KeyRound, ArrowLeft } from 'lucide-react';
import { supabase, emailCorporativo, configurado } from '../lib/supabase';
import { Logo } from '../Logo';
import { BotaoTema } from '../Tema';

export function Login() {
  const [email, setEmail] = useState('');
  const [codigo, setCodigo] = useState('');
  const [etapa, setEtapa] = useState<'email' | 'codigo'>('email');
  const [enviando, setEnviando] = useState(false);
  const [msg, setMsg] = useState<{ t: string; c: 'bad' | 'ok' | 'info' } | null>(null);

  async function enviar(e: FormEvent) {
    e.preventDefault();
    const em = email.trim().toLowerCase();
    if (!emailCorporativo(em)) {
      setMsg({ t: 'Use seu e-mail corporativo @tvevangelizar.com.br ou @evangelizarepreciso.com.br.', c: 'bad' });
      return;
    }
    setEnviando(true);
    setMsg(null);
    const { error } = await supabase.auth.signInWithOtp({
      email: em,
      options: { shouldCreateUser: true, emailRedirectTo: window.location.origin },
    });
    setEnviando(false);
    if (error) return setMsg({ t: traduz(error.message), c: 'bad' });
    setEmail(em);
    setEtapa('codigo');
    setMsg({ t: `Enviamos um código para ${em}. Confira também a caixa de spam.`, c: 'info' });
  }

  async function validar(e: FormEvent) {
    e.preventDefault();
    setEnviando(true);
    const { error } = await supabase.auth.verifyOtp({ email, token: codigo.trim(), type: 'email' });
    setEnviando(false);
    if (error) setMsg({ t: 'Código inválido ou expirado. Peça um novo.', c: 'bad' });
  }

  return (
    <div className="login">
      <div style={{ position: 'fixed', top: 16, right: 16 }}><BotaoTema /></div>
      <div className="card">
        <Logo />
        <div className="tit">
          <h1>Almoxarifado Técnico</h1>
          <p>Controle de equipamentos · Operações Técnicas</p>
        </div>
        {!configurado && (
          <div className="aviso warn">Configure VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY (veja o README).</div>
        )}
        {msg && <div className={'aviso ' + msg.c}>{msg.t}</div>}
        {etapa === 'email' ? (
          <form className="stack" onSubmit={enviar}>
            <label className="campo">
              <span>E-mail corporativo</span>
              <input className="inp" type="email" autoComplete="email" required autoFocus placeholder="nome@tvevangelizar.com.br"
                value={email} onChange={(e) => setEmail(e.target.value)} />
            </label>
            <button className="btn prim" disabled={enviando}><Mail size={16} /> {enviando ? 'Enviando…' : 'Receber código de acesso'}</button>
          </form>
        ) : (
          <form className="stack" onSubmit={validar}>
            <label className="campo">
              <span>Código recebido por e-mail</span>
              <input className="inp codigo" inputMode="numeric" autoComplete="one-time-code" required autoFocus maxLength={10}
                value={codigo} onChange={(e) => setCodigo(e.target.value.replace(/\D/g, ''))} />
            </label>
            <button className="btn prim" disabled={enviando || codigo.length < 6}><KeyRound size={16} /> Entrar</button>
            <button type="button" className="btn" onClick={() => { setEtapa('email'); setCodigo(''); setMsg(null); }}>
              <ArrowLeft size={16} /> Trocar e-mail
            </button>
          </form>
        )}
        <div className="rod">Acesso restrito a colaboradores TV Evangelizar e Evangelizar é Preciso.</div>
      </div>
    </div>
  );
}

function traduz(m: string) {
  if (/rate limit|security purposes/i.test(m)) return 'Muitas tentativas. Aguarde um minuto e tente de novo.';
  if (/restrito|Database error/i.test(m)) return 'E-mail não autorizado para este sistema.';
  return m;
}
