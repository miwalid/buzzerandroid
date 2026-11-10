(() => {
  const config = window.BUZZER_CONFIG;
  const native = window.Native;
  let session;
  let timer;
  let lastState;
  let requests = 0;
  let received = 0;

  const messages = {
    room: 'الغرفة غير موجودة أو انتهت صلاحيتها',
    name: 'اكتب اسمًا من 1 إلى 30 حرفًا',
    full: 'الغرفة ممتلئة',
    credential: 'انقطع اتصالك بالغرفة',
    network: 'تعذّر الاتصال بالخادم. تحقّق من الإنترنت.',
    config: 'اللعب عبر الإنترنت غير متاح حاليًا'
  };

  function deliver(event, value) {
    window.fromNative(event, value);
  }

  async function rpc(action, current, fields = {}) {
    if (!config?.url || !config.publishableKey) throw new Error('config');
    const response = await fetch(config.url.replace(/\/$/, '') + '/rest/v1/rpc/buzzer_play', {
      method: 'POST',
      headers: {apikey: config.publishableKey, 'Content-Type': 'application/json'},
      body: JSON.stringify({action, room_code: current.code, credential: current.token, ...fields}),
      signal: AbortSignal.timeout(6500)
    });
    if (!response.ok) throw new Error('network');
    const data = await response.json();
    if (data.error) throw new Error(data.error);
    return data;
  }

  function report(error) {
    deliver('error', messages[error.message] || messages.network);
  }

  function renderState(current, state, request) {
    const currentEpoch = lastState?.epoch ?? -1;
    if (session !== current || state.epoch < currentEpoch) return;
    if (state.epoch === currentEpoch && request < received) return;
    received = Math.max(request, received);
    lastState = state;
    deliver('state', state);
  }

  async function sync(current) {
    const request = ++requests;
    try {
      renderState(current, await rpc('state', current), request);
    } catch (error) {
      if (session !== current) return;
      if (error.message === 'room' || error.message === 'credential') {
        stop();
        report(error);
        return;
      }
      deliver('offline', messages.network);
    }
    if (session === current) timer = setTimeout(() => sync(current), 850);
  }

  async function enter(role, code, name) {
    try {
      const current = {role, code, token: crypto.randomUUID()};
      const state = await rpc(role === 'host' ? 'create' : 'join', current, {player_name: name});
      current.code = state.code;
      session = current;
      deliver(role, role === 'host' ? state.code : name);
      renderState(current, state, ++requests);
      timer = setTimeout(() => sync(current), 850);
    } catch (error) {
      report(error);
    }
  }

  function stop() {
    clearTimeout(timer);
    const current = session;
    session = undefined;
    lastState = undefined;
    if (current) rpc(current.role === 'host' ? 'close' : 'leave', current).catch(() => {});
  }

  async function command(action, epoch) {
    const current = session;
    if (!current) return;
    const request = ++requests;
    try {
      renderState(current, await rpc(action, current, {expected_epoch: epoch}), request);
    } catch {
      if (session === current) deliver('offline', messages.network);
    }
  }

  window.Online = {
    host: () => enter('host', null, null),
    join: (code, name) => enter('player', code.trim().toUpperCase(), name.trim()),
    scan: () => native.scan(),
    qr: code => native?.qr(code) || '',
    stop,
    command: action => command(action, lastState?.epoch),
    buzz: epoch => command('buzz', epoch)
  };
})();
