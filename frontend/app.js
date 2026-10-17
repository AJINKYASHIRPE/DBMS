// In Codespaces the page is on port 5500 and the API on 8080 of the same host.
const API = location.hostname.endsWith('.app.github.dev')
  ? location.origin.replace(/-\d+(\.app\.github\.dev)$/, '-8080$1')
  : 'http://localhost:8080';

const $ = id => document.getElementById(id);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money = n => new Intl.NumberFormat('en-IN', {style:'currency', currency:'INR'}).format(Number(n));
const dt = s => s ? String(s).replace('T', ' ').slice(0, 16) : '-';
const day = s => s ? String(s).slice(0, 10) : '-';
const show = (id, on) => $(id).classList.toggle('hidden', !on);

let session = JSON.parse(sessionStorage.getItem('session') || 'null');

function msg(text, ok) {
  const m = $('msg');
  m.textContent = text;
  m.className = 'msg ' + (ok ? 'ok' : 'err');
  clearTimeout(msg.t);
  msg.t = setTimeout(() => show('msg', false), 6000);
}

async function api(path, method = 'GET', body) {
  let res;
  try {
    res = await fetch(API + path, {
      method,
      headers: {'Content-Type': 'application/json', ...(session ? {Authorization: 'Bearer ' + session.token} : {})},
      body: body ? JSON.stringify(body) : undefined
    });
  } catch (e) {
    throw new Error('Cannot reach the server. Is the backend running and port 8080 set to Public?');
  }
  const data = await res.json().catch(() => ({}));
  if (res.status === 401) throw new Error('Invalid login details');
  if (res.status === 403) { if (session) logout(); throw new Error('Session expired. Please sign in again.'); }
  if (!res.ok) throw new Error(data.error || 'Something went wrong');
  return data;
}

// ---------- login / logout ----------
function showLogin() {
  show('login', true); show('customer', false); show('admin', false); show('topbar', false);
}
function logout() {
  session = null;
  sessionStorage.removeItem('session');
  ['c-pin', 'a-pass'].forEach(id => $(id).value = '');
  showLogin();
}
async function login(kind) {
  const body = kind === 'customer'
    ? {accountNo: $('c-acc').value.trim(), pin: $('c-pin').value}
    : {username: $('a-user').value.trim(), password: $('a-pass').value};
  const d = await api('/api/auth/' + kind + '/login', 'POST', body);
  session = {token: d.token, role: d.role};
  sessionStorage.setItem('session', JSON.stringify(session));
  await start();
}
async function start() {
  if (!session) return showLogin();
  await (session.role === 'ADMIN' ? loadAdmin() : loadCustomer());
}
const refresh = () => start();

$('tab-customer').onclick = () => { $('tab-customer').classList.add('active'); $('tab-admin').classList.remove('active'); show('form-customer', true); show('form-admin', false); };
$('tab-admin').onclick = () => { $('tab-admin').classList.add('active'); $('tab-customer').classList.remove('active'); show('form-admin', true); show('form-customer', false); };
$('c-login').onclick = () => login('customer').catch(e => msg(e.message, false));
$('a-login').onclick = () => login('admin').catch(e => msg(e.message, false));
$('logout').onclick = logout;

// ---------- shared rendering ----------
const IN = ['CREATE', 'DEPOSIT', 'TRANSFER_IN', 'LOAN_CREDIT'];
function renderTxns(rows, id) {
  $(id).innerHTML = rows.length
    ? '<table><tr><th>Date</th><th>Type</th><th>Amount</th><th>Details</th></tr>' +
      rows.map(t => {
        const inn = IN.includes(t.txn_type);
        return `<tr><td>${dt(t.txn_time)}</td><td>${esc(t.txn_type.replace('_', ' '))}</td>` +
               `<td class="${inn ? 'in' : 'out'}">${inn ? '+' : '-'}${money(t.amount)}</td><td>${esc(t.description)}</td></tr>`;
      }).join('') + '</table>'
    : '<p class="muted">No transactions.</p>';
}
function badge(s) {
  const c = s === 'CLOSED' ? 'b-closed' : (s === 'PAYING ON TIME' ? 'b-good' : 'b-bad');
  return `<span class="badge ${c}">${esc(s)}</span>`;
}

// ---------- customer ----------
async function loadCustomer() {
  show('login', false); show('admin', false); show('customer', true); show('topbar', true);
  const [me, txns, loans] = await Promise.all([
    api('/api/customer/me'), api('/api/customer/transactions'), api('/api/customer/loans')]);
  $('who').textContent = me.name + ' (' + me.account_no + ')';
  $('balance').textContent = money(me.balance);
  $('c-since').textContent = 'Customer since ' + day(me.created_at);
  $('loans').innerHTML = loans.length
    ? '<table><tr><th>Loan</th><th>Amount</th><th>EMI</th><th>Paid</th><th>Outstanding</th><th>Next due</th><th>Status</th></tr>' +
      loans.map(l => `<tr><td>#${esc(l.loan_id)}</td><td>${money(l.principal)}</td><td>${money(l.emi)}</td>` +
        `<td>${esc(l.emis_paid)}/${esc(l.total_emis)}</td><td>${money(l.outstanding)}</td>` +
        `<td>${day(l.next_due_date)}</td><td>${badge(l.status)}</td></tr>`).join('') + '</table>'
    : '<p class="muted">No loans.</p>';
  show('pay-emi', loans.some(l => l.status !== 'CLOSED'));
  allTxns = txns;
  applyFilter();
}

async function act(fn, okText) {
  try { await fn(); msg(okText, true); await refresh(); }
  catch (e) { msg(e.message, false); }
}
function positive(id) {
  const v = Number($(id).value);
  if (!(v > 0)) throw new Error('Enter an amount greater than zero');
  return v;
}

$('dep-btn').onclick = () => act(async () => {
  await api('/api/customer/deposit', 'POST', {amount: positive('dep-amt')}); $('dep-amt').value = '';
}, 'Deposit successful');
$('wd-btn').onclick = () => act(async () => {
  await api('/api/customer/withdraw', 'POST', {amount: positive('wd-amt')}); $('wd-amt').value = '';
}, 'Withdrawal successful');
$('tr-btn').onclick = () => act(async () => {
  const to = $('tr-acc').value.trim();
  if (!to) throw new Error('Enter the receiver account number');
  await api('/api/customer/transfer', 'POST', {toAccount: to, amount: positive('tr-amt')});
  $('tr-acc').value = ''; $('tr-amt').value = '';
}, 'Transfer successful');
$('ln-btn').onclick = () => act(async () => {
  await api('/api/customer/loans', 'POST', {amount: positive('ln-amt'), months: Number($('ln-months').value)});
  $('ln-amt').value = ''; emiPreview();
}, 'Loan credited to your account');
$('pay-emi').onclick = () => act(() => api('/api/customer/loans/pay-emi', 'POST'), 'EMI paid');

// ---------- admin ----------
async function loadAdmin() {
  show('login', false); show('customer', false); show('admin', true); show('topbar', true);
  const [accs, loans] = await Promise.all([api('/api/admin/accounts'), api('/api/admin/loans')]);
  $('who').textContent = 'Admin';
  $('accounts').innerHTML = '<table><tr><th>Account</th><th>Name</th><th>Balance</th><th>Opened</th><th></th></tr>' +
    accs.map(a => `<tr><td>${esc(a.account_no)}</td><td>${esc(a.name)}</td><td>${money(a.balance)}</td>` +
      `<td>${day(a.created_at)}</td><td><button class="small" data-acc="${esc(a.account_no)}">Transactions</button></td></tr>`).join('') +
    '</table>';
  $('admin-loans').innerHTML = loans.length
    ? '<table><tr><th>Customer</th><th>Account</th><th>Loan</th><th>Amount</th><th>EMI</th><th>Paid</th><th>Outstanding</th><th>Status</th></tr>' +
      loans.map(l => `<tr><td>${esc(l.name)}</td><td>${esc(l.account_no)}</td><td>#${esc(l.loan_id)}</td>` +
        `<td>${money(l.principal)}</td><td>${money(l.emi)}</td><td>${esc(l.emis_paid)}/${esc(l.total_emis)}</td>` +
        `<td>${money(l.outstanding)}</td><td>${badge(l.status)}</td></tr>`).join('') + '</table>'
    : '<p class="muted">No loans.</p>';
}
$('accounts').onclick = async e => {
  const b = e.target.closest('button[data-acc]');
  if (!b) return;
  try {
    const t = await api('/api/admin/accounts/' + encodeURIComponent(b.dataset.acc) + '/transactions');
    $('acc-title').textContent = 'Transactions for ' + b.dataset.acc;
    renderTxns(t, 'acc-txns');
    show('acc-panel', true);
  } catch (err) { msg(err.message, false); }
};
$('n-btn').onclick = async () => {
  try {
    const name = $('n-name').value.trim();
    if (!name) throw new Error('Enter the customer name');
    const d = await api('/api/admin/accounts', 'POST',
      {name, pin: $('n-pin').value, initialDeposit: Number($('n-amt').value || 0)});
    msg('Account ' + d.accountNo + ' created', true);
    $('n-name').value = ''; $('n-pin').value = ''; $('n-amt').value = '0';
    await refresh();
  } catch (e) { msg(e.message, false); }
};

// ---------- filter, CSV statement, EMI preview ----------
let allTxns = [];
const FILTERS = {
  ALL: null,
  DEPOSIT: ['DEPOSIT'],
  WITHDRAW: ['WITHDRAW'],
  TRANSFER: ['TRANSFER_IN', 'TRANSFER_OUT'],
  LOAN: ['LOAN_CREDIT', 'EMI_PAID']
};
function filtered() {
  const types = FILTERS[$('txn-filter').value];
  return types ? allTxns.filter(t => types.includes(t.txn_type)) : allTxns;
}
function applyFilter() { renderTxns(filtered(), 'txns'); }
$('txn-filter').onchange = applyFilter;

function csvCell(v) {
  let s = String(v ?? '');
  if (/^[=+\-@]/.test(s)) s = "'" + s;   // stop spreadsheet formula injection
  return '"' + s.replace(/"/g, '""') + '"';
}
$('csv-btn').onclick = () => {
  const rows = filtered();
  if (!rows.length) return msg('No transactions to download', false);
  const lines = ['Date,Type,Amount,Details'].concat(rows.map(t =>
    [dt(t.txn_time), t.txn_type, t.amount, t.description].map(csvCell).join(',')));
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([lines.join('\n')], {type: 'text/csv'}));
  a.download = 'statement.csv';
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
};

function emiPreview() {
  const p = Number($('ln-amt').value), n = Number($('ln-months').value);
  const el = $('emi-preview');
  if (!(p > 0) || !(n >= 3 && n <= 36)) { el.textContent = ''; return; }
  const r = 12 / 12 / 100;                       // 12% p.a., same as the bank's loan rate
  const emi = p * r * Math.pow(1 + r, n) / (Math.pow(1 + r, n) - 1);
  el.textContent = 'Estimated EMI: ' + money(emi) + ' per month, total repayment ' + money(emi * n);
}
$('ln-amt').oninput = emiPreview;
$('ln-months').oninput = emiPreview;

start().catch(e => msg(e.message, false));
