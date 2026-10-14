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
