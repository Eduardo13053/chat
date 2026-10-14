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
