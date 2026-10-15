import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const configurado = Boolean(url && key);

export const supabase = createClient(url || 'http://localhost', key || 'anon', {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
});

export const DOMINIOS = ['tvevangelizar.com.br', 'evangelizarepreciso.com.br'];

export function emailCorporativo(email: string) {
  const d = email.trim().toLowerCase().split('@')[1] || '';
  return DOMINIOS.includes(d);
}

export const EMAIL_DONO = 'jhony.bevilaqua@tvevangelizar.com.br';
