// Verificacion funcional del build web en Chrome headless.
// Requiere: npm i playwright-core (los navegadores ya estan en %LOCALAPPDATA%/ms-playwright)
// Uso:  node tools/verify_web.js            (usa http://127.0.0.1:8060/)
//       node tools/verify_web.js http://otro/
//
// El juego expone window.__rito desde GDScript (scripts/player/rito.gd). Se mide el
// FPS del build nativo con tools/bench.tscn: aqui SwiftShader renderiza por software,
// asi que el FPS del navegador NO es representativo de la GPU real.

const { chromium } = require('playwright-core');

const URL = process.argv[2] || 'http://127.0.0.1:8060/index.html';
const OUT = __dirname + '/../build/web';

(async () => {
  const browser = await chromium.launch({
    executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    headless: true,
    args: [
      '--use-gl=angle',
      '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader',
      '--ignore-gpu-blocklist',
      '--disable-gpu-sandbox',
    ],
  });
  const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
  page.setDefaultTimeout(180000);
  const errors = [];
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push('console.error: ' + m.text());
  });
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));

  console.log('NAVIGATING', URL);
  await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 120000 });

  let ready = false;
  for (let i = 0; i < 60; i++) {
    await page.waitForTimeout(2000);
    const state = await page.evaluate(() => (window.__rito && window.__rito.ready ? { ...window.__rito } : null));
    if (state) {
      console.log('READY after', (i + 1) * 2, 's', JSON.stringify(state));
      ready = true;
      break;
    }
  }
  if (!ready) {
    console.log('FAIL: el juego no quedo listo');
    console.log('ERRORS', JSON.stringify(errors.slice(0, 10)));
    await browser.close();
    process.exit(1);
  }

  const before = await page.evaluate(() => ({ ...window.__rito }));
  await page.click('#canvas', { position: { x: 480, y: 300 } }).catch(() => {});
  await page.waitForTimeout(1000);
  await page.keyboard.down('w');
  let moved = 0;
  for (let i = 0; i < 20; i++) {
    await page.waitForTimeout(1500);
    const state = await page.evaluate(() => ({ ...window.__rito }));
    moved = Math.hypot(state.x - before.x, state.z - before.z);
    if (moved > 3) break;
  }
  await page.keyboard.up('w');
  await page.waitForTimeout(1500);

  const after = await page.evaluate(() => ({ ...window.__rito }));

  // Combate a traves del puente JS. Se comprueba el estado y el cambio de arma, no el
  // resultado de un golpe: bajo SwiftShader el juego va a 1-2 FPS y ningun NPC alcanza a
  // Rito en la ventana de la prueba. El golpe ya lo cubre tools/combat_test.gd en nativo.
  const combat = await page.evaluate(() => ({ ...window.__rito }));
  await page.keyboard.press('2');
  await page.waitForTimeout(1500);
  const pilum = await page.evaluate(() => ({ ...window.__rito }));
  await page.keyboard.press('3');
  await page.waitForTimeout(1500);
  const spatha = await page.evaluate(() => ({ ...window.__rito }));
  await page.keyboard.press('1');
  await page.waitForTimeout(1500);
  const back = await page.evaluate(() => ({ ...window.__rito }));

  // El menu de arsenal: se abre con B (Tab lo puede robar el navegador) y debe
  // aparecer en el puente.
  await page.keyboard.press('b');
  await page.waitForTimeout(1500);
  const arsenal = await page.evaluate(() => ({ ...window.__rito }));
  await page.keyboard.press('b');
  await page.waitForTimeout(1000);

  const errorsBeforeAttack = errors.length;
  await page.mouse.down({ button: 'left' });
  await page.mouse.up({ button: 'left' });
  await page.waitForTimeout(2000);
  const attacked = await page.evaluate(() => ({ ...window.__rito }));

  await page.screenshot({ path: OUT + '/verify-web.png', timeout: 180000, animations: 'disabled' });

  const distance = Math.hypot(after.x - before.x, after.y - before.y, after.z - before.z);
  const checks = [
    ['movimiento', distance > 1],
    ['hp presente y llena', typeof combat.hp === 'number' && combat.hp === 100],
    ['alive true', combat.alive === true],
    ['arma inicial gladius', combat.weapon === 0],
    ['tecla 2 cambia a pilum', pilum.weapon === 1 && pilum.weapon_name === 'Pilum'],
    ['tecla 3 cambia a spatha', spatha.weapon === 2 && spatha.weapon_name === 'Spatha'],
    ['tecla 1 vuelve al gladius', back.weapon === 0],
    ['kills presente', typeof combat.kills === 'number'],
    ['el menu de arsenal se abre', arsenal.arsenal === 1],
    ['el moloso esta cerca', typeof arsenal.dog_dist === 'number' && arsenal.dog_dist < 20],
    ['clic en atacar no rompe', errors.length === errorsBeforeAttack],
    ['sigue vivo tras atacar', attacked.alive === true],
    ['xp presente', typeof combat.xp === 'number' && combat.xp >= 0],
    ['nivel presente', typeof combat.level === 'number' && combat.level >= 1],
    ['denarios y mision', typeof combat.coins === 'number' && combat.coins >= 0 && typeof combat.mission === 'string' && (combat.mission === '' || ['bandit_purge', 'city_defense', 'world_event'].includes(combat.mission))],
  ];
  for (const [name, ok] of checks) console.log('CHECK', name, ok ? 'ok' : 'FALLA');

  console.log('BEFORE', JSON.stringify(before));
  console.log('AFTER ', JSON.stringify(after));
  console.log('DISTANCE', distance.toFixed(2), 'm');
  const failed = checks.filter(([, ok]) => !ok).map(([name]) => name);
  console.log('RESULT', failed.length === 0 ? 'PASS' : 'FAIL ' + failed.join(', '));
  console.log('ERRORS', JSON.stringify(errors.slice(0, 8)));
  await browser.close();
  process.exit(failed.length === 0 ? 0 : 1);
})();
