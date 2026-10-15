export type Status = 'DISPONIVEL' | 'EM_USO' | 'MANUTENCAO' | 'AVARIADO' | 'BAIXADO';
export type Papel = 'admin' | 'operador' | 'leitor';

export interface Item {
  id: number;
  equipamento: string;
  tipo: string;
  marca: string | null;
  modelo: string | null;
  descricao: string | null;
  numero_serie: string | null;
  patrimonio: string | null;
  codigo_almox: string | null;
  data_entrada: string | null;
  ano_entrada: number | null;
  vida_util_anos: number | null;
  localizacao: string | null;
  acessorios: string | null;
  observacoes: string | null;
  historico: string | null;
  ultima_inspecao: string | null;
  status: Status;
  created_at: string;
  updated_at: string;
  updated_by: string | null;
}

export type ItemNovo = Omit<Item, 'id' | 'created_at' | 'updated_at' | 'updated_by'>;

export interface Movimentacao {
  id: number;
  item_id: number;
  lote: string;
  responsavel: string;
  setor: string | null;
  destino: string | null;
  saida_em: string;
  previsao_retorno: string | null;
  devolvido_em: string | null;
  condicao_retorno: 'OK' | 'AVARIADO' | 'MANUTENCAO' | null;
  obs_saida: string | null;
  obs_retorno: string | null;
  registrado_por: string | null;
  recebido_por: string | null;
  itens?: Pick<Item, 'id' | 'equipamento' | 'codigo_almox' | 'patrimonio' | 'tipo' | 'localizacao'> | null;
}

export interface Evento {
  id: number;
  item_id: number | null;
  acao: string;
  detalhe: string | null;
  usuario: string | null;
  created_at: string;
  itens?: Pick<Item, 'equipamento' | 'codigo_almox'> | null;
}

export interface Usuario {
  email: string;
  nome: string | null;
  papel: Papel;
  created_at: string;
}

export const STATUS_INFO: Record<Status, { rotulo: string; cls: string }> = {
  DISPONIVEL: { rotulo: 'Disponível', cls: 'ok' },
  EM_USO: { rotulo: 'Em uso / fora', cls: 'info' },
  MANUTENCAO: { rotulo: 'Manutenção', cls: 'warn' },
  AVARIADO: { rotulo: 'Avariado', cls: 'bad' },
  BAIXADO: { rotulo: 'Baixado', cls: 'mute' },
};

export const TIPOS = ['VÍDEO', 'ÁUDIO', 'ILUMINAÇÃO', 'OUTROS'];
