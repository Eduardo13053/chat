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
