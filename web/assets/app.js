(() => {
  const root = document.getElementById('fuel-root');
  const app = document.getElementById('app');
  const modeLabel = document.getElementById('mode-label');
  const footerStation = document.getElementById('footer-station');
  const screen = document.querySelector('.screen');
  const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'ps-fuel';
  let mode = 'refuel';
  let state = {};
  let selectedFuel = null;
  let activeTab = 'overview';
  let utility = null;

  const esc = (value) => String(value ?? '').replace(/[&<>'"]/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  const money = (value) => `£${Math.round(Number(value) || 0).toLocaleString('en-GB')}`;
  const number = (value, digits = 0) => (Number(value) || 0).toLocaleString('en-GB', {maximumFractionDigits: digits, minimumFractionDigits: digits});
  const post = async (name, data = {}) => {
    if (resource === 'ps-fuel' && typeof GetParentResourceName !== 'function') return {success:true};
    try {
      const response = await fetch(`https://${resource}/${name}`, {method:'POST', headers:{'Content-Type':'application/json; charset=UTF-8'}, body:JSON.stringify(data)});
      return await response.json();
    } catch (error) {
      return {success:false, message:'The fuel terminal could not reach the game client.'};
    }
  };
  const toast = (message, type = 'inform') => {
    if (!message) return;
    const item = document.createElement('div');
    item.className = `toast ${type}`;
    item.textContent = message;
    document.getElementById('toast-stack').appendChild(item);
    setTimeout(() => item.remove(), 3400);
  };
  let employeeModal = null;
  const closeEmployeeModal = () => {
    if (!employeeModal) return;
    employeeModal.remove();
    employeeModal = null;
  };
  const openEmployeeModal = () => {
    closeEmployeeModal();
    const overlay = document.createElement('div');
    overlay.className = 'employee-modal-overlay';
    overlay.innerHTML = `
      <div class="employee-modal" role="dialog" aria-modal="true" aria-labelledby="employee-modal-title">
        <div class="employee-modal-head">
          <div>
            <p class="eyebrow">STATION STAFF</p>
            <h2 id="employee-modal-title">Add employee</h2>
          </div>
          <button class="employee-modal-close" type="button" aria-label="Close">×</button>
        </div>
        <form id="employee-form">
          <label class="form-label" for="employee-identifier">Player identifier / citizen ID</label>
          <input class="text-input" id="employee-identifier" name="identifier" type="text" maxlength="80" autocomplete="off" required>
          <label class="form-label" for="employee-name">Display name</label>
          <input class="text-input" id="employee-name" name="name" type="text" maxlength="80" autocomplete="off">
          <label class="form-label" for="employee-role">Role</label>
          <select class="text-input" id="employee-role" name="role">
            <option value="employee">Employee</option>
            <option value="manager">Manager</option>
          </select>
          <div class="employee-modal-actions">
            <button class="secondary" id="employee-cancel" type="button">Cancel</button>
            <button class="primary" id="employee-save" type="submit">Add employee</button>
          </div>
        </form>
      </div>`;
    (screen || document.body).appendChild(overlay);
    employeeModal = overlay;

    const identifierInput = overlay.querySelector('#employee-identifier');
    const nameInput = overlay.querySelector('#employee-name');
    const roleInput = overlay.querySelector('#employee-role');
    const form = overlay.querySelector('#employee-form');
    const saveButton = overlay.querySelector('#employee-save');

    overlay.querySelector('.employee-modal-close')?.addEventListener('click', closeEmployeeModal);
    overlay.querySelector('#employee-cancel')?.addEventListener('click', closeEmployeeModal);
    overlay.addEventListener('mousedown', (event) => {
      if (event.target === overlay) closeEmployeeModal();
    });
    form?.addEventListener('submit', async (event) => {
      event.preventDefault();
      const identifier = String(identifierInput?.value || '').trim();
      if (!identifier) {
        toast('Enter a player identifier or citizen ID.', 'error');
        identifierInput?.focus();
        return;
      }
      const name = String(nameInput?.value || '').trim() || identifier;
      const role = roleInput?.value === 'manager' ? 'manager' : 'employee';
      if (saveButton) {
        saveButton.disabled = true;
        saveButton.textContent = 'SAVING...';
      }
      const response = await post('addStationEmployee', {stationId:state.id,identifier,name,role});
      if (!response?.success) {
        toast(response?.message || 'Employee update failed.', 'error');
        if (saveButton) {
          saveButton.disabled = false;
          saveButton.textContent = 'Add employee';
        }
        return;
      }
      closeEmployeeModal();
      toast(response?.message || 'Employee saved.', 'success');
      await refreshStation(false);
    });
    requestAnimationFrame(() => identifierInput?.focus());
  };
  const close = () => {
    closeEmployeeModal();
    root.classList.remove('visible');
    root.setAttribute('aria-hidden', 'true');
    if (mode === 'utility') post('utilityCancel'); else post('fuelClose');
  };
  const fuelTypes = () => Array.isArray(state.fuelTypes) ? state.fuelTypes : [];
  const allowed = () => new Set(state.vehicle?.allowedFuelTypes || []);
  const chosen = () => fuelTypes().find((fuel) => fuel.id === selectedFuel) || fuelTypes()[0] || {unitPrice:0,label:'Fuel'};

  function utilityField(field) {
    const key = esc(field.key || 'value');
    const type = field.type || 'text';
    const label = esc(field.label || field.key || 'Value');
    const description = field.description ? `<small>${esc(field.description)}</small>` : '';
    const full = field.full === true ? ' full' : '';
    if (type === 'checkbox') {
      return `<div class="utility-field${full}"><label class="utility-check"><input data-utility-field="${key}" type="checkbox" ${field.default === true ? 'checked' : ''}><span>${label}</span></label>${description}</div>`;
    }
    if (type === 'select') {
      const options = Array.isArray(field.options) ? field.options : [];
      return `<div class="utility-field${full}"><label class="form-label">${label}</label>${description}<select class="text-input" data-utility-field="${key}">${options.map((option)=>`<option value="${esc(option.value)}" ${String(option.value)===String(field.default??'')?'selected':''}>${esc(option.label ?? option.value)}</option>`).join('')}</select></div>`;
    }
    const inputType = type === 'number' ? 'number' : type === 'password' ? 'password' : 'text';
    const attrs = [field.min != null ? `min="${esc(field.min)}"` : '', field.max != null ? `max="${esc(field.max)}"` : '', field.step != null ? `step="${esc(field.step)}"` : '', field.required === true ? 'required' : ''].filter(Boolean).join(' ');
    return `<div class="utility-field${full}"><label class="form-label">${label}</label>${description}<input class="text-input" data-utility-field="${key}" type="${inputType}" value="${esc(field.default ?? '')}" ${attrs}></div>`;
  }

  function utilityView() {
    const data = utility || {};
    const rows = Array.isArray(data.rows) ? data.rows : [];
    const fields = Array.isArray(data.fields) ? data.fields : [];
    const actions = Array.isArray(data.actions) && data.actions.length ? data.actions : [{id:'submit',label:'Continue',style:'primary'}];
    const note = data.note ? `<div class="utility-note">${esc(data.note)}</div>` : '';
    return `<div class="utility-page">${pageHeader(data.title || 'FuelOS',data.description || 'Fuel system operation',data.badge || 'Tablet')}${note}<article class="utility-card">${rows.length ? `<div class="utility-rows">${rows.map((row)=>`<div class="utility-row"><div><strong>${esc(row.label || '')}</strong>${row.description ? `<small>${esc(row.description)}</small>` : ''}</div><div class="utility-row-value">${esc(row.value ?? '')}</div></div>`).join('')}</div>` : ''}${fields.length ? `<form id="utility-form"><div class="utility-fields">${fields.map(utilityField).join('')}</div></form>` : ''}<div class="utility-actions">${actions.map((action)=>`<button type="button" class="${action.style==='danger'?'danger':action.style==='secondary'?'secondary':'primary'}" data-utility-action="${esc(action.id || 'submit')}">${esc(action.label || 'Continue')}</button>`).join('')}</div></article></div>`;
  }

  function utilityValues() {
    const values = {};
    app.querySelectorAll('[data-utility-field]').forEach((field) => {
      const key = field.dataset.utilityField;
      if (!key) return;
      if (field.type === 'checkbox') values[key] = field.checked === true;
      else if (field.type === 'number') values[key] = field.value === '' ? null : Number(field.value);
      else values[key] = field.value;
    });
    return values;
  }

  function pageHeader(title, description, badge = 'Online') {
    return `<div class="page-header"><div><p class="eyebrow">PS FUEL OPERATIONS</p><h1>${esc(title)}</h1><p>${esc(description)}</p></div><span class="badge">${esc(badge)}</span></div>`;
  }
  function stat(label, value, meta) {
    return `<article class="card"><div class="stat-label"><span>${esc(label)}</span><span>LIVE</span></div><div class="stat-value">${value}</div><div class="stat-meta">${esc(meta)}</div></article>`;
  }
  function tabs(items) {
    return `<nav class="tabs">${items.map(([id,label]) => `<button class="tab ${activeTab === id ? 'active' : ''}" data-tab="${id}">${label}</button>`).join('')}</nav>`;
  }

  function refuelView(includeHeader = true) {
    if (!state.vehicle) return `<article class="card empty"><div><strong>No vehicle detected</strong><p>Park beside a pump to select a fuel type.</p></div></article>`;
    const valid = fuelTypes().filter((fuel) => allowed().has(fuel.id));
    if (!selectedFuel || !allowed().has(selectedFuel)) selectedFuel = valid[0]?.id || null;
    const fuel = chosen();
    const current = Number(state.vehicle.fuel) || 0;
    return `${includeHeader ? pageHeader('Select fuel type', `${state.label || 'Fuel station'} · choose the correct fuel before using the pump`, 'Pump ready') : ''}
      <div class="fuel-layout">
        <div>
          <article class="card vehicle-card">
            <div class="vehicle-head"><div><div class="vehicle-name">${esc(state.vehicle.label)}</div><span class="vehicle-plate">${esc(state.vehicle.plate)}</span></div><span class="badge">${state.vehicle.electric ? (state.vehicle.fastCharge ? 'Fast-charge EV' : 'Electric vehicle') : (state.vehicle.fuelFamilyLabel || (state.vehicle.diesel ? 'Diesel vehicle' : 'Petrol vehicle'))}</span></div>
            <div class="gauge-row"><div class="gauge"><div class="gauge-fill" style="width:${Math.min(100,current)}%"></div></div><div class="gauge-value">${number(current,1)}% · ${number(state.vehicle.volume,1)} / ${number(state.vehicle.capacity,1)} ${state.vehicle.electric ? 'kWh' : 'L'}</div></div>
          </article>
          <div class="fuel-types">${fuelTypes().map((item) => {
            const enabled = allowed().has(item.id);
            return `<button class="fuel-type ${selectedFuel === item.id ? 'selected' : ''} ${enabled ? '' : 'disabled'}" data-fuel="${esc(item.id)}" ${enabled ? '' : 'disabled'} style="--fuel-accent:${esc(item.accent || '#1ee8ef')}"><strong>${esc(item.label)}</strong><small>${esc(item.description)}</small><div class="fuel-price">${money(item.unitPrice)} / ${state.vehicle?.electric ? 'kWh' : 'L'}</div></button>`;
          }).join('')}</div>
        </div>
        <article class="card amount-panel">
          <div class="section-title"><h2>Physical pump control</h2><span>Step 1 of 2</span></div>
          <div class="summary">
            <div class="summary-row"><span>Selected fuel</span><strong>${esc(fuel.label)}</strong></div>
            <div class="summary-row"><span>${state.vehicle.electric ? 'Battery charge' : 'Current fuel'}</span><strong>${number(current,1)}%</strong></div>
            <div class="summary-row"><span>Unit rate</span><strong>${money(fuel.unitPrice)} / ${state.vehicle?.electric ? 'kWh' : 'L'}</strong></div>
          </div>
          <p style="color:var(--muted);font-size:10px;line-height:1.7;margin:16px 0">${state.physicalNozzle ? `The connected ${state.vehicle.electric ? 'charging connector' : 'fuel nozzle'} will start automatically after selection. Live progress appears above the vehicle.` : 'Selecting a fuel type closes the terminal. Insert the nozzle into the vehicle to begin; live progress appears above it.'}</p>
          <button class="primary wide" id="select-fuel" ${!selectedFuel || current >= (Number(state.vehicle.maxFuel) || 100) ? 'disabled' : ''}>SELECT ${esc(String(fuel.label || 'FUEL').toUpperCase())}</button>
        </article>
      </div>`;
  }

  function overviewView() {
    const stockPercent = Math.min(100, ((Number(state.stock)||0) / Math.max(1,Number(state.capacity)||1))*100);
    return `${pageHeader(state.label || 'Fuel station', `Owned by ${state.owner || 'Unknown'} · management terminal`, 'Owner access')}
      ${tabs([['overview','Overview'],['refuel','Refuel'],['operations','Operations'],['advanced','Advanced'],['ledger','Ledger']])}
      <div class="grid stats">${stat('Station balance', money(state.balance), 'Available to withdraw')}${stat('Lifetime revenue', money(state.totalSales), 'Gross station sales')}${stat('Fuel sold', `${number(state.totalFuel,1)} L`, 'Recorded volume')}${stat('Price multiplier', `${number(state.priceMultiplier || 1,2)}×`, 'Owner retail rate')}</div>
      <div class="grid two" style="margin-top:12px"><article class="card"><div class="section-title"><h2>Fuel reserves</h2><span>${number(stockPercent,0)}% capacity</span></div><div class="gauge"><div class="gauge-fill" style="width:${stockPercent}%"></div></div><div class="summary-row"><span>Current stock</span><strong>${number(state.stock,0)} / ${number(state.capacity,0)}</strong></div><div class="summary-row"><span>Market multiplier</span><strong>${number(state.marketMultiplier || 1,2)}×</strong></div></article><article class="card"><div class="section-title"><h2>Owner controls</h2><span>Protected</span></div><p style="color:var(--muted);font-size:10px;line-height:1.6">Only the station owner or an authorised administrator can open this management tablet. Public players retain access to the pump terminal only.</p><button class="secondary wide" id="refresh-station">Synchronise station data</button></article></div>`;
  }

  function operationsView() {
    return `${pageHeader(state.label || 'Fuel station','Pricing, banking and station operations','Owner controls')}${tabs([['overview','Overview'],['refuel','Refuel'],['operations','Operations'],['advanced','Advanced'],['ledger','Ledger']])}<div class="grid two"><article class="card"><div class="section-title"><h2>Retail pricing</h2><span>0.50× – 2.00×</span></div><label class="form-label" for="multiplier">Station price multiplier</label><input class="text-input" id="multiplier" type="number" min="0.5" max="2" step="0.05" value="${Number(state.priceMultiplier)||1}"/><button class="primary wide" id="save-multiplier">Save pricing</button><button class="secondary wide" id="withdraw">Withdraw ${money(state.balance)}</button></article><article class="card"><div class="section-title"><h2>Station services</h2><span>Live actions</span></div><div class="action-list"><div class="action"><div class="action-copy"><strong>Fuel delivery</strong><small>Collect a tanker and replenish station stock.</small></div><button class="secondary" id="start-delivery" ${state.deliveriesEnabled ? '' : 'disabled'}>Start</button></div><div class="action"><div class="action-copy"><strong>Jerry can</strong><small>Purchase portable emergency fuel for ${money(state.jerryCanPrice)}.</small></div><button class="secondary" id="buy-jerry">Buy</button></div><div class="action"><div class="action-copy"><strong>Security simulation</strong><small>Start the configured station robbery flow.</small></div><button class="danger" id="start-robbery" ${state.robberiesEnabled ? '' : 'disabled'}>Start</button></div></div></article></div>`;
  }

  function advancedView() {
    const adv = state.advanced || {};
    const stationAdv = adv.station || {};
    const analytics = adv.analytics || {};
    const employees = Array.isArray(adv.employees) ? adv.employees : [];
    const breakdown = Array.isArray(adv.fuelBreakdown) ? adv.fuelBreakdown : [];
    const level = (key) => Number(stationAdv[key] || 0);
    return `${pageHeader(state.label || 'Fuel station','Fleet, supplier, maintenance and analytics controls','FuelOS 3.5.1')}
      ${tabs([['overview','Overview'],['refuel','Refuel'],['operations','Operations'],['advanced','Advanced'],['ledger','Ledger']])}
      <div class="grid stats">${stat('Transactions',number(analytics.transactions),'Lifetime station sales')}${stat('Average sale',money(analytics.average_transaction),'Average transaction')}${stat('Wholesale',`${number(adv.wholesaleMultiplier || state.wholesaleMultiplier || 1,2)}×`,'Network wholesale market')}${stat('Maintenance',`${number(stationAdv.maintenance || 100,1)}%`,'Pump and charger condition')}</div>
      <div class="grid two" style="margin-top:12px">
        <article class="card"><div class="section-title"><h2>Supplier contract</h2><span>${esc(stationAdv.supplier_id || 'localfuel')}</span></div>
          <label class="form-label">Supplier</label><select class="text-input" id="supplier"><option value="localfuel">Local Fuel Distribution</option><option value="budget">Budget Petro Logistics</option><option value="premium">Premium Energy Logistics</option></select>
          <button class="primary wide" id="save-supplier">Save supplier</button><label class="form-label" style="margin-top:12px">Promotion off per litre</label><input class="text-input" id="promotion" type="number" min="0" max="1" step="0.01" value="${number(stationAdv.promotion_per_litre || 0,2)}"/><button class="secondary wide" id="save-promotion">Save promotion</button>
          <label class="form-label" style="margin-top:12px">NPC delivery amount</label><input class="text-input" id="npc-amount" type="number" min="500" step="250" value="1500"/>
          <button class="secondary wide" id="npc-delivery">Order automated delivery</button>
          <button class="secondary wide" id="repair-station">Service station equipment</button>
        </article>
        <article class="card"><div class="section-title"><h2>Station upgrades</h2><span>Permanent</span></div>
          <div class="action-list">${[['storage','Storage',level('storage_level')],['pumps','Pumps',level('pump_level')],['chargers','EV chargers',level('charger_level')],['security','Security',level('security_level')],['tanker','Tanker capacity',level('tanker_level')]].map(([id,label,lvl])=>`<div class="action"><div class="action-copy"><strong>${label}</strong><small>Current level ${lvl}</small></div><button class="secondary upgrade-button" data-upgrade="${id}">Upgrade</button></div>`).join('')}</div>
        </article>
      </div>
      <div class="grid two" style="margin-top:12px">
        <article class="card"><div class="section-title"><h2>Employees</h2><span>${employees.length}</span></div>${employees.length ? employees.map(e=>`<div class="transaction"><div><strong>${esc(e.name || e.identifier)}</strong><small>${esc(e.role || 'employee')}</small></div><button class="danger remove-employee" data-identifier="${esc(e.identifier)}">Remove</button></div>`).join('') : '<div class="empty">No station employees.</div>'}<button class="secondary wide" id="add-employee">Add employee</button></article>
        <article class="card"><div class="section-title"><h2>Fuel mix</h2><span>Analytics</span></div>${breakdown.length ? breakdown.map(row=>`<div class="summary-row"><span>${esc(String(row.transaction_type || '').replace(/_/g,' '))}</span><strong>${number(row.volume,1)} · ${money(row.revenue)}</strong></div>`).join('') : '<div class="empty">No fuel analytics yet.</div>'}</article>
      </div>`;
  }

  function ledgerView() {
    const rows = Array.isArray(state.transactions) ? state.transactions : [];
    return `${pageHeader(state.label || 'Fuel station','Latest station transactions and operational records','Live ledger')}${tabs([['overview','Overview'],['refuel','Refuel'],['operations','Operations'],['advanced','Advanced'],['ledger','Ledger']])}<article class="card"><div class="section-title"><h2>Recent transactions</h2><span>${rows.length} records</span></div><div class="transactions">${rows.length ? rows.map((row) => `<div class="transaction"><div><strong>${esc(String(row.transaction_type || 'transaction').replace(/_/g,' ').toUpperCase())}</strong><small>${esc(row.player_name || 'System')} · ${esc(row.created_at || '')}</small></div><span>${number(row.fuel_amount,1)} units</span><span class="amount">${money(row.amount_paid)}</span></div>`).join('') : '<div class="empty">No transactions have been recorded.</div>'}</div></article>`;
  }

  function adminView() {
    const totals = state.totals || {};
    const stations = Array.isArray(state.stations) ? state.stations : [];
    return `${pageHeader('Fuel network administration','Read-only operational overview across every configured station','Admin link')}<div class="grid stats">${stat('Transactions', number(totals.transactions), 'Network records')}${stat('Revenue', money(totals.revenue), 'Gross network sales')}${stat('Fuel moved', `${number(totals.fuel,1)}%`, 'Recorded volume')}${stat('Stations', number(stations.length), 'Configured locations')}</div><article class="card" style="margin-top:12px"><table class="station-table"><thead><tr><th>Station</th><th>Owner</th><th>Revenue</th><th>Stock</th><th>Price</th></tr></thead><tbody>${stations.map((station)=>`<tr><td>${esc(station.label)}</td><td>${esc(station.owner || 'Unowned')}</td><td>${money(station.totalSales)}</td><td>${number(station.stock,0)} / ${number(station.capacity,0)}</td><td>${number(station.priceMultiplier,2)}×</td></tr>`).join('')}</tbody></table></article>`;
  }

  function render() {
    modeLabel.textContent = mode === 'utility' ? (utility?.modeLabel || 'FuelOS tablet') : mode === 'admin' ? 'Network administration' : mode === 'station' ? 'Owner management tablet' : 'Fuel type selector';
    footerStation.textContent = mode === 'utility' ? String(utility?.footer || 'FUELOS').toUpperCase() : state.label ? String(state.label).toUpperCase() : 'CONNECTED';
    if (mode === 'utility') app.innerHTML = utilityView();
    else if (mode === 'admin') app.innerHTML = adminView();
    else if (mode === 'refuel') app.innerHTML = refuelView(true);
    else if (activeTab === 'refuel') app.innerHTML = `${pageHeader(state.label || 'Fuel station','Select a compatible fuel type, then use the physical pump','Fuel selector')}${tabs([['overview','Overview'],['refuel','Refuel'],['operations','Operations'],['advanced','Advanced'],['ledger','Ledger']])}${refuelView(false)}`;
    else if (activeTab === 'operations') app.innerHTML = operationsView();
    else if (activeTab === 'advanced') app.innerHTML = advancedView();
    else if (activeTab === 'ledger') app.innerHTML = ledgerView();
    else app.innerHTML = overviewView();
    bind();
  }

  function bind() {
    app.querySelectorAll('[data-utility-action]').forEach((button) => button.addEventListener('click', async () => {
      const action = button.dataset.utilityAction || 'submit';
      if (action === 'cancel' || action === 'close') {
        await post('utilityCancel');
        return;
      }
      button.disabled = true;
      const response = await post('utilitySubmit', {action, values:utilityValues()});
      if (response?.success === false) {
        button.disabled = false;
        toast(response.message || 'Unable to complete this action.', 'error');
      }
    }));
    app.querySelectorAll('[data-tab]').forEach((button) => button.addEventListener('click', () => {activeTab = button.dataset.tab; render();}));
    app.querySelectorAll('[data-fuel]').forEach((button) => button.addEventListener('click', () => {selectedFuel = button.dataset.fuel; render();}));
    document.getElementById('select-fuel')?.addEventListener('click', async (event) => {
      event.currentTarget.disabled = true;
      event.currentTarget.textContent = 'SELECTING…';
      const response = await post('selectFuelType',{stationId:state.id,fuelType:selectedFuel});
      if (response?.success) {
        event.currentTarget.textContent = `${String(response.fuelLabel || 'FUEL').toUpperCase()} SELECTED`;
        toast(response.message || 'Fuel type selected.','success');
      } else {
        toast(response?.message || 'Fuel selection failed.','error');
        render();
      }
    });
    document.getElementById('refresh-station')?.addEventListener('click', refreshStation);
    document.getElementById('save-multiplier')?.addEventListener('click', async () => {const response=await post('setMultiplier',{stationId:state.id,multiplier:Number(document.getElementById('multiplier').value)});toast(response?.message || (response?.success?'Pricing updated.':'Pricing update failed.'),response?.success?'success':'error');if(response?.success) refreshStation();});
    document.getElementById('withdraw')?.addEventListener('click', async () => {const response=await post('withdraw',{stationId:state.id});toast(response?.message || (response?.success?`Withdrew ${money(response.amount)}.`:'Withdrawal failed.'),response?.success?'success':'error');if(response?.success) refreshStation();});
    document.getElementById('buy-jerry')?.addEventListener('click', async () => {const response=await post('buyJerryCan',{stationId:state.id});toast(response?.message || (response?.success?'Jerry can purchased.':'Purchase failed.'),response?.success?'success':'error');});
    document.getElementById('start-delivery')?.addEventListener('click', async () => {const response=await post('startDelivery',{stationId:state.id});toast(response?.message || (response?.success?'Delivery started.':'Delivery failed.'),response?.success?'success':'error');});
    document.getElementById('start-robbery')?.addEventListener('click', async () => {const response=await post('startRobbery',{stationId:state.id});toast(response?.message || (response?.success?'Security event started.':'Action failed.'),response?.success?'success':'error');});
    document.getElementById('save-supplier')?.addEventListener('click', async () => {const response=await post('setSupplier',{stationId:state.id,supplierId:document.getElementById('supplier').value});toast(response?.message||'Supplier update failed.',response?.success?'success':'error');if(response?.success)refreshStation();});
    document.getElementById('save-promotion')?.addEventListener('click', async () => {const response=await post('setPromotion',{stationId:state.id,amount:Number(document.getElementById('promotion').value)});toast(response?.message||'Promotion update failed.',response?.success?'success':'error');if(response?.success)refreshStation();});
    document.getElementById('npc-delivery')?.addEventListener('click', async () => {const response=await post('orderNpcDelivery',{stationId:state.id,amount:Number(document.getElementById('npc-amount').value)});toast(response?.message||'Delivery order failed.',response?.success?'success':'error');});
    document.getElementById('repair-station')?.addEventListener('click', async () => {const response=await post('repairStation',{stationId:state.id});toast(response?.message||'Maintenance failed.',response?.success?'success':'error');if(response?.success)refreshStation();});
    app.querySelectorAll('.upgrade-button').forEach((button)=>button.addEventListener('click',async()=>{const response=await post('upgradeStation',{stationId:state.id,upgrade:button.dataset.upgrade});toast(response?.message||'Upgrade failed.',response?.success?'success':'error');if(response?.success)refreshStation();}));
    app.querySelectorAll('.remove-employee').forEach((button)=>button.addEventListener('click',async()=>{const response=await post('removeStationEmployee',{stationId:state.id,identifier:button.dataset.identifier});toast(response?.message||'Employee update failed.',response?.success?'success':'error');if(response?.success)refreshStation();}));
    document.getElementById('add-employee')?.addEventListener('click', openEmployeeModal);
  }
  async function refreshStation(showToast = true){const response=await post('refreshStation',{stationId:state.id});if(response?.success&&response.data){const vehicle=state.vehicle;state=response.data;if(vehicle)state.vehicle=vehicle;if(showToast)toast('Station data synchronised.','success');render();return true;}toast(response?.message||'Refresh failed.','error');return false;}
  function open(payload){mode=payload.mode||'refuel';utility=null;state=payload.data||{};activeTab='overview';const valid=fuelTypes().filter((fuel)=>(state.vehicle?.allowedFuelTypes||[]).includes(fuel.id));selectedFuel=valid[0]?.id||null;root.classList.add('visible');root.setAttribute('aria-hidden','false');render();}
  function openUtility(payload){mode='utility';utility=payload.data||{};state={};activeTab='overview';selectedFuel=null;closeEmployeeModal();root.classList.add('visible');root.setAttribute('aria-hidden','false');render();}
  window.addEventListener('message',(event)=>{const message=event.data||{};if(message.action==='open')open(message);if(message.action==='utilityOpen')openUtility(message);if(message.action==='reset'){closeEmployeeModal();utility=null;root.classList.remove('visible');root.setAttribute('aria-hidden','true');}});
  document.getElementById('close-button').addEventListener('click',close);
  document.addEventListener('keydown',(event)=>{if(event.key!=='Escape')return;if(employeeModal){closeEmployeeModal();return;}close();});
  setInterval(()=>{document.getElementById('clock').textContent=new Date().toLocaleTimeString('en-GB',{hour:'2-digit',minute:'2-digit'});},1000);
  document.getElementById('clock').textContent=new Date().toLocaleTimeString('en-GB',{hour:'2-digit',minute:'2-digit'});

  if (typeof GetParentResourceName !== 'function') {
    open({mode:'station',data:{id:'strawberry',label:'Strawberry Fuel',owner:'Techy',balance:18420,totalSales:78350,totalFuel:12642,priceMultiplier:1.05,stock:7420,capacity:10000,marketMultiplier:.96,jerryCanPrice:350,deliveriesEnabled:true,robberiesEnabled:true,vehicle:{label:'Benefactor Schafter V12',plate:'SARP 26',fuel:37.4,maxFuel:100,diesel:false,allowedFuelTypes:['petrol','premium']},fuelTypes:[{id:'petrol',label:'Petrol',description:'Regular unleaded for standard road vehicles.',unitPrice:1.92,accent:'#1ee8ef'},{id:'premium',label:'Premium',description:'High-octane unleaded for performance vehicles.',unitPrice:2.59,accent:'#a78bfa'},{id:'diesel',label:'Diesel',description:'Commercial diesel for configured heavy vehicles.',unitPrice:2.15,accent:'#f6b84c'}],transactions:[{transaction_type:'fuel_premium',player_name:'Alex Morgan',amount_paid:126,fuel_amount:48,created_at:'Today 00:41'},{transaction_type:'fuel_petrol',player_name:'Jamie Clark',amount_paid:82,fuel_amount:41,created_at:'Today 00:36'}]}});
  }
})();
