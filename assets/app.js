'use strict';
const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const state = { csrf: $('meta[name="csrf-token"]').content, me: null, mode: 'login' };
const statusNames = {
  solicitada: 'Solicitada', aguardando_entregador: 'Aguardando entregador',
  aguardando_coleta: 'Aguardando coleta', coletada: 'Coletada',
  em_transito: 'Em trânsito', saiu_para_entrega: 'Saiu para entrega',
  entregue: 'Entregue', cancelada: 'Cancelada'
};
const esc = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const money = value => Number(value ?? 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const dateBR = value => value ? new Date(value).toLocaleString('pt-BR') : '—';
let toastTimer;
function toast(message, error = false) {
  const el = $('#toast'); el.textContent = message; el.classList.toggle('error', error); el.hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => { el.hidden = true; }, 6500);
}
async function request(action, payload = {}) {
  const response = await fetch('/api.php', {
    method: 'POST', credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, csrf: state.csrf, ...payload })
  });
  let result;
  try { result = await response.json(); } catch { throw Error('Resposta inesperada do servidor.'); }
  if (result.csrf) state.csrf = result.csrf;
  if (!response.ok) throw Error(result.error || 'Não foi possível concluir.');
  return result;
}
async function loadData() {
  const response = await fetch('/api.php?action=me', { credentials: 'same-origin', cache: 'no-store' });
  let data;
  try { data = await response.json(); } catch { throw Error('Resposta inesperada do servidor. Verifique o PHP e sua configuração.'); }
  if (!response.ok) throw Error(data.error || 'Falha ao carregar sua conta.');
  if (data.csrf) state.csrf = data.csrf;
  state.me = data;
  const active = Boolean(data.logged_in);
  $('#landing').hidden = active; $('#dashboard').hidden = !active;
  $('#open-login').hidden = active; $('#open-register').hidden = active;
  $('#logout').hidden = !active; $('#user-greeting').hidden = !active;
  $$('.public-link').forEach(link => link.hidden = active);
  if (active) {
    $('#user-greeting').textContent = data.user.email || '';
    $('#dash-name').textContent = (data.user.nome || 'cliente').trim().split(' ')[0];
    renderDashboard(data);
    renderOperations(data);
    closeAuth();
    if (data.warnings?.length) toast(data.warnings.join(' '), true);
  }
}
function statusTag(status) {
  const color = status === 'entregue' ? 'tag-green' : status === 'cancelada' ? 'tag-yellow' : '';
  return `<span class="tag ${color}">${esc(statusNames[status] || status)}</span>`;
}
function deliveryMarkup(items) {
  if (!items.length) return '<div class="empty">Nenhuma entrega por aqui ainda. Que tal solicitar a primeira?</div>';
  return items.map(d => `<article class="delivery-item"><div><strong>${esc(d.codigo_rastreio || `Entrega #${d.id_entrega}`)}</strong><p>${esc(d.descricao_carga)} · ${money(d.valor_frete)} · ${esc(dateBR(d.data_solicitacao))}</p></div><div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;justify-content:flex-end">${statusTag(d.status)}<button class="btn btn-outline btn-small" type="button" data-track="${Number(d.id_entrega)}" data-code="${esc(d.codigo_rastreio)}">Rastrear</button>${['solicitada','aguardando_entregador','aguardando_coleta'].includes(d.status) ? `<button class="btn btn-outline btn-small" data-cancel="${Number(d.id_entrega)}">Cancelar</button>` : ''}</div></article>`).join('');
}
function renderDashboard(data) {
  const addresses = data.addresses || [];
  const deliveries = data.deliveries || [];
  const pickups = data.pickups || [];
  $('#stat-total').textContent = deliveries.length;
  $('#stat-active').textContent = deliveries.filter(d => !['entregue', 'cancelada'].includes(d.status)).length;
  $('#stat-addresses').textContent = addresses.length;
  $('#recent-deliveries').innerHTML = deliveryMarkup(deliveries.slice(0, 3));
  $('#delivery-list').innerHTML = deliveryMarkup(deliveries);
  $('#address-list').innerHTML = addresses.length ? addresses.map(a => {
    const e = a.enderecos || {};
    return `<div class="address-item"><div><strong>${esc(a.nome_endereco || 'Meu endereço')}</strong> ${a.principal ? '<span class="tag">Principal</span>' : ''}<p>${esc(e.logradouro)}, ${esc(e.numero)}${e.complemento ? ' · ' + esc(e.complemento) : ''}<br>${esc(e.bairro)} · ${esc(e.cidade)}/${esc(e.estado)} · CEP ${esc(e.cep)}</p><div class="mini-actions">${a.principal ? '' : `<button class="btn btn-outline btn-small" data-address-primary="${Number(a.id_endereco)}">Principal</button>`}<button class="btn btn-outline btn-small" data-address-disable="${Number(a.id_endereco)}">Desativar</button></div></div><span class="tag">${esc(a.tipo)}</span></div>`;
  }).join('') : '<div class="empty">Você ainda não cadastrou endereços.</div>';
  $('#destination-select').innerHTML = '<option value="">Selecione um endereço</option>' + addresses.map(a => {
    const e = a.enderecos || {};
    return `<option value="${Number(a.id_endereco)}">${esc(a.nome_endereco || e.logradouro || 'Endereço')} — ${esc(e.cidade || '')}/${esc(e.estado || '')}</option>`;
  }).join('');
  $('#pickup-select').innerHTML = '<option value="">Selecione um ponto de coleta</option>' + pickups.map(p => `<option value="${Number(p.id_vendedor)}|${Number(p.id_endereco_origem)}">${esc(p.nome_estabelecimento)} — ${esc(p.bairro)}, ${esc(p.cidade)}</option>`).join('');
  if (!pickups.length) $('#pickup-select').innerHTML = '<option value="">Nenhum vendedor com endereço comercial/de coleta cadastrado</option>';
}
function openAuth(mode = 'login') {
  state.mode = mode;
  const register = mode === 'register';
  $('#auth-title').textContent = register ? 'Crie sua conta' : 'Bem-vindo de volta';
  $('#auth-subtitle').textContent = register ? 'Comece a movimentar suas entregas.' : 'Entre para acompanhar suas entregas.';
  $('#name-field').hidden = !register;
  $('#name-field input').required = register;
  $('#auth-submit').textContent = register ? 'Criar conta' : 'Entrar';
  $('#auth-toggle').firstChild.textContent = register ? 'Já tem uma conta? ' : 'Ainda não tem conta? ';
  $('#switch-auth').textContent = register ? 'Faça login' : 'Cadastre-se';
  $('#auth-form input[name="senha"]').autocomplete = register ? 'new-password' : 'current-password';
  $('#auth-modal').hidden = false;
}
function closeAuth() { $('#auth-modal').hidden = true; }
function tab(name) {
  $$('.tab').forEach(btn => btn.classList.toggle('active', btn.dataset.tab === name));
  $$('.dash-panel').forEach(panel => { panel.hidden = panel.dataset.panel !== name; });
  window.scrollTo({ top: 0, behavior: 'smooth' });
}
function formValues(form) { return Object.fromEntries(new FormData(form).entries()); }
async function submitWithLoading(form, fn) {
  const button = $('button[type="submit"]', form);
  if (button.disabled) return;
  button.disabled = true;
  try { await fn(); } catch (e) { toast(e.message || 'Erro inesperado.', true); }
  finally { button.disabled = false; }
}
$('#open-login').addEventListener('click', () => openAuth('login'));
$('#open-register').addEventListener('click', () => openAuth('register'));
$('#hero-cta').addEventListener('click', () => openAuth('register'));
$('#switch-auth').addEventListener('click', () => openAuth(state.mode === 'login' ? 'register' : 'login'));
$('#close-modal').addEventListener('click', closeAuth);
$('#auth-modal').addEventListener('click', e => { if (e.target === $('#auth-modal')) closeAuth(); });
$('#auth-form').addEventListener('submit', e => {
  e.preventDefault();
  const form = e.currentTarget;
  submitWithLoading(form, async () => {
    const values = formValues(form);
    const result = await request(state.mode === 'register' ? 'register' : 'login', values);
    toast(result.message);
    if (state.mode === 'register') { openAuth('login'); }
    else { await loadData(); tab('overview'); }
  });
});
$('#resend-email').addEventListener('click', async () => {
  const email = $('#auth-form input[name="email"]').value.trim();
  if (!email) return toast('Informe o e-mail no campo acima para reenviar.', true);
  try { toast((await request('resend', { email })).message); } catch (e) { toast(e.message, true); }
});
$('#logout').addEventListener('click', async () => {
  try { await request('logout'); await loadData(); window.scrollTo(0, 0); toast('Você saiu da conta.'); }
  catch (e) { toast(e.message, true); }
});
$$('.tab').forEach(btn => btn.addEventListener('click', () => tab(btn.dataset.tab)));
document.addEventListener('click', e => {
  const goto = e.target.closest('[data-goto]'); if (goto) tab(goto.dataset.goto);
  const track = e.target.closest('[data-track]'); if (track) showHistory(Number(track.dataset.track), track.dataset.code);
});
$('#address-form').addEventListener('submit', e => {
  e.preventDefault();
  const form = e.currentTarget;
  submitWithLoading(form, async () => {
    const result = await request('address_add', formValues(form));
    toast(result.message); form.reset(); await loadData(); tab('addresses');
  });
});
$('#delivery-form').addEventListener('submit', e => {
  e.preventDefault();
  const form = e.currentTarget;
  submitWithLoading(form, async () => {
    const values = formValues(form);
    const [id_vendedor, id_endereco_origem] = (values.pickup || '').split('|');
    const result = await request('delivery_create', { ...values, id_vendedor, id_endereco_origem });
    const first = Array.isArray(result.delivery) ? result.delivery[0] : result.delivery;
    toast(`${result.message} Código: ${first?.codigo_rastreio || 'consulte suas entregas'}`);
    form.reset(); await loadData(); tab('deliveries');
  });
});
$('#refresh-data').addEventListener('click', async () => {
  try { await loadData(); toast('Dados atualizados.'); } catch (e) { toast(e.message, true); }
});
async function showHistory(id, code) {
  $('#history-modal').hidden = false;
  $('#history-subtitle').textContent = code || `Entrega #${id}`;
  $('#history-content').innerHTML = '<p class="muted">Carregando histórico...</p>';
  try {
    const { history } = await request('tracking', { id_entrega: id });
    $('#history-content').innerHTML = history.length ? history.map(item => `<div class="timeline-item"><strong>${esc(statusNames[item.status] || item.status)}</strong><p>${esc(item.descricao || 'Status atualizado')}</p><time>${esc(dateBR(item.registrado_em))}</time></div>`).join('') : '<p class="muted">Ainda não há eventos para esta entrega.</p>';
  } catch (e) { $('#history-content').textContent = e.message; }
}
$('#close-history').addEventListener('click', () => { $('#history-modal').hidden = true; });
$('#history-modal').addEventListener('click', e => { if (e.target === $('#history-modal')) $('#history-modal').hidden = true; });
document.addEventListener('keydown', e => { if (e.key === 'Escape') { closeAuth(); $('#history-modal').hidden = true; } });
// Inicialização ao final, após registrar todos os painéis e callbacks.

// Painéis adicionais: vendedor, entregador, pagamentos e gestor.
function compactDelivery(d, controls = '') {
  return `<article class="delivery-item"><div><strong>${esc(d.codigo_rastreio || `#${d.id_entrega}`)}</strong><p>${esc(d.descricao_carga || '')} · ${statusTag(d.status)} · ${money(d.valor_frete)}</p></div><div class="mini-actions">${controls}</div></article>`;
}
function empty(text) { return `<div class="empty">${esc(text)}</div>`; }
function renderOperations(data) {
  const op = data.operations || {};
  const roles = op.roles || {};
  ['seller-form', 'driver-document-form', 'vehicle-form', 'payment-form'].forEach(id => {
    $$('input,select,button', document.getElementById(id)).forEach(control => { control.disabled = Boolean(op.unavailable); });
  });
  $('#driver-register').disabled = Boolean(op.unavailable);
  $('#driver-availability').disabled = Boolean(op.unavailable);
  $('#admin-tab').hidden = !roles.gestor;
  $('#seller-status').textContent = !roles.vendedor ? 'Ainda não há loja cadastrada nesta conta.' :
    roles.vendedor_aprovado ? '✓ Loja aprovada. Cadastre um endereço comercial/de coleta para aparecer aos clientes.' :
    'Cadastro recebido. Aguarde a aprovação de um gestor.';
  $('#seller-deliveries').innerHTML = (op.seller_deliveries || []).map(d => compactDelivery(d)).join('') || empty('Sua loja ainda não recebeu entregas.');
  $('#driver-status').textContent = !roles.entregador ? 'Cadastre-se como entregador para começar.' :
    `${roles.entregador_aprovado ? '✓ Cadastro aprovado' : 'Aguardando aprovação'} · ${roles.disponivel ? 'Disponível' : 'Indisponível'}`;
  $('#driver-register').hidden = Boolean(roles.entregador);
  $('#driver-availability').hidden = !roles.entregador;
  $('#driver-availability').textContent = roles.disponivel ? 'Ficar indisponível' : 'Ficar disponível';
  const vehicles = op.vehicles || [];
  $('#vehicle-list').innerHTML = vehicles.map(v => `<div class="address-item"><div><strong>${esc(v.marca)} ${esc(v.modelo)}</strong><p>${esc(v.tipo)} · Placa ${esc(v.placa)} · ${esc(v.capacidade_kg)} kg</p></div>${v.principal ? '<span class="tag">Principal</span>' : ''}</div>`).join('') || empty('Nenhum veículo cadastrado.');
  const vehicleOptions = vehicles.filter(v => v.ativo).map(v => `<option value="${Number(v.id_veiculo)}">${esc(v.placa)} — ${esc(v.modelo)}</option>`).join('');
  $('#available-deliveries').innerHTML = (op.available_deliveries || []).map(d => compactDelivery(d,
    `<select class="inline-select" aria-label="Veículo" data-vehicle-for="${Number(d.id_entrega)}"><option value="">Escolha o veículo</option>${vehicleOptions}</select><button class="btn btn-primary btn-small" data-claim="${Number(d.id_entrega)}">Assumir</button>`)).join('') || empty('Não há entregas disponíveis para sua conta.');
  const nextStatus = {aguardando_coleta:'coletada',coletada:'em_transito',em_transito:'saiu_para_entrega'};
  const statusButton = {coletada:'Confirmar coleta',em_transito:'Iniciar transporte',saiu_para_entrega:'Saiu para entrega'};
  $('#driver-deliveries').innerHTML = (op.driver_deliveries || []).map(d => compactDelivery(d,
    nextStatus[d.status] ? `<button class="btn btn-primary btn-small" data-driver-status="${esc(nextStatus[d.status])}" data-id="${Number(d.id_entrega)}">${esc(statusButton[nextStatus[d.status]])}</button>` :
    d.status === 'saiu_para_entrega' ? `<button class="btn btn-yellow btn-small" data-proof="${Number(d.id_entrega)}">Registrar recebimento</button>` : '')).join('') || empty('Nenhuma entrega atribuída.');
  const deliveries = data.deliveries || [];
  $('#payment-delivery-select').innerHTML = '<option value="">Selecione uma entrega</option>' + deliveries.filter(d => d.status !== 'cancelada').map(d => `<option value="${Number(d.id_entrega)}">${esc(d.codigo_rastreio)} — ${money(d.valor_frete)}</option>`).join('');
  $('#payment-list').innerHTML = (op.my_payments || []).map(p => `<div class="address-item"><div><strong>Entrega #${Number(p.id_entrega)}</strong><p>${money(p.valor)} · ${esc(p.metodo)} · ${esc(dateBR(p.criado_em))}</p></div><span class="tag ${p.status_pagamento === 'pago' ? 'tag-green' : 'tag-yellow'}">${esc(p.status_pagamento)}</span></div>`).join('') || empty('Nenhum pagamento registrado.');
  if (roles.gestor) {
    $('#admin-sellers').innerHTML = (op.admin_sellers || []).map(v => `<div class="address-item"><div><strong>${esc(v.nome)}</strong><p>Vendedor #${Number(v.id)}</p></div>${v.aprovado ? '<span class="tag tag-green">Aprovado</span>' : `<button class="btn btn-primary btn-small" data-approve="vendedor" data-id="${Number(v.id)}">Aprovar</button>`}</div>`).join('') || empty('Nenhum vendedor.');
    $('#admin-drivers').innerHTML = (op.admin_drivers || []).map(d => `<div class="address-item"><div><strong>${esc(d.nome)}</strong><p>Entregador #${Number(d.id)}</p></div>${d.aprovado ? '<span class="tag tag-green">Aprovado</span>' : `<button class="btn btn-primary btn-small" data-approve="entregador" data-id="${Number(d.id)}">Aprovar</button>`}</div>`).join('') || empty('Nenhum entregador.');
    $('#admin-payments').innerHTML = (op.admin_payments || []).map(p => `<div class="address-item"><div><strong>Pagamento #${Number(p.id_pagamento)}</strong><p>Entrega #${Number(p.id_entrega)} · ${money(p.valor)} · ${esc(p.metodo)}</p></div>${p.status_pagamento === 'pendente' ? `<button class="btn btn-yellow btn-small" data-admin-payment="${Number(p.id_pagamento)}">Confirmar após conferir</button>` : `<span class="tag tag-green">${esc(p.status_pagamento)}</span>`}</div>`).join('') || empty('Nenhum pagamento.');
    $('#admin-deliveries').innerHTML = (op.admin_deliveries || []).map(d => compactDelivery(d)).join('') || empty('Nenhuma entrega.');
  }
}
function wireForm(id, action, messageHandler) {
  $(id).addEventListener('submit', e => {
    e.preventDefault();
    const form = e.currentTarget;
    submitWithLoading(form, async () => {
      const result = await request(action, formValues(form));
      toast(result.message || 'Operação realizada.');
      if (messageHandler) messageHandler(form);
      await loadData();
    });
  });
}
wireForm('#seller-form', 'seller_register');
wireForm('#driver-document-form', 'driver_document', f => f.reset());
wireForm('#vehicle-form', 'vehicle_add', f => f.reset());
wireForm('#payment-form', 'payment_request');
$('#driver-register').addEventListener('click', async () => {
  try { toast((await request('driver_register')).message); await loadData(); }
  catch (e) { toast(e.message, true); }
});
$('#driver-availability').addEventListener('click', async () => {
  try {
    const current = Boolean(state.me?.operations?.roles?.disponivel);
    toast((await request('availability', { disponivel: !current })).message); await loadData();
  } catch (e) { toast(e.message, true); }
});
document.addEventListener('click', async e => {
  const action = e.target.closest('[data-address-primary],[data-address-disable],[data-cancel],[data-claim],[data-driver-status],[data-proof],[data-approve],[data-admin-payment]');
  if (!action) return;
  const attr = action.dataset;
  if (attr.proof) {
    $('#proof-form input[name="id_entrega"]').value = attr.proof;
    $('#proof-modal').hidden = false;
    return;
  }
  if (action.disabled) return;
  action.disabled = true;
  try {
    let result;
    if (attr.addressPrimary) result = await request('address_primary', { id_endereco: Number(attr.addressPrimary) });
    else if (attr.addressDisable) {
      if (!confirm('Desativar este endereço? Ele não será apagado das entregas antigas.')) return;
      result = await request('address_disable', { id_endereco: Number(attr.addressDisable) });
    } else if (attr.cancel) {
      if (!confirm('Deseja cancelar esta entrega?')) return;
      result = await request('delivery_cancel', { id_entrega: Number(attr.cancel) });
    } else if (attr.claim) {
      const vehicle = document.querySelector(`[data-vehicle-for="${Number(attr.claim)}"]`);
      if (!vehicle?.value) return toast('Selecione um veículo.', true);
      result = await request('driver_claim', { id_entrega: Number(attr.claim), id_veiculo: Number(vehicle.value) });
    } else if (attr.driverStatus) result = await request('driver_status', { id_entrega: Number(attr.id), status: attr.driverStatus });
    else if (attr.approve) {
      if (!confirm('Você verificou os dados e documentos deste cadastro?')) return;
      result = await request('admin_approve', { id: Number(attr.id), tipo: attr.approve });
    } else if (attr.adminPayment) {
      if (!confirm('Você conferiu o recebimento real FORA do Moove? Esta ação marcará o pagamento como PAGO.')) return;
      result = await request('admin_payment', { id_pagamento: Number(attr.adminPayment) });
    }
    if (result) { toast(result.message); await loadData(); }
  } catch (err) { toast(err.message, true); }
  finally { action.disabled = false; }
});
$('#close-proof').addEventListener('click', () => { $('#proof-modal').hidden = true; });
$('#proof-form').addEventListener('submit', e => {
  e.preventDefault();
  const form = e.currentTarget;
  submitWithLoading(form, async () => {
    const values = formValues(form);
    values.recebido_pelo_cliente = Boolean($('#proof-form input[name="recebido_pelo_cliente"]').checked);
    const result = await request('delivery_proof', values);
    toast(result.message); form.reset(); $('#proof-modal').hidden = true; await loadData();
  });
});
$('#forgot-password').addEventListener('click', async () => {
  const email = $('#auth-form input[name="email"]').value.trim();
  if (!email) return toast('Informe o e-mail no formulário primeiro.', true);
  try { toast((await request('password_recover', { email })).message); } catch (e) { toast(e.message, true); }
});
const resetParams = new URLSearchParams(window.location.hash.slice(1));
if (resetParams.get('type') === 'recovery' && resetParams.get('access_token')) {
  state.resetToken = resetParams.get('access_token');
  $('#reset-modal').hidden = false;
  history.replaceState(null, '', location.pathname + location.search);
}
$('#reset-form').addEventListener('submit', e => {
  e.preventDefault();
  const form = e.currentTarget;
  submitWithLoading(form, async () => {
    const result = await request('password_reset_confirm', { access_token: state.resetToken, senha: form.querySelector('[name=senha]').value });
    toast(result.message); $('#reset-modal').hidden = true; state.resetToken = null; openAuth('login');
  });
});

loadData().catch(e => toast('Não foi possível carregar os dados: ' + e.message, true));
