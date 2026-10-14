-- MOOVE: atualização completa e transacional para o esquema existente do TCC.
-- Execute o arquivo INTEIRO no SQL Editor do Supabase como administrador.
-- Mantém tabelas/usuários/dados. Não cria o esquema base do TCC.
-- Faz alterações em funções e políticas; use backup antes de aplicar em produção.
BEGIN;
DO $$
DECLARE v_nome text;
BEGIN
 FOREACH v_nome IN ARRAY ARRAY['auth.users','public.perfis','public.clientes','public.vendedores','public.entregadores','public.funcionarios','public.enderecos','public.perfil_enderecos','public.entregas','public.historico_entregas','public.documentos_entregadores','public.veiculos','public.comprovantes_entrega','public.pagamentos'] LOOP
  IF to_regclass(v_nome) IS NULL THEN RAISE EXCEPTION 'Tabela obrigatória ausente: %. Importe o esquema base do TCC antes de atualizar o Moove.',v_nome; END IF;
 END LOOP;
END $$;




-- MOOVE: execute UMA VEZ no SQL Editor, após conferir os nomes do seu schema.
-- Não apaga tabelas nem usuários. Funções SECURITY DEFINER exigem revisão cuidadosa.
-- Estas funções usam auth.uid() do JWT fornecido pelo Supabase/PostgREST.

CREATE OR REPLACE FUNCTION public.moove_conta_autorizada()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users u
    JOIN public.perfis p ON p.id = u.id
    WHERE u.id = (SELECT auth.uid())
      AND u.email_confirmed_at IS NOT NULL
      AND p.status = 'ativo'
  );
$$;
REVOKE ALL ON FUNCTION public.moove_conta_autorizada() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.moove_conta_autorizada() TO authenticated;

-- Cria ou reutiliza endereço físico, permitindo que duas pessoas usem o mesmo local.
CREATE OR REPLACE FUNCTION public.moove_salvar_endereco(
  p_cep text, p_logradouro text, p_numero text, p_complemento text,
  p_bairro text, p_cidade text, p_estado text,
  p_tipo text DEFAULT 'residencial', p_nome_endereco text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_cep text := regexp_replace(coalesce(p_cep,''), '[^0-9]', '', 'g');
  v_logradouro text := btrim(coalesce(p_logradouro,''));
  v_numero text := btrim(coalesce(p_numero,''));
  v_complemento text := nullif(btrim(coalesce(p_complemento,'')), '');
  v_id bigint;
BEGIN
  IF NOT public.moove_conta_autorizada() THEN
    RAISE EXCEPTION 'Confirme seu e-mail para continuar.';
  END IF;
  IF v_cep !~ '^[0-9]{8}$'
     OR length(v_logradouro) < 3 OR length(v_numero) < 1
     OR length(btrim(coalesce(p_bairro,''))) < 2
     OR length(btrim(coalesce(p_cidade,''))) < 2
     OR upper(coalesce(p_estado,'')) !~ '^[A-Z]{2}$'
     OR p_tipo NOT IN ('residencial','comercial','coleta','entrega','outro')
  THEN
    RAISE EXCEPTION 'Endereço inválido.';
  END IF;
  -- Não inclui dados pessoais na chave única; endereços físicos são compartilháveis.
  INSERT INTO public.enderecos
    (cep, logradouro, numero, complemento, bairro, cidade, estado)
  VALUES
    (v_cep, v_logradouro, v_numero, v_complemento,
     btrim(p_bairro), btrim(p_cidade), upper(p_estado))
  ON CONFLICT DO NOTHING
  RETURNING id_endereco INTO v_id;

  IF v_id IS NULL THEN
    SELECT e.id_endereco INTO v_id
    FROM public.enderecos e
    WHERE e.cep = v_cep
      AND lower(e.logradouro) = lower(v_logradouro)
      AND e.numero = v_numero
      AND coalesce(lower(e.complemento),'') = coalesce(lower(v_complemento),'')
    LIMIT 1;
  END IF;
  IF v_id IS NULL THEN RAISE EXCEPTION 'Endereço inválido.'; END IF;

  INSERT INTO public.perfil_enderecos
    (perfil_id, id_endereco, tipo, nome_endereco)
  VALUES
    ((SELECT auth.uid()), v_id, p_tipo::public.tipo_endereco, nullif(btrim(coalesce(p_nome_endereco,'')),''))
  ON CONFLICT (perfil_id, id_endereco)
  DO UPDATE SET ativo = true,
                tipo = EXCLUDED.tipo,
                nome_endereco = EXCLUDED.nome_endereco;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.moove_salvar_endereco(text,text,text,text,text,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.moove_salvar_endereco(text,text,text,text,text,text,text,text,text) TO authenticated;

-- Apenas endereços de coleta/comerciais vinculados a vendedores são divulgados.
CREATE OR REPLACE FUNCTION public.moove_pontos_coleta()
RETURNS TABLE (
  id_vendedor bigint,
  nome_estabelecimento text,
  id_endereco_origem bigint,
  bairro text,
  cidade text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT v.id_vendedor,
         v.nome_estabelecimento::text,
         pe.id_endereco,
         e.bairro::text,
         e.cidade::text
  FROM public.vendedores v
  JOIN public.perfis p ON p.id = v.perfil_id AND p.status = 'ativo'
  JOIN public.perfil_enderecos pe ON pe.perfil_id = v.perfil_id
    AND pe.ativo = true AND pe.tipo IN ('comercial','coleta')
  JOIN public.enderecos e ON e.id_endereco = pe.id_endereco
  WHERE public.moove_conta_autorizada()
  ORDER BY v.nome_estabelecimento, e.cidade, e.bairro;
$$;
REVOKE ALL ON FUNCTION public.moove_pontos_coleta() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.moove_pontos_coleta() TO authenticated;

-- Frete fixo de demonstração: R$ 25,00. Calcule o valor no SERVIDOR antes de produção.
CREATE OR REPLACE FUNCTION public.moove_criar_entrega(
  p_id_vendedor bigint,
  p_id_endereco_origem bigint,
  p_id_endereco_destino bigint,
  p_descricao_carga text,
  p_peso_kg numeric
)
RETURNS TABLE (id_entrega bigint, codigo_rastreio text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_cliente bigint;
  v_id bigint;
BEGIN
  IF NOT public.moove_conta_autorizada() THEN
    RAISE EXCEPTION 'Confirme seu e-mail para continuar.';
  END IF;
  SELECT c.id_cliente INTO v_cliente
  FROM public.clientes c WHERE c.perfil_id = (SELECT auth.uid());
  IF v_cliente IS NULL THEN RAISE EXCEPTION 'Seu cadastro de cliente não foi criado. Verifique o trigger de cadastro no Supabase.'; END IF;
  IF p_peso_kg IS NULL OR p_peso_kg <= 0 OR p_peso_kg > 1000
     OR length(btrim(coalesce(p_descricao_carga,''))) NOT BETWEEN 3 AND 255 THEN
    RAISE EXCEPTION 'Dados da entrega inválidos.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.perfil_enderecos pe
    WHERE pe.perfil_id = (SELECT auth.uid())
      AND pe.id_endereco = p_id_endereco_destino AND pe.ativo = true
  ) THEN
    RAISE EXCEPTION 'Cadastre um endereço de destino válido.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.vendedores v
    JOIN public.perfis p ON p.id = v.perfil_id AND p.status = 'ativo'
    JOIN public.perfil_enderecos pe ON pe.perfil_id = v.perfil_id
    WHERE v.id_vendedor = p_id_vendedor
      AND pe.id_endereco = p_id_endereco_origem
      AND pe.ativo = true AND pe.tipo IN ('comercial','coleta')
  ) THEN
    RAISE EXCEPTION 'Ponto de coleta indisponível.';
  END IF;
  IF p_id_endereco_origem = p_id_endereco_destino THEN
    RAISE EXCEPTION 'Origem e destino precisam ser diferentes.';
  END IF;
  INSERT INTO public.entregas AS nova (
    id_cliente, id_vendedor, id_endereco_origem, id_endereco_destino,
    descricao_carga, peso_kg, valor_frete
  ) VALUES (
    v_cliente, p_id_vendedor, p_id_endereco_origem, p_id_endereco_destino,
    btrim(p_descricao_carga), p_peso_kg, 25.00
  ) RETURNING nova.id_entrega INTO v_id;
  RETURN QUERY
    SELECT e.id_entrega::bigint, e.codigo_rastreio::text
    FROM public.entregas e WHERE e.id_entrega = v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.moove_criar_entrega(bigint,bigint,bigint,text,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.moove_criar_entrega(bigint,bigint,bigint,text,numeric) TO authenticated;

-- Retorna histórico SOMENTE se a entrega pertence ao cliente autenticado.
CREATE OR REPLACE FUNCTION public.moove_historico_entrega(p_id_entrega bigint)
RETURNS TABLE (status text, descricao text, registrado_em timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NOT public.moove_conta_autorizada() THEN
    RAISE EXCEPTION 'Confirme seu e-mail para continuar.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.entregas e
    JOIN public.clientes c ON c.id_cliente = e.id_cliente
    WHERE e.id_entrega = p_id_entrega AND c.perfil_id = (SELECT auth.uid())
  ) THEN RAISE EXCEPTION 'Entrega não encontrada.'; END IF;
  RETURN QUERY
    SELECT h.status::text, h.descricao::text, h.registrado_em::timestamptz
    FROM public.historico_entregas h
    WHERE h.id_entrega = p_id_entrega
    ORDER BY h.registrado_em ASC, h.id_historico ASC;
END;
$$;
REVOKE ALL ON FUNCTION public.moove_historico_entrega(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.moove_historico_entrega(bigint) TO authenticated;

-- Após executar, confirme que as funções aparecem em Database > Functions.
-- Se alterou nomes das tabelas/colunas no projeto, adapte o SQL antes de executar.


-- MOOVE / EXTENSÃO OPERACIONAL — executar DEPOIS de 01_funcoes_moove.sql
-- Não cria usuários Auth, não apaga tabelas e não promove funcionários automaticamente.
-- Revise este arquivo e faça backup antes de executar em PRODUCTION.

-- Validador local: não depende de função externa do esquema do TCC.
CREATE OR REPLACE FUNCTION public.moove_validar_cnpj(p_cnpj text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE v_soma integer; v_digito integer; v_pos integer; v_i integer; v_pesos integer[];
BEGIN
 IF p_cnpj IS NULL OR p_cnpj !~ '^[0-9]{14}$' OR p_cnpj ~ '^([0-9])\1{13}$' THEN RETURN false; END IF;
 FOR v_pos IN 13..14 LOOP
  v_pesos := CASE WHEN v_pos=13 THEN ARRAY[5,4,3,2,9,8,7,6,5,4,3,2]
             ELSE ARRAY[6,5,4,3,2,9,8,7,6,5,4,3,2] END;
  v_soma := 0;
  FOR v_i IN 1..(v_pos-1) LOOP
   v_soma := v_soma + substring(p_cnpj,v_i,1)::integer * v_pesos[v_i];
  END LOOP;
  v_digito := CASE WHEN v_soma % 11 < 2 THEN 0 ELSE 11 - (v_soma % 11) END;
  IF substring(p_cnpj,v_pos,1)::integer <> v_digito THEN RETURN false; END IF;
 END LOOP;
 RETURN true;
END; $$;
REVOKE ALL ON FUNCTION public.moove_validar_cnpj(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_validar_cnpj(text) TO authenticated;

-- As aprovações são explícitas e feitas por administrador humano.
CREATE TABLE IF NOT EXISTS public.moove_funcionarios_autorizados (
  perfil_id uuid PRIMARY KEY REFERENCES public.perfis(id) ON DELETE CASCADE,
  autorizado_em timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.moove_vendedores_aprovados (
  id_vendedor bigint PRIMARY KEY REFERENCES public.vendedores(id_vendedor) ON DELETE CASCADE,
  aprovado_em timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.moove_entregadores_aprovados (
  id_entregador bigint PRIMARY KEY REFERENCES public.entregadores(id_entregador) ON DELETE CASCADE,
  aprovado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.moove_funcionarios_autorizados ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.moove_vendedores_aprovados ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.moove_entregadores_aprovados ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.moove_funcionarios_autorizados, public.moove_vendedores_aprovados, public.moove_entregadores_aprovados FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.moove_eh_gestor()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
 SELECT public.moove_conta_autorizada()
    AND EXISTS (SELECT 1 FROM public.funcionarios f
      JOIN public.moove_funcionarios_autorizados a ON a.perfil_id = f.perfil_id
      WHERE f.perfil_id = (SELECT auth.uid()));
$$;
REVOKE ALL ON FUNCTION public.moove_eh_gestor() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.moove_eh_gestor() TO authenticated;

-- Cadastro de vendedor e entregador: NÃO significa aprovação para operar.
CREATE OR REPLACE FUNCTION public.moove_cadastrar_vendedor(p_nome text, p_cnpj text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id bigint; v_old public.vendedores%ROWTYPE; v_cnpj text := nullif(regexp_replace(coalesce(p_cnpj,''),'[^0-9]','','g'),'');
BEGIN
 IF NOT public.moove_conta_autorizada() THEN RAISE EXCEPTION 'Confirme seu e-mail para continuar.'; END IF;
 IF length(btrim(coalesce(p_nome,''))) NOT BETWEEN 3 AND 150 THEN RAISE EXCEPTION 'Nome do estabelecimento inválido.'; END IF;
 IF v_cnpj IS NOT NULL AND NOT public.moove_validar_cnpj(v_cnpj) THEN RAISE EXCEPTION 'CNPJ inválido.'; END IF;
 PERFORM 1 FROM public.perfis WHERE id=auth.uid() FOR UPDATE;
 SELECT * INTO v_old FROM public.vendedores WHERE perfil_id=auth.uid();
 INSERT INTO public.vendedores(perfil_id,nome_estabelecimento,cnpj)
 VALUES (auth.uid(),btrim(p_nome),v_cnpj)
 ON CONFLICT (perfil_id) DO UPDATE SET nome_estabelecimento = EXCLUDED.nome_estabelecimento, cnpj = EXCLUDED.cnpj
 RETURNING id_vendedor INTO v_id;
 IF v_old.id_vendedor IS NOT NULL AND (v_old.nome_estabelecimento IS DISTINCT FROM btrim(p_nome) OR v_old.cnpj IS DISTINCT FROM v_cnpj) THEN
  DELETE FROM public.moove_vendedores_aprovados WHERE id_vendedor=v_id;
 END IF;
 RETURN v_id;
END; $$;
REVOKE ALL ON FUNCTION public.moove_cadastrar_vendedor(text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_cadastrar_vendedor(text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.moove_cadastrar_entregador()
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id bigint;
BEGIN
 IF NOT public.moove_conta_autorizada() THEN RAISE EXCEPTION 'Confirme seu e-mail para continuar.'; END IF;
 INSERT INTO public.entregadores(perfil_id,disponivel) VALUES (auth.uid(),false)
 ON CONFLICT (perfil_id) DO UPDATE SET perfil_id = EXCLUDED.perfil_id
 RETURNING id_entregador INTO v_id;
 RETURN v_id;
END; $$;
REVOKE ALL ON FUNCTION public.moove_cadastrar_entregador() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_cadastrar_entregador() TO authenticated;

CREATE OR REPLACE FUNCTION public.moove_documento_entregador(p_cnh text, p_validade date)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id bigint;
BEGIN
 IF NOT public.moove_conta_autorizada() THEN RAISE EXCEPTION 'Conta não autorizada.'; END IF;
 SELECT id_entregador INTO v_id FROM public.entregadores WHERE perfil_id = auth.uid();
 IF v_id IS NULL OR btrim(coalesce(p_cnh,'')) !~ '^[0-9]{9,11}$' OR p_validade IS NULL OR p_validade <= current_date THEN
  RAISE EXCEPTION 'Informe CNH numérica e validade futura.';
 END IF;
 INSERT INTO public.documentos_entregadores(id_entregador,numero_cnh,validade_cnh)
 VALUES (v_id,btrim(p_cnh),p_validade)
 ON CONFLICT (id_entregador) DO UPDATE SET numero_cnh = EXCLUDED.numero_cnh,
 validade_cnh = EXCLUDED.validade_cnh, atualizado_em = now();
 -- Alteração de documentos exige NOVA aprovação.
 DELETE FROM public.moove_entregadores_aprovados WHERE id_entregador = v_id;
 UPDATE public.entregadores SET disponivel=false WHERE id_entregador=v_id;
END; $$;
REVOKE ALL ON FUNCTION public.moove_documento_entregador(text,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_documento_entregador(text,date) TO authenticated;

CREATE OR REPLACE FUNCTION public.moove_salvar_veiculo(p_tipo text,p_marca text,p_modelo text,p_placa text,p_capacidade numeric)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_driver bigint; v_id bigint; v_placa text := upper(regexp_replace(coalesce(p_placa,''),'[^A-Za-z0-9]','','g'));
BEGIN
 IF NOT public.moove_conta_autorizada() THEN RAISE EXCEPTION 'Conta não autorizada.'; END IF;
 SELECT id_entregador INTO v_driver FROM public.entregadores WHERE perfil_id=auth.uid();
 IF v_driver IS NULL OR v_placa !~ '^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$'
 OR length(btrim(coalesce(p_tipo,''))) < 3 OR length(btrim(coalesce(p_marca,''))) < 2
 OR length(btrim(coalesce(p_modelo,''))) < 2 OR p_capacidade IS NULL OR p_capacidade <= 0
 THEN RAISE EXCEPTION 'Dados do veículo inválidos.'; END IF;
 INSERT INTO public.veiculos(id_entregador,tipo,marca,modelo,placa,capacidade_kg)
 VALUES(v_driver,btrim(p_tipo),btrim(p_marca),btrim(p_modelo),v_placa,p_capacidade)
 RETURNING id_veiculo INTO v_id;
 RETURN v_id;
END; $$;
REVOKE ALL ON FUNCTION public.moove_salvar_veiculo(text,text,text,text,numeric) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_salvar_veiculo(text,text,text,text,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.moove_disponibilidade(p_disponivel boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id bigint;
BEGIN
 IF NOT public.moove_conta_autorizada() THEN RAISE EXCEPTION 'Conta não autorizada.'; END IF;
 SELECT id_entregador INTO v_id FROM public.entregadores WHERE perfil_id=auth.uid();
 IF v_id IS NULL THEN RAISE EXCEPTION 'Cadastre-se como entregador.'; END IF;
 IF p_disponivel AND NOT EXISTS (
   SELECT 1 FROM public.moove_entregadores_aprovados a
   JOIN public.documentos_entregadores d ON d.id_entregador=a.id_entregador AND d.validade_cnh > current_date
   JOIN public.veiculos v ON v.id_entregador=a.id_entregador AND v.ativo=true
   WHERE a.id_entregador=v_id
 ) THEN RAISE EXCEPTION 'Aguarde aprovação, cadastre CNH válida e veículo ativo.'; END IF;
 UPDATE public.entregadores SET disponivel=p_disponivel WHERE id_entregador=v_id;
END; $$;
REVOKE ALL ON FUNCTION public.moove_disponibilidade(boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_disponibilidade(boolean) TO authenticated;

-- Endereço principal: remove o principal anterior antes de marcar o novo.
CREATE OR REPLACE FUNCTION public.moove_endereco_principal(p_id_endereco bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.moove_conta_autorizada() THEN RAISE EXCEPTION 'Conta não autorizada.'; END IF;
 PERFORM 1 FROM public.perfis WHERE id=auth.uid() FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM public.perfil_enderecos WHERE perfil_id=auth.uid() AND id_endereco=p_id_endereco AND ativo) THEN
  RAISE EXCEPTION 'Endereço não encontrado.';
 END IF;
 UPDATE public.perfil_enderecos SET principal=false WHERE perfil_id=auth.uid() AND principal;
 UPDATE public.perfil_enderecos SET principal=true WHERE perfil_id=auth.uid() AND id_endereco=p_id_endereco;
END; $$;
REVOKE ALL ON FUNCTION public.moove_endereco_principal(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_endereco_principal(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.moove_endereco_desativar(p_id_endereco bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.moove_conta_autorizada() THEN RAISE EXCEPTION 'Conta não autorizada.'; END IF;
 UPDATE public.perfil_enderecos SET ativo=false, principal=false
 WHERE perfil_id=auth.uid() AND id_endereco=p_id_endereco;
 IF NOT FOUND THEN RAISE EXCEPTION 'Endereço não encontrado.'; END IF;
END; $$;
REVOKE ALL ON FUNCTION public.moove_endereco_desativar(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_endereco_desativar(bigint) TO authenticated;

-- Reforço do controle de aprovação nos pontos de coleta (substitui funções do arquivo 01).
CREATE OR REPLACE FUNCTION public.moove_pontos_coleta()
RETURNS TABLE(id_vendedor bigint,nome_estabelecimento text,id_endereco_origem bigint,bairro text,cidade text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
 SELECT v.id_vendedor,v.nome_estabelecimento::text,pe.id_endereco,e.bairro::text,e.cidade::text
 FROM public.vendedores v
 JOIN public.moove_vendedores_aprovados a ON a.id_vendedor=v.id_vendedor
 JOIN public.perfis p ON p.id=v.perfil_id AND p.status='ativo'
 JOIN public.perfil_enderecos pe ON pe.perfil_id=v.perfil_id AND pe.ativo AND pe.tipo IN ('comercial','coleta')
 JOIN public.enderecos e ON e.id_endereco=pe.id_endereco
 WHERE public.moove_conta_autorizada()
 ORDER BY v.nome_estabelecimento,e.cidade,e.bairro;
$$;
REVOKE ALL ON FUNCTION public.moove_pontos_coleta() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_pontos_coleta() TO authenticated;

CREATE OR REPLACE FUNCTION public.moove_criar_entrega(
 p_id_vendedor bigint,p_id_endereco_origem bigint,p_id_endereco_destino bigint,p_descricao_carga text,p_peso_kg numeric)
RETURNS TABLE(id_entrega bigint,codigo_rastreio text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_cliente bigint; v_id bigint;
BEGIN
 IF NOT public.moove_conta_autorizada() THEN RAISE EXCEPTION 'Confirme seu e-mail para continuar.'; END IF;
 SELECT c.id_cliente INTO v_cliente FROM public.clientes c WHERE c.perfil_id=auth.uid();
 IF v_cliente IS NULL THEN RAISE EXCEPTION 'Seu cadastro de cliente não foi criado. Verifique o trigger de cadastro no Supabase.'; END IF;
 IF p_peso_kg IS NULL OR p_peso_kg <= 0 OR p_peso_kg > 1000
 OR length(btrim(coalesce(p_descricao_carga,''))) NOT BETWEEN 3 AND 255 THEN RAISE EXCEPTION 'Dados da entrega inválidos.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.perfil_enderecos pe
 WHERE pe.perfil_id=auth.uid() AND pe.id_endereco=p_id_endereco_destino AND pe.ativo)
 THEN RAISE EXCEPTION 'Cadastre um endereço de destino válido.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.vendedores v
 JOIN public.moove_vendedores_aprovados a ON a.id_vendedor=v.id_vendedor
 JOIN public.perfis p ON p.id=v.perfil_id AND p.status='ativo'
 JOIN public.perfil_enderecos pe ON pe.perfil_id=v.perfil_id
 WHERE v.id_vendedor=p_id_vendedor AND pe.id_endereco=p_id_endereco_origem
 AND pe.ativo AND pe.tipo IN ('comercial','coleta'))
 THEN RAISE EXCEPTION 'Ponto de coleta indisponível.'; END IF;
 IF p_id_endereco_origem=p_id_endereco_destino THEN RAISE EXCEPTION 'Origem e destino precisam ser diferentes.'; END IF;
 INSERT INTO public.entregas AS nova(id_cliente,id_vendedor,id_endereco_origem,id_endereco_destino,descricao_carga,peso_kg,valor_frete)
 VALUES(v_cliente,p_id_vendedor,p_id_endereco_origem,p_id_endereco_destino,btrim(p_descricao_carga),p_peso_kg,25.00)
 RETURNING nova.id_entrega INTO v_id;
 RETURN QUERY SELECT e.id_entrega::bigint,e.codigo_rastreio::text FROM public.entregas e WHERE e.id_entrega=v_id;
END; $$;
REVOKE ALL ON FUNCTION public.moove_criar_entrega(bigint,bigint,bigint,text,numeric) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_criar_entrega(bigint,bigint,bigint,text,numeric) TO authenticated;

-- Atribuição concorrente segura: bloqueia a entrega enquanto o motorista assume.
CREATE OR REPLACE FUNCTION public.moove_assumir_entrega(p_id_entrega bigint,p_id_veiculo bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_driver bigint; v_status public.status_entrega;
BEGIN
 IF NOT public.moove_conta_autorizada() THEN RAISE EXCEPTION 'Conta não autorizada.'; END IF;
 SELECT id_entregador INTO v_driver FROM public.entregadores WHERE perfil_id=auth.uid() AND disponivel;
 IF v_driver IS NULL OR NOT EXISTS(SELECT 1 FROM public.moove_entregadores_aprovados WHERE id_entregador=v_driver)
 OR NOT EXISTS(SELECT 1 FROM public.documentos_entregadores WHERE id_entregador=v_driver AND validade_cnh > current_date)
 THEN RAISE EXCEPTION 'Entregador indisponível ou não aprovado.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.veiculos WHERE id_veiculo=p_id_veiculo AND id_entregador=v_driver AND ativo)
 THEN RAISE EXCEPTION 'Veículo não autorizado.'; END IF;
 SELECT status INTO v_status FROM public.entregas WHERE id_entrega=p_id_entrega AND id_entregador IS NULL FOR UPDATE;
 IF v_status IS NULL OR v_status NOT IN ('solicitada','aguardando_entregador') THEN
  RAISE EXCEPTION 'Entrega não disponível para coleta.';
 END IF;
 IF EXISTS (SELECT 1 FROM public.entregas e JOIN public.veiculos v ON v.id_veiculo=p_id_veiculo
 WHERE e.id_entrega=p_id_entrega AND e.peso_kg > v.capacidade_kg) THEN
  RAISE EXCEPTION 'Carga acima da capacidade do veículo.'; END IF;
 UPDATE public.entregas SET id_entregador=v_driver,id_veiculo=p_id_veiculo,status='aguardando_coleta'
 WHERE id_entrega=p_id_entrega;
END; $$;
REVOKE ALL ON FUNCTION public.moove_assumir_entrega(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_assumir_entrega(bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.moove_status_entrega(p_id_entrega bigint,p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_driver bigint; v_atual public.status_entrega;
BEGIN
 IF NOT public.moove_conta_autorizada() THEN RAISE EXCEPTION 'Conta não autorizada.'; END IF;
 SELECT id_entregador INTO v_driver FROM public.entregadores WHERE perfil_id=auth.uid();
 SELECT status INTO v_atual FROM public.entregas WHERE id_entrega=p_id_entrega AND id_entregador=v_driver FOR UPDATE;
 IF v_atual IS NULL THEN RAISE EXCEPTION 'Entrega não encontrada.'; END IF;
 IF p_status IS NULL OR NOT ((v_atual='aguardando_coleta' AND p_status='coletada') OR
 (v_atual='coletada' AND p_status='em_transito') OR
 (v_atual='em_transito' AND p_status='saiu_para_entrega')) THEN
 RAISE EXCEPTION 'Transição de status não permitida.'; END IF;
 UPDATE public.entregas SET status=p_status::public.status_entrega WHERE id_entrega=p_id_entrega;
END; $$;
REVOKE ALL ON FUNCTION public.moove_status_entrega(bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_status_entrega(bigint,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.moove_comprovar_entrega(p_id_entrega bigint,p_cliente boolean,p_nome text,p_relacao text,p_documento_final4 text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_driver bigint; v_status public.status_entrega;
BEGIN
 IF NOT public.moove_conta_autorizada() THEN RAISE EXCEPTION 'Conta não autorizada.'; END IF;
 SELECT id_entregador INTO v_driver FROM public.entregadores WHERE perfil_id=auth.uid();
 SELECT status INTO v_status FROM public.entregas WHERE id_entrega=p_id_entrega AND id_entregador=v_driver FOR UPDATE;
 IF v_status IS DISTINCT FROM 'saiu_para_entrega' THEN RAISE EXCEPTION 'Entrega não está pronta para comprovação.'; END IF;
 IF NOT coalesce(p_cliente,false) AND length(btrim(coalesce(p_nome,''))) < 3 THEN RAISE EXCEPTION 'Informe o nome de quem recebeu.'; END IF;
 IF nullif(btrim(coalesce(p_documento_final4,'')),'') IS NOT NULL AND p_documento_final4 !~ '^[0-9]{4}$'
 THEN RAISE EXCEPTION 'Informe somente os 4 últimos dígitos do documento.'; END IF;
 INSERT INTO public.comprovantes_entrega(id_entrega,recebido_pelo_cliente,nome_recebedor,relacao_com_destinatario,documento_final4,recebido_em)
 VALUES(p_id_entrega,coalesce(p_cliente,false),CASE WHEN p_cliente THEN '' ELSE btrim(p_nome) END,
 nullif(btrim(coalesce(p_relacao,'')),''),nullif(btrim(coalesce(p_documento_final4,'')),''),now());
 -- Compatível com o trigger existente; garante conclusão caso ele esteja ausente.
 UPDATE public.entregas SET status='entregue',data_hora_entrega=coalesce(data_hora_entrega,now())
 WHERE id_entrega=p_id_entrega AND status='saiu_para_entrega';
END; $$;
REVOKE ALL ON FUNCTION public.moove_comprovar_entrega(bigint,boolean,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_comprovar_entrega(bigint,boolean,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.moove_cancelar_entrega(p_id_entrega bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_status public.status_entrega;
BEGIN
 IF NOT public.moove_conta_autorizada() THEN RAISE EXCEPTION 'Conta não autorizada.'; END IF;
 SELECT e.status INTO v_status FROM public.entregas e
 JOIN public.clientes c ON c.id_cliente=e.id_cliente
 WHERE e.id_entrega=p_id_entrega AND c.perfil_id=auth.uid() FOR UPDATE OF e;
 IF v_status NOT IN ('solicitada','aguardando_entregador','aguardando_coleta') OR v_status IS NULL THEN
 RAISE EXCEPTION 'Não é possível cancelar esta entrega.'; END IF;
 UPDATE public.entregas SET status='cancelada' WHERE id_entrega=p_id_entrega;
 UPDATE public.pagamentos SET status_pagamento='cancelado' WHERE id_entrega=p_id_entrega AND status_pagamento='pendente';
END; $$;
REVOKE ALL ON FUNCTION public.moove_cancelar_entrega(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_cancelar_entrega(bigint) TO authenticated;

-- Registra intenção de pagamento, NÃO processa cartão/Pix e NÃO confirma pagamento automaticamente.
CREATE OR REPLACE FUNCTION public.moove_pagamento_pendente(p_id_entrega bigint,p_metodo text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_valor numeric; v_id bigint;
BEGIN
 IF NOT public.moove_conta_autorizada() THEN RAISE EXCEPTION 'Conta não autorizada.'; END IF;
 IF p_metodo IS NULL OR p_metodo NOT IN ('pix','cartao','dinheiro') THEN RAISE EXCEPTION 'Forma de pagamento inválida.'; END IF;
 SELECT e.valor_frete INTO v_valor FROM public.entregas e
 JOIN public.clientes c ON c.id_cliente=e.id_cliente
 WHERE e.id_entrega=p_id_entrega AND c.perfil_id=auth.uid() AND e.status<>'cancelada' FOR UPDATE OF e;
 IF v_valor IS NULL OR v_valor <= 0 THEN RAISE EXCEPTION 'Entrega não disponível para pagamento.'; END IF;
 IF EXISTS(SELECT 1 FROM public.pagamentos WHERE id_entrega=p_id_entrega AND status_pagamento IN ('pendente','pago'))
 THEN RAISE EXCEPTION 'Já existe pagamento pendente ou pago.'; END IF;
 INSERT INTO public.pagamentos(id_entrega,metodo,valor,status_pagamento)
 VALUES(p_id_entrega,p_metodo::public.metodo_pagamento,v_valor,'pendente') RETURNING id_pagamento INTO v_id;
 RETURN v_id;
END; $$;
REVOKE ALL ON FUNCTION public.moove_pagamento_pendente(bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_pagamento_pendente(bigint,text) TO authenticated;

-- Somente gestores explicitamente autorizados podem aprovar operações.
CREATE OR REPLACE FUNCTION public.moove_aprovar_cadastro(p_tipo text,p_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.moove_eh_gestor() THEN RAISE EXCEPTION 'Acesso administrativo negado.'; END IF;
 IF p_tipo='vendedor' THEN
  IF NOT EXISTS(SELECT 1 FROM public.vendedores v JOIN public.perfil_enderecos pe ON pe.perfil_id=v.perfil_id
    WHERE v.id_vendedor=p_id AND pe.ativo AND pe.tipo IN ('comercial','coleta'))
  THEN RAISE EXCEPTION 'Vendedor precisa cadastrar endereço de coleta.'; END IF;
  INSERT INTO public.moove_vendedores_aprovados(id_vendedor) VALUES(p_id) ON CONFLICT DO NOTHING;
 ELSIF p_tipo='entregador' THEN
  IF NOT EXISTS(SELECT 1 FROM public.documentos_entregadores WHERE id_entregador=p_id AND validade_cnh > current_date)
  OR NOT EXISTS(SELECT 1 FROM public.veiculos WHERE id_entregador=p_id AND ativo)
  THEN RAISE EXCEPTION 'Entregador precisa cadastrar CNH válida e veículo.'; END IF;
  INSERT INTO public.moove_entregadores_aprovados(id_entregador) VALUES(p_id) ON CONFLICT DO NOTHING;
 ELSE RAISE EXCEPTION 'Tipo de cadastro inválido.';
 END IF;
END; $$;
REVOKE ALL ON FUNCTION public.moove_aprovar_cadastro(text,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_aprovar_cadastro(text,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.moove_confirmar_pagamento(p_id_pagamento bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF NOT public.moove_eh_gestor() THEN RAISE EXCEPTION 'Acesso administrativo negado.'; END IF;
 -- Só confirme após verificar recebimento FORA do Moove (gateway, extrato ou dinheiro).
 UPDATE public.pagamentos SET status_pagamento='pago' WHERE id_pagamento=p_id_pagamento AND status_pagamento='pendente';
 IF NOT FOUND THEN RAISE EXCEPTION 'Pagamento pendente não encontrado.'; END IF;
END; $$;
REVOKE ALL ON FUNCTION public.moove_confirmar_pagamento(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_confirmar_pagamento(bigint) TO authenticated;

-- Painel único por função: JSON filtrado por proprietário, vendedor, entregador ou gestor autorizado.
CREATE OR REPLACE FUNCTION public.moove_painel_operacional()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_seller bigint; v_driver bigint; v_staff boolean; v_result jsonb;
BEGIN
 IF NOT public.moove_conta_autorizada() THEN RAISE EXCEPTION 'Conta não autorizada.'; END IF;
 SELECT id_vendedor INTO v_seller FROM public.vendedores WHERE perfil_id=auth.uid();
 SELECT id_entregador INTO v_driver FROM public.entregadores WHERE perfil_id=auth.uid();
 v_staff := public.moove_eh_gestor();
 SELECT jsonb_build_object(
 'roles',jsonb_build_object('vendedor',v_seller IS NOT NULL,'entregador',v_driver IS NOT NULL,'gestor',v_staff,
  'vendedor_aprovado',EXISTS(SELECT 1 FROM public.moove_vendedores_aprovados WHERE id_vendedor=v_seller),
  'entregador_aprovado',EXISTS(SELECT 1 FROM public.moove_entregadores_aprovados WHERE id_entregador=v_driver),
  'disponivel',coalesce((SELECT disponivel FROM public.entregadores WHERE id_entregador=v_driver),false)),
 'seller_id',v_seller,'driver_id',v_driver,
 'vehicles',coalesce((SELECT jsonb_agg(to_jsonb(v) ORDER BY v.id_veiculo DESC)
  FROM public.veiculos v WHERE v.id_entregador=v_driver),'[]'::jsonb),
 'seller_deliveries',coalesce((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.data_solicitacao DESC)
  FROM (SELECT id_entrega,codigo_rastreio,status,descricao_carga,valor_frete,data_solicitacao,id_entregador
        FROM public.entregas WHERE id_vendedor=v_seller ORDER BY data_solicitacao DESC LIMIT 100) e),'[]'::jsonb),
 'driver_deliveries',coalesce((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.data_solicitacao DESC)
  FROM (SELECT id_entrega,codigo_rastreio,status,descricao_carga,valor_frete,data_solicitacao,id_veiculo
        FROM public.entregas WHERE id_entregador=v_driver ORDER BY data_solicitacao DESC LIMIT 100) e),'[]'::jsonb),
 'available_deliveries',coalesce((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.data_solicitacao)
  FROM (SELECT id_entrega,codigo_rastreio,status,valor_frete,descricao_carga,peso_kg,data_solicitacao
        FROM public.entregas WHERE id_entregador IS NULL AND status IN ('solicitada','aguardando_entregador')
        AND EXISTS(SELECT 1 FROM public.moove_entregadores_aprovados a
          JOIN public.entregadores d ON d.id_entregador=a.id_entregador AND d.disponivel
          JOIN public.documentos_entregadores doc ON doc.id_entregador=d.id_entregador AND doc.validade_cnh > current_date
          WHERE a.id_entregador=v_driver)
        AND EXISTS(SELECT 1 FROM public.veiculos v WHERE v.id_entregador=v_driver AND v.ativo AND v.capacidade_kg >= public.entregas.peso_kg)
        ORDER BY data_solicitacao ASC LIMIT 40) e),'[]'::jsonb),
 'my_payments',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.criado_em DESC)
  FROM (SELECT p.id_pagamento,p.id_entrega,p.valor,p.metodo,p.status_pagamento,p.criado_em
        FROM public.pagamentos p JOIN public.entregas e ON e.id_entrega=p.id_entrega
        JOIN public.clientes c ON c.id_cliente=e.id_cliente WHERE c.perfil_id=auth.uid()
        ORDER BY p.criado_em DESC LIMIT 100) p),'[]'::jsonb),
 'admin_deliveries',CASE WHEN v_staff THEN coalesce((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.data_solicitacao DESC)
  FROM (SELECT id_entrega,codigo_rastreio,status,descricao_carga,valor_frete,data_solicitacao,id_entregador
        FROM public.entregas ORDER BY data_solicitacao DESC LIMIT 100) e),'[]'::jsonb) ELSE '[]'::jsonb END,
 'admin_sellers',CASE WHEN v_staff THEN coalesce((SELECT jsonb_agg(jsonb_build_object('id',v.id_vendedor,'nome',v.nome_estabelecimento,
   'aprovado',a.id_vendedor IS NOT NULL) ORDER BY v.id_vendedor DESC)
   FROM public.vendedores v LEFT JOIN public.moove_vendedores_aprovados a ON a.id_vendedor=v.id_vendedor),'[]'::jsonb) ELSE '[]'::jsonb END,
 'admin_drivers',CASE WHEN v_staff THEN coalesce((SELECT jsonb_agg(jsonb_build_object('id',d.id_entregador,'nome',p.nome,
   'aprovado',a.id_entregador IS NOT NULL) ORDER BY d.id_entregador DESC)
   FROM public.entregadores d JOIN public.perfis p ON p.id=d.perfil_id
   LEFT JOIN public.moove_entregadores_aprovados a ON a.id_entregador=d.id_entregador),'[]'::jsonb) ELSE '[]'::jsonb END,
 'admin_payments',CASE WHEN v_staff THEN coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.criado_em DESC)
   FROM (SELECT id_pagamento,id_entrega,valor,metodo,status_pagamento,criado_em
         FROM public.pagamentos ORDER BY criado_em DESC LIMIT 100) p),'[]'::jsonb) ELSE '[]'::jsonb END
 ) INTO v_result;
 RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.moove_painel_operacional() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_painel_operacional() TO authenticated;

-- Configure o PRIMEIRO gestor manualmente, SOMENTE após conferir que é conta de funcionário legítimo:
-- INSERT INTO public.moove_funcionarios_autorizados(perfil_id)
-- VALUES ('UUID-DO-FUNCIONARIO-REAL');
-- IMPORTANTE: a tabela funcionarios já deve ter um registro com esse perfil_id.

-- Solicita atualização do cache de funções da API REST do Supabase.
NOTIFY pgrst, 'reload schema';


-- EXECUTAR após 03_operacoes_completas.sql. Requer que as operações de escrita
-- passem pelas funções moove_* (SECURITY DEFINER, com verificações de autorização).
-- Políticas RESTRICTIVE usam AND com todas as permissivas existentes, bloqueando
-- escrita REST direta, inclusive se uma política antiga permitir.
-- IMPORTANTE: confirme que suas outras aplicações não dependem de escrita direta.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='entregas' AND policyname='moove_entregas_insert_rpc') THEN
  CREATE POLICY moove_entregas_insert_rpc ON public.entregas AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='entregas' AND policyname='moove_entregas_update_rpc') THEN
  CREATE POLICY moove_entregas_update_rpc ON public.entregas AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='entregas' AND policyname='moove_entregas_delete_rpc') THEN
  CREATE POLICY moove_entregas_delete_rpc ON public.entregas AS RESTRICTIVE FOR DELETE TO authenticated USING (false);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='pagamentos' AND policyname='moove_pagamentos_insert_rpc') THEN
  CREATE POLICY moove_pagamentos_insert_rpc ON public.pagamentos AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='pagamentos' AND policyname='moove_pagamentos_update_rpc') THEN
  CREATE POLICY moove_pagamentos_update_rpc ON public.pagamentos AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='pagamentos' AND policyname='moove_pagamentos_delete_rpc') THEN
  CREATE POLICY moove_pagamentos_delete_rpc ON public.pagamentos AS RESTRICTIVE FOR DELETE TO authenticated USING (false);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='comprovantes_entrega' AND policyname='moove_comprovantes_insert_rpc') THEN
  CREATE POLICY moove_comprovantes_insert_rpc ON public.comprovantes_entrega AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (false);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='comprovantes_entrega' AND policyname='moove_comprovantes_update_rpc') THEN
  CREATE POLICY moove_comprovantes_update_rpc ON public.comprovantes_entrega AS RESTRICTIVE FOR UPDATE TO authenticated USING (false) WITH CHECK (false);
 END IF;
END $$;

-- RLS deve estar ativo para que políticas restritivas tenham efeito.
-- Cadastros e endereços também passam exclusivamente pelas RPCs autorizadas.
DO $$
DECLARE v_tabela text; v_operacao text; v_politica text;
BEGIN
 FOREACH v_tabela IN ARRAY ARRAY['entregas','pagamentos','comprovantes_entrega','vendedores','entregadores','documentos_entregadores','veiculos','enderecos','perfil_enderecos'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',v_tabela);
  FOREACH v_operacao IN ARRAY ARRAY['INSERT','UPDATE','DELETE'] LOOP
   v_politica := 'moove_rpc_only_' || lower(v_operacao);
   IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename=v_tabela AND policyname=v_politica) THEN
    IF v_operacao='INSERT' THEN
     EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (false)',v_politica,v_tabela);
    ELSIF v_operacao='UPDATE' THEN
     EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (false) WITH CHECK (false)',v_politica,v_tabela);
    ELSE
     EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (false)',v_politica,v_tabela);
    END IF;
   END IF;
  END LOOP;
 END LOOP;
END $$;


-- Aplicar após 01 e 03. Mantém os dados filtrados pelo usuário autenticado.
CREATE OR REPLACE FUNCTION public.moove_dados_cliente()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_uid uuid := auth.uid(); v_result jsonb;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Conta não autorizada.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=v_uid AND email_confirmed_at IS NOT NULL)
 THEN RAISE EXCEPTION 'Confirme seu e-mail para continuar.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.perfis WHERE id=v_uid)
 THEN RAISE EXCEPTION 'Seu perfil não foi criado no banco. Verifique o trigger de cadastro no Supabase.'; END IF;
 IF NOT public.moove_conta_autorizada() THEN RAISE EXCEPTION 'Sua conta não está ativa. Procure o responsável pelo sistema.'; END IF;
 SELECT jsonb_build_object(
  'nome',p.nome,'status',p.status,
  'cliente_cadastrado',EXISTS(SELECT 1 FROM public.clientes WHERE perfil_id=v_uid),
  'addresses',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.criado_em DESC)
    FROM (SELECT pe.id_perfil_endereco,pe.id_endereco,pe.tipo,pe.nome_endereco,pe.principal,pe.ativo,pe.criado_em,
      jsonb_build_object('id_endereco',e.id_endereco,'cep',e.cep,'logradouro',e.logradouro,'numero',e.numero,
       'complemento',e.complemento,'bairro',e.bairro,'cidade',e.cidade,'estado',e.estado) AS enderecos
      FROM public.perfil_enderecos pe JOIN public.enderecos e ON e.id_endereco=pe.id_endereco
      WHERE pe.perfil_id=v_uid AND pe.ativo) a),'[]'::jsonb),
  'deliveries',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.data_solicitacao DESC)
    FROM (SELECT e.id_entrega,e.codigo_rastreio,e.status,e.descricao_carga,e.valor_frete,e.data_solicitacao,e.data_hora_entrega
      FROM public.entregas e JOIN public.clientes c ON c.id_cliente=e.id_cliente
      WHERE c.perfil_id=v_uid ORDER BY e.data_solicitacao DESC LIMIT 100) d),'[]'::jsonb)
 ) INTO v_result FROM public.perfis p WHERE p.id=v_uid;
 RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.moove_dados_cliente() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.moove_dados_cliente() TO authenticated;
NOTIFY pgrst, 'reload schema';


COMMIT;
