<?php
declare(strict_types=1);
require __DIR__ . '/bootstrap.php';
header('X-Content-Type-Options: nosniff');
if ($_SERVER['REQUEST_METHOD'] === 'GET' && ($_GET['action'] ?? '') === 'me') {
    try {
        require_configuration();
        if (!logged_in()) json_response(['logged_in' => false, 'csrf' => csrf_token()]);
        require_auth();
        $client = rpc('moove_dados_cliente', []);
        $warnings = [];
        if (empty($client['cliente_cadastrado'])) $warnings[] = 'Seu cadastro de cliente está ausente. Verifique o trigger de cadastro no Supabase antes de solicitar entregas.';
        $pickups = rpc('moove_pontos_coleta', []);
        try {
            $operations = rpc('moove_painel_operacional', []);
        } catch (MooveException $e) {
            if (in_array($e->httpStatus, [401, 403], true)) throw $e;
            $operations = ['unavailable' => true];
            $warnings[] = 'O painel operacional não pôde ser carregado: ' . $e->getMessage();
        }
        json_response([
            'logged_in' => true, 'csrf' => csrf_token(),
            'user' => ['email' => $_SESSION['user_email'], 'nome' => $client['nome'] ?? '', 'status' => $client['status'] ?? ''],
            'addresses' => $client['addresses'] ?? [], 'deliveries' => $client['deliveries'] ?? [],
            'pickups' => $pickups, 'operations' => $operations, 'warnings' => $warnings,
        ]);
    } catch (Throwable $e) { exception_response($e); }
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') json_response(['error' => 'Método não permitido.'], 405);
$data = json_decode(file_get_contents('php://input'), true);
if (!is_array($data)) json_response(['error' => 'JSON inválido.'], 400);
require_csrf($data);
$action = (string)($data['action'] ?? '');
try {
    if ($action !== 'logout') require_configuration();
    switch ($action) {
        case 'register':
            $name = trim((string)($data['nome'] ?? ''));
            $email = strtolower(trim((string)($data['email'] ?? '')));
            $password = (string)($data['senha'] ?? '');
            if (mb_strlen($name) < 3 || mb_strlen($name) > 150 || !filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($password) < 8) {
                json_response(['error' => 'Informe nome, e-mail válido e senha de pelo menos 8 caracteres.'], 422);
            }
            $result = api_request('POST', 'auth/v1/signup?redirect_to=' . rawurlencode(rtrim($config['app_url'], '/') . '/'), [
                'email' => $email, 'password' => $password,
                'data' => ['nome' => $name, 'tipo' => 'cliente'],
            ]);
            if ($result['status'] >= 300) json_response(['error' => api_error($result, 'Não foi possível criar sua conta.')], 400);
            json_response(['message' => 'Cadastro solicitado! Confira seu e-mail e confirme a conta antes de entrar.']);
        case 'login':
            $email = trim((string)($data['email'] ?? ''));
            $password = (string)($data['senha'] ?? '');
            if (!filter_var($email, FILTER_VALIDATE_EMAIL) || $password === '') json_response(['error' => 'Informe e-mail e senha.'], 422);
            $result = api_request('POST', 'auth/v1/token?grant_type=password', ['email' => $email, 'password' => $password]);
            if ($result['status'] >= 300 || empty($result['data']['access_token'])) json_response(['error' => api_error($result, 'Não foi possível entrar.')], 401);
            save_auth($result['data']);
            json_response(['message' => 'Login realizado.']);
        case 'resend':
            $email = trim((string)($data['email'] ?? ''));
            if (!filter_var($email, FILTER_VALIDATE_EMAIL)) json_response(['error' => 'E-mail inválido.'], 422);
            // Resposta neutra para evitar revelar quais endereços estão cadastrados.
            $result = api_request('POST', 'auth/v1/resend', ['type' => 'signup', 'email' => $email, 'options' => ['emailRedirectTo' => rtrim($config['app_url'], '/') . '/']]);
            if ($result['status'] >= 300) upstream_exception($result, 'Não foi possível enviar a confirmação. Verifique a configuração de e-mail do Supabase.');
            json_response(['message' => 'Se o endereço estiver elegível, você receberá uma mensagem. Verifique também o Spam.']);
        case 'logout':
            if (logged_in()) {
                try { api_request('POST', 'auth/v1/logout', [], true); } catch (Throwable $ignored) {}
            }
            $_SESSION = [];
            session_regenerate_id(true);
            json_response(['message' => 'Você saiu da conta.', 'csrf' => csrf_token()]);
        case 'address_add':
            require_auth();
            $type = (string)($data['tipo'] ?? 'residencial');
            if (!in_array($type, ['residencial', 'comercial', 'coleta', 'entrega', 'outro'], true)) json_response(['error' => 'Tipo de endereço inválido.'], 422);
            rpc('moove_salvar_endereco', [
                'p_cep' => (string)($data['cep'] ?? ''),
                'p_logradouro' => trim((string)($data['logradouro'] ?? '')),
                'p_numero' => trim((string)($data['numero'] ?? '')),
                'p_complemento' => trim((string)($data['complemento'] ?? '')),
                'p_bairro' => trim((string)($data['bairro'] ?? '')),
                'p_cidade' => trim((string)($data['cidade'] ?? '')),
                'p_estado' => strtoupper(trim((string)($data['estado'] ?? ''))),
                'p_tipo' => $type,
                'p_nome_endereco' => trim((string)($data['nome_endereco'] ?? '')),
            ]);
            json_response(['message' => 'Endereço cadastrado com sucesso.']);
        case 'delivery_create':
            require_auth();
            $seller = filter_var($data['id_vendedor'] ?? null, FILTER_VALIDATE_INT);
            $origin = filter_var($data['id_endereco_origem'] ?? null, FILTER_VALIDATE_INT);
            $destination = filter_var($data['id_endereco_destino'] ?? null, FILTER_VALIDATE_INT);
            $weight = filter_var($data['peso_kg'] ?? null, FILTER_VALIDATE_FLOAT);
            $description = trim((string)($data['descricao_carga'] ?? ''));
            if (!$seller || !$origin || !$destination || $weight === false || $weight <= 0 || $weight > 1000 || mb_strlen($description) < 3 || mb_strlen($description) > 255) {
                json_response(['error' => 'Preencha vendedor, origem, destino, descrição e peso válido.'], 422);
            }
            $delivery = rpc('moove_criar_entrega', [
                'p_id_vendedor' => $seller, 'p_id_endereco_origem' => $origin,
                'p_id_endereco_destino' => $destination, 'p_descricao_carga' => $description,
                'p_peso_kg' => $weight,
            ]);
            json_response(['message' => 'Entrega solicitada!', 'delivery' => $delivery]);
        case 'seller_register':
            require_auth();
            rpc('moove_cadastrar_vendedor', [
                'p_nome' => trim((string)($data['nome_estabelecimento'] ?? '')),
                'p_cnpj' => trim((string)($data['cnpj'] ?? '')) ?: null,
            ]);
            json_response(['message' => 'Cadastro de vendedor enviado. Aguarde aprovação do gestor.']);
        case 'driver_register':
            require_auth();
            rpc('moove_cadastrar_entregador', []);
            json_response(['message' => 'Cadastro de entregador criado. Cadastre CNH e veículo e aguarde aprovação.']);
        case 'driver_document':
            require_auth();
            rpc('moove_documento_entregador', [
                'p_cnh' => trim((string)($data['numero_cnh'] ?? '')),
                'p_validade' => (string)($data['validade_cnh'] ?? ''),
            ]);
            json_response(['message' => 'CNH cadastrada. É necessária aprovação novamente após alterar documentos.']);
        case 'vehicle_add':
            require_auth();
            rpc('moove_salvar_veiculo', [
                'p_tipo' => trim((string)($data['tipo'] ?? '')),
                'p_marca' => trim((string)($data['marca'] ?? '')),
                'p_modelo' => trim((string)($data['modelo'] ?? '')),
                'p_placa' => strtoupper(trim((string)($data['placa'] ?? ''))),
                'p_capacidade' => filter_var($data['capacidade_kg'] ?? null, FILTER_VALIDATE_FLOAT) ?: 0,
            ]);
            json_response(['message' => 'Veículo cadastrado com sucesso.']);
        case 'availability':
            require_auth();
            rpc('moove_disponibilidade', ['p_disponivel' => filter_var($data['disponivel'] ?? false, FILTER_VALIDATE_BOOLEAN)]);
            json_response(['message' => 'Disponibilidade atualizada.']);
        case 'address_primary':
        case 'address_disable':
            require_auth();
            $id = filter_var($data['id_endereco'] ?? null, FILTER_VALIDATE_INT);
            if (!$id) json_response(['error' => 'Endereço inválido.'], 422);
            rpc($action === 'address_primary' ? 'moove_endereco_principal' : 'moove_endereco_desativar', ['p_id_endereco' => $id]);
            json_response(['message' => 'Endereço atualizado.']);
        case 'driver_claim':
            require_auth();
            $delivery = filter_var($data['id_entrega'] ?? null, FILTER_VALIDATE_INT);
            $vehicle = filter_var($data['id_veiculo'] ?? null, FILTER_VALIDATE_INT);
            if (!$delivery || !$vehicle) json_response(['error' => 'Selecione entrega e veículo.'], 422);
            rpc('moove_assumir_entrega', ['p_id_entrega' => $delivery, 'p_id_veiculo' => $vehicle]);
            json_response(['message' => 'Entrega assumida com sucesso.']);
        case 'driver_status':
            require_auth();
            $id = filter_var($data['id_entrega'] ?? null, FILTER_VALIDATE_INT);
            $status = (string)($data['status'] ?? '');
            if (!$id || !in_array($status, ['coletada','em_transito','saiu_para_entrega'], true))
                json_response(['error' => 'Status inválido.'], 422);
            rpc('moove_status_entrega', ['p_id_entrega' => $id, 'p_status' => $status]);
            json_response(['message' => 'Status atualizado.']);
        case 'delivery_proof':
            require_auth();
            $id = filter_var($data['id_entrega'] ?? null, FILTER_VALIDATE_INT);
            if (!$id) json_response(['error' => 'Entrega inválida.'], 422);
            rpc('moove_comprovar_entrega', [
                'p_id_entrega' => $id,
                'p_cliente' => filter_var($data['recebido_pelo_cliente'] ?? false, FILTER_VALIDATE_BOOLEAN),
                'p_nome' => trim((string)($data['nome_recebedor'] ?? '')),
                'p_relacao' => trim((string)($data['relacao_com_destinatario'] ?? '')),
                'p_documento_final4' => trim((string)($data['documento_final4'] ?? '')),
            ]);
            json_response(['message' => 'Entrega concluída e comprovante registrado.']);
        case 'delivery_cancel':
            require_auth();
            $id = filter_var($data['id_entrega'] ?? null, FILTER_VALIDATE_INT);
            if (!$id) json_response(['error' => 'Entrega inválida.'], 422);
            rpc('moove_cancelar_entrega', ['p_id_entrega' => $id]);
            json_response(['message' => 'Entrega cancelada.']);
        case 'payment_request':
            require_auth();
            $id = filter_var($data['id_entrega'] ?? null, FILTER_VALIDATE_INT);
            $method = (string)($data['metodo'] ?? '');
            if (!$id || !in_array($method, ['pix','cartao','dinheiro'], true))
                json_response(['error' => 'Forma de pagamento inválida.'], 422);
            rpc('moove_pagamento_pendente', ['p_id_entrega' => $id, 'p_metodo' => $method]);
            json_response(['message' => 'Intenção de pagamento registrada como PENDENTE. Nenhuma cobrança foi realizada.']);
        case 'admin_approve':
            require_auth();
            $id = filter_var($data['id'] ?? null, FILTER_VALIDATE_INT);
            $type = (string)($data['tipo'] ?? '');
            if (!$id || !in_array($type, ['vendedor','entregador'], true)) json_response(['error' => 'Dados inválidos.'], 422);
            rpc('moove_aprovar_cadastro', ['p_tipo' => $type, 'p_id' => $id]);
            json_response(['message' => 'Cadastro aprovado.']);
        case 'admin_payment':
            require_auth();
            $id = filter_var($data['id_pagamento'] ?? null, FILTER_VALIDATE_INT);
            if (!$id) json_response(['error' => 'Pagamento inválido.'], 422);
            rpc('moove_confirmar_pagamento', ['p_id_pagamento' => $id]);
            json_response(['message' => 'Pagamento marcado como pago após conferência externa.']);
        case 'password_recover':
            $email = trim((string)($data['email'] ?? ''));
            if (!filter_var($email, FILTER_VALIDATE_EMAIL)) json_response(['error' => 'E-mail inválido.'], 422);
            global $config;
            $redirect = rtrim($config['app_url'], '/') . '/?reset=1';
            $result = api_request('POST', 'auth/v1/recover?redirect_to=' . rawurlencode($redirect), ['email' => $email]);
            if ($result['status'] >= 300) upstream_exception($result, 'Não foi possível enviar a recuperação. Verifique a configuração de e-mail do Supabase.');
            json_response(['message' => 'Se a conta existir e o envio estiver configurado, você receberá instruções.']);
        case 'password_reset_confirm':
            $token = (string)($data['access_token'] ?? '');
            $password = (string)($data['senha'] ?? '');
            if (strlen($password) < 8 || strlen($token) > 4096 || substr_count($token, '.') !== 2)
                json_response(['error' => 'Link inválido ou senha muito curta.'], 422);
            $result = api_request('PUT', 'auth/v1/user', ['password' => $password], false, $token);
            if ($result['status'] >= 300) upstream_exception($result, 'Link expirado ou inválido. Solicite outra recuperação.');
            $_SESSION = [];
            session_regenerate_id(true);
            json_response(['message' => 'Senha alterada. Faça login com a nova senha.', 'csrf' => csrf_token()]);
        case 'tracking':
            require_auth();
            $id = filter_var($data['id_entrega'] ?? null, FILTER_VALIDATE_INT);
            if (!$id) json_response(['error' => 'Entrega inválida.'], 422);
            json_response(['history' => rpc('moove_historico_entrega', ['p_id_entrega' => $id])]);
        default:
            json_response(['error' => 'Ação desconhecida.'], 404);
    }
} catch (Throwable $e) {
    exception_response($e);
}
