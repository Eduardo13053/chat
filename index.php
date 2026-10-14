<?php
require __DIR__ . '/bootstrap.php';
header('X-Content-Type-Options: nosniff');
header('Cache-Control: no-store');
header('Referrer-Policy: strict-origin-when-cross-origin');
?>
<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="theme-color" content="#0957cd">
  <meta name="csrf-token" content="<?= htmlspecialchars(csrf_token(), ENT_QUOTES, 'UTF-8') ?>">
  <title>Moove | Entregas que conectam</title>
  <link rel="stylesheet" href="/assets/style.css">
  <script src="/assets/app.js" defer></script>
</head>
<body>
<header class="topbar">
  <a href="#inicio" class="brand" aria-label="Moove início"><span class="brand-mark">M<span class="spark">•</span></span><span>moove<span class="brand-dot">.</span></span></a>
  <nav class="topnav" aria-label="Navegação principal">
    <a href="#como-funciona" class="public-link">Como funciona</a>
    <a href="#vantagens" class="public-link">Vantagens</a>
    <span id="user-greeting" class="user-greeting" hidden></span>
    <button class="btn btn-outline" id="open-login" type="button">Entrar</button>
    <button class="btn btn-yellow" id="open-register" type="button">Criar conta</button>
    <button class="btn btn-outline" id="logout" type="button" hidden>Sair</button>
  </nav>
</header>
<main>
  <section id="landing">
    <div class="hero" id="inicio">
      <div class="hero-content">
        <span class="eyebrow"><span class="eyebrow-dot"></span> A logística do seu dia a dia</span>
        <h1>Suas entregas em <span>movimento.</span></h1>
        <p>Solicite transportes, acompanhe seus pedidos e organize seus endereços em um só lugar. Simples, rápido e conectado.</p>
        <div class="hero-actions"><button type="button" class="btn btn-primary btn-large" id="hero-cta">Começar agora <span aria-hidden="true">→</span></button><a href="#como-funciona" class="btn btn-quiet">Saiba mais</a></div>
        <div class="hero-points"><span>✓ Cadastro seguro</span><span>✓ Acompanhamento de pedidos</span></div>
      </div>
      <div class="hero-art" aria-hidden="true">
        <div class="orb orb-one"></div><div class="orb orb-two"></div>
        <div class="illustration-card card-route"><span class="route-icon">↗</span><div><strong>Rota conectada</strong><small>Da coleta até você</small></div><span class="check-round">✓</span></div>
        <div class="illustration-card card-box"><div class="package-icon">▣</div><div><strong>Seu pedido está a caminho!</strong><small>Acompanhe cada etapa</small></div></div>
        <div class="road"><span class="road-line"></span><div class="truck"><span class="truck-box">M</span><span class="truck-cabin"></span><span class="wheel wheel-a"></span><span class="wheel wheel-b"></span></div></div>
        <div class="art-tag">#BoraDeMoove <span>✦</span></div>
      </div>
    </div>
    <section class="how" id="como-funciona"><div class="section-heading"><span class="eyebrow">É fácil começar</span><h2>Como a Moove funciona?</h2><p>Você cuida do que importa. A Moove organiza sua solicitação.</p></div><div class="steps"><article class="step"><span class="step-icon">01</span><h3>Crie sua conta</h3><p>Cadastre-se e confirme seu e-mail para começar com segurança.</p></article><article class="step"><span class="step-icon">02</span><h3>Escolha a coleta</h3><p>Selecione um estabelecimento parceiro e seu endereço de destino.</p></article><article class="step"><span class="step-icon">03</span><h3>Acompanhe tudo</h3><p>Veja o código de rastreio e as atualizações da entrega.</p></article></div></section>
    <section class="benefits" id="vantagens"><div><span class="eyebrow">Por que escolher a Moove?</span><h2>Menos complicação.<br>Mais movimento.</h2><p>Um espaço pensado para facilitar sua rotina de entregas.</p></div><div class="benefit-list"><div><span>⚡</span><strong>Solicitação prática</strong><small>Seus pedidos organizados em poucos passos.</small></div><div><span>⌖</span><strong>Endereços salvos</strong><small>Cadastre diferentes destinos para reutilizar.</small></div><div><span>▤</span><strong>Histórico acessível</strong><small>Acompanhe o andamento dos seus pedidos.</small></div></div></section>
  </section>
  <section id="dashboard" class="dashboard" hidden>
    <div class="dash-head"><div><span class="eyebrow">PAINEL DO CLIENTE</span><h1>Olá, <span id="dash-name">cliente</span> 👋</h1><p>Gerencie seus endereços e entregas em um só lugar.</p></div><span class="status-pill">● Conta conectada</span></div>
    <div class="dash-tabs" role="tablist" aria-label="Seções do painel">
      <button class="tab active" type="button" data-tab="overview">Visão geral</button>
      <button class="tab" type="button" data-tab="addresses">Meus endereços</button>
      <button class="tab" type="button" data-tab="new-delivery">Solicitar entrega</button>
      <button class="tab" type="button" data-tab="deliveries">Minhas entregas</button>
      <button class="tab" type="button" data-tab="payments">Pagamentos</button>
      <button class="tab" type="button" data-tab="seller">Vendedor</button>
      <button class="tab" type="button" data-tab="driver">Entregador</button>
      <button class="tab" type="button" data-tab="admin" id="admin-tab" hidden>Gestão</button>
    </div>
    <section class="dash-panel" data-panel="overview">
      <div class="stat-grid"><article class="stat"><span>Entregas cadastradas</span><strong id="stat-total">0</strong><small>Solicitações na plataforma</small></article><article class="stat"><span>Em andamento</span><strong id="stat-active">0</strong><small>Pedidos ainda não finalizados</small></article><article class="stat"><span>Endereços salvos</span><strong id="stat-addresses">0</strong><small>Destinos disponíveis</small></article></div>
      <div class="section-card"><div class="card-heading"><div><h2>Entregas recentes</h2><p>Acompanhe seus pedidos mais recentes.</p></div><button type="button" class="btn btn-outline btn-small" data-goto="deliveries">Ver todas</button></div><div id="recent-deliveries"></div></div>
    </section>
    <section class="dash-panel" data-panel="addresses" hidden>
      <div class="two-col"><div class="section-card"><h2>Adicionar endereço</h2><p class="muted">Você pode cadastrar vários endereços.</p><form id="address-form" class="form-grid">
        <label>Nome do endereço<input name="nome_endereco" placeholder="Ex.: Minha casa" maxlength="100"></label>
        <label>Tipo<select name="tipo"><option value="residencial">Residencial</option><option value="comercial">Comercial</option><option value="coleta">Coleta</option><option value="entrega">Entrega</option><option value="outro">Outro</option></select></label>
        <label>CEP<input name="cep" placeholder="00000-000" inputmode="numeric" maxlength="9" required></label>
        <label>Estado (UF)<input name="estado" placeholder="RJ" maxlength="2" required></label>
        <label class="full">Logradouro<input name="logradouro" placeholder="Rua, avenida..." maxlength="200" required></label>
        <label>Número<input name="numero" maxlength="20" required></label>
        <label>Complemento<input name="complemento" placeholder="Apto, bloco..." maxlength="100"></label>
        <label>Bairro<input name="bairro" maxlength="100" required></label>
        <label>Cidade<input name="cidade" maxlength="100" required></label>
        <button type="submit" class="btn btn-primary full">Salvar endereço</button>
      </form></div><div class="section-card"><h2>Endereços cadastrados</h2><p class="muted">Locais vinculados à sua conta.</p><div id="address-list" class="stack"></div></div></div>
    </section>
    <section class="dash-panel" data-panel="new-delivery" hidden><div class="section-card delivery-card"><div class="card-heading"><div><h2>Nova solicitação</h2><p>Selecione o ponto de coleta e onde deseja receber.</p></div><span class="demo-price">Frete demonstrativo: R$ 25,00</span></div><form id="delivery-form" class="form-grid">
      <label class="full">Estabelecimento e ponto de coleta<select name="pickup" id="pickup-select" required><option value="">Carregando...</option></select></label>
      <label class="full">Endereço de destino<select name="id_endereco_destino" id="destination-select" required><option value="">Selecione um endereço</option></select></label>
      <label class="full">Descrição da carga<input name="descricao_carga" placeholder="Ex.: Caixa de livros" maxlength="255" required></label>
      <label>Peso aproximado (kg)<input name="peso_kg" type="number" min="0.01" max="1000" step="0.01" placeholder="2.5" required></label>
      <div class="notice full">ℹ️ O valor de R$ 25,00 é apenas para demonstração do TCC. Esta versão não realiza pagamentos reais.</div>
      <button type="submit" class="btn btn-primary full">Solicitar entrega →</button>
    </form></div></section>
    <section class="dash-panel" data-panel="deliveries" hidden><div class="section-card"><div class="card-heading"><div><h2>Minhas entregas</h2><p>Consulte o andamento e o histórico de cada pedido.</p></div><button type="button" class="btn btn-outline btn-small" id="refresh-data">Atualizar</button></div><div id="delivery-list"></div></div></section>
    <section class="dash-panel" data-panel="payments" hidden>
      <div class="two-col"><div class="section-card"><h2>Registrar intenção de pagamento</h2>
        <p class="muted">Demonstração acadêmica: nenhuma cobrança ou Pix real é realizado. O gestor confere o recebimento fora do site.</p>
        <form id="payment-form" class="form-grid">
          <label class="full">Entrega<select name="id_entrega" id="payment-delivery-select" required></select></label>
          <label class="full">Forma de pagamento<select name="metodo" required><option value="pix">Pix</option><option value="cartao">Cartão</option><option value="dinheiro">Dinheiro</option></select></label>
          <button class="btn btn-primary full" type="submit">Registrar como pendente</button>
        </form></div><div class="section-card"><h2>Histórico de pagamentos</h2><div class="stack" id="payment-list"></div></div></div>
    </section>
    <section class="dash-panel" data-panel="seller" hidden>
      <div class="two-col"><div class="section-card"><h2>Minha loja / vendedor</h2><p class="muted">Cadastre seu estabelecimento. Para aparecer nas solicitações, adicione um endereço comercial ou de coleta em “Meus endereços” e aguarde aprovação do gestor.</p>
      <div id="seller-status" class="notice"></div>
      <form id="seller-form" class="form-grid">
        <label class="full">Nome do estabelecimento<input name="nome_estabelecimento" maxlength="150" required placeholder="Ex.: Loja Moove Centro"></label>
        <label class="full">CNPJ (opcional)<input name="cnpj" inputmode="numeric" maxlength="18" placeholder="Somente se tiver CNPJ"></label>
        <button class="btn btn-primary full" type="submit">Cadastrar / atualizar loja</button>
      </form></div><div class="section-card"><h2>Pedidos recebidos</h2><div class="stack" id="seller-deliveries"></div></div></div>
    </section>
    <section class="dash-panel" data-panel="driver" hidden>
      <div class="section-card"><div class="card-heading"><div><h2>Painel do entregador</h2><p>Cadastre-se, informe sua CNH, adicione veículo e aguarde aprovação antes de aceitar entregas.</p></div><button class="btn btn-yellow" id="driver-register" type="button">Quero ser entregador</button></div><div id="driver-status" class="notice"></div></div>
      <div class="two-col extra-top"><div class="section-card"><h2>Documentação</h2>
        <form id="driver-document-form" class="form-grid"><label class="full">Número da CNH<input name="numero_cnh" maxlength="11" inputmode="numeric" required></label><label class="full">Validade da CNH<input type="date" name="validade_cnh" required></label><button class="btn btn-primary full" type="submit">Salvar CNH</button></form>
        <p class="muted">Ao alterar a CNH, uma nova aprovação é necessária.</p>
      </div><div class="section-card"><h2>Cadastrar veículo</h2>
        <form id="vehicle-form" class="form-grid"><label>Tipo<input name="tipo" required placeholder="Moto, carro, van"></label><label>Marca<input name="marca" required></label><label>Modelo<input name="modelo" required></label><label>Placa<input name="placa" maxlength="8" required placeholder="ABC1D23"></label><label class="full">Capacidade (kg)<input type="number" name="capacidade_kg" min="1" step="0.1" required></label><button class="btn btn-primary full" type="submit">Adicionar veículo</button></form>
      </div></div>
      <div class="two-col extra-top"><div class="section-card"><div class="card-heading"><h2>Veículos e disponibilidade</h2><button class="btn btn-outline btn-small" type="button" id="driver-availability">Alternar disponibilidade</button></div><div id="vehicle-list" class="stack"></div></div>
      <div class="section-card"><h2>Entregas disponíveis</h2><div class="stack" id="available-deliveries"></div></div></div>
      <div class="section-card extra-top"><h2>Minhas entregas como motorista</h2><div class="stack" id="driver-deliveries"></div></div>
    </section>
    <section class="dash-panel" data-panel="admin" hidden>
      <div class="section-card"><h2>Gestão de cadastros e pagamentos</h2><p class="muted">Somente funcionários explicitamente autorizados pelo administrador do banco têm acesso a estas operações.</p></div>
      <div class="two-col extra-top"><div class="section-card"><h2>Vendedores aguardando aprovação</h2><div class="stack" id="admin-sellers"></div></div><div class="section-card"><h2>Entregadores aguardando aprovação</h2><div class="stack" id="admin-drivers"></div></div></div>
      <div class="two-col extra-top"><div class="section-card"><h2>Pagamentos (conferência externa)</h2><div class="stack" id="admin-payments"></div></div><div class="section-card"><h2>Entregas da plataforma</h2><div class="stack" id="admin-deliveries"></div></div></div>
    </section>
  </section>
</main>
<footer class="footer"><div class="brand brand-footer"><span class="brand-mark">M<span class="spark">•</span></span><span>moove<span class="brand-dot">.</span></span></div><span>Seu mundo em movimento.</span><small>© <?= date('Y') ?> Moove · Projeto acadêmico de logística</small></footer>
<div id="auth-modal" class="modal-backdrop" hidden><div class="modal" role="dialog" aria-modal="true" aria-labelledby="auth-title"><button class="modal-close" id="close-modal" type="button" aria-label="Fechar">×</button><div class="brand"><span class="brand-mark">M<span class="spark">•</span></span><span>moove<span class="brand-dot">.</span></span></div><h2 id="auth-title">Bem-vindo de volta</h2><p id="auth-subtitle" class="muted">Entre para acompanhar suas entregas.</p><form id="auth-form" class="form-grid"><label class="full" id="name-field" hidden>Nome completo<input name="nome" placeholder="Seu nome completo" autocomplete="name"></label><label class="full">E-mail<input type="email" name="email" placeholder="voce@email.com" autocomplete="email" required></label><label class="full">Senha<input type="password" name="senha" minlength="8" placeholder="Mínimo 8 caracteres" autocomplete="current-password" required></label><button type="submit" id="auth-submit" class="btn btn-primary full">Entrar</button></form><p class="auth-toggle" id="auth-toggle">Ainda não tem conta? <button type="button" id="switch-auth">Cadastre-se</button></p><button type="button" class="resend-link" id="resend-email">Reenviar confirmação de e-mail</button>
<button type="button" class="resend-link" id="forgot-password">Esqueci minha senha</button></div></div>
<div id="history-modal" class="modal-backdrop" hidden><div class="modal history-modal" role="dialog" aria-modal="true" aria-labelledby="history-title"><button class="modal-close" id="close-history" type="button" aria-label="Fechar">×</button><h2 id="history-title">Acompanhamento</h2><p class="muted" id="history-subtitle"></p><div id="history-content" class="timeline"></div></div></div>
<div id="proof-modal" class="modal-backdrop" hidden><div class="modal" role="dialog" aria-modal="true" aria-labelledby="proof-title"><button class="modal-close" id="close-proof" type="button">×</button><h2 id="proof-title">Comprovante de entrega</h2><p class="muted">Confirme quem recebeu a encomenda.</p>
<form id="proof-form" class="form-grid"><input type="hidden" name="id_entrega"><label class="full checkline"><input type="checkbox" name="recebido_pelo_cliente" value="1"> Recebido pelo próprio cliente</label><label class="full">Nome de quem recebeu<input name="nome_recebedor" maxlength="150" placeholder="Preencha se foi outra pessoa"></label><label>Relação com destinatário<input name="relacao_com_destinatario" placeholder="Ex.: familiar"></label><label>Últimos 4 dígitos do documento (opcional)<input name="documento_final4" maxlength="4" inputmode="numeric"></label><button type="submit" class="btn btn-primary full">Concluir entrega</button></form></div></div>
<div id="reset-modal" class="modal-backdrop" hidden><div class="modal" role="dialog" aria-modal="true" aria-labelledby="reset-title"><h2 id="reset-title">Definir nova senha</h2><form id="reset-form" class="form-grid"><label class="full">Nova senha<input name="senha" type="password" minlength="8" required></label><button class="btn btn-primary full" type="submit">Alterar senha</button></form></div></div>
<div id="toast" class="toast" role="status" aria-live="polite" hidden></div>
</body>
</html>
