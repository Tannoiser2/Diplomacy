// Prova della pagina HTML per i telefoni: entra nella stanza come farebbe chi inquadra il QR, tratta,
// dà gli ordini e gioca qualche anno contro le IA di chi ospita (vedi tests/telefono_pagina.sh).
// Uso: node telefono_pagina.js <indirizzo della pagina> <file con il codice> <cartella per le foto>
const puppeteer = require('puppeteer-core');
const fs = require('fs');
const dormi = (ms) => new Promise((r) => setTimeout(r, ms));
(async () => {
  const [base, fileCodice, foto] = process.argv.slice(2);
  fs.mkdirSync(foto, { recursive: true });
  let codice = '';
  while (!codice) { if (fs.existsSync(fileCodice)) codice = fs.readFileSync(fileCodice, 'utf8').trim(); await dormi(300); }
  const browser = await puppeteer.launch({ executablePath: '/usr/bin/google-chrome', headless: 'new', args: ['--no-sandbox', '--no-proxy-server'] });
  const page = await browser.newPage();
  await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const errori = [];
  page.on('console', (m) => { if (m.type() === 'error') errori.push(m.text().slice(0, 200)); });
  page.on('pageerror', (e) => errori.push('PAGEERROR ' + String(e).slice(0, 300)));
  await page.goto(base + '&stanza=' + codice, { waitUntil: 'load' });
  const scatta = async (n) => { await dormi(350); await page.screenshot({ path: `${foto}/${n}.png` }); };
  const tocca = async (testo, esatto) => page.evaluate((t, es) => {
    const b = [...document.querySelectorAll('button')].filter((x) => x.offsetParent !== null && !x.disabled)
      .find((x) => es ? x.textContent.trim() === t : x.textContent.includes(t));
    if (b) { b.click(); return true; } return false;
  }, testo, !!esatto);
  const stato = () => page.evaluate(() => ({ passo: S.passo, titolo: S.pub ? S.pub.titolo : '', chiave: S.pub ? S.pub.chiave : '', finita: S.pub ? S.pub.finita : false,
    puo: typeof posso_ordinare === 'function' && !!S.pub && !!S.priv && posso_ordinare(), posta: S.priv ? S.priv.posta.length : 0, seq: S.seq, coda: S.coda.length }));
  const fallisci = async (perche) => { console.log('PAGINA FALLITA: ' + perche); console.log(JSON.stringify(await stato())); for (const e of errori.slice(0, 10)) console.log('  ', e); await scatta('zz_errore'); await browser.close(); process.exit(1); };

  await page.waitForSelector('#nome', { timeout: 20000 }).catch(() => fallisci('non compare la scelta della potenza'));
  await page.type('#nome', 'Stefano');
  await scatta('01_entra');
  if (!(await tocca('Italia'))) await fallisci('manca il posto dell\'Italia');
  await page.waitForFunction(() => S.passo === 'attesa' || S.passo === 'gioco', { timeout: 15000 }).catch(() => fallisci('non entra nella stanza'));
  await scatta('02_attesa');
  await page.waitForFunction(() => S.passo === 'gioco' && S.pub && S.priv, { timeout: 90000 }).catch(() => fallisci('la partita non parte'));
  // aspetta i primi dispacci delle IA
  await page.waitForFunction(() => S.priv.posta.length > 0, { timeout: 30000 }).catch(() => {});
  await scatta('03_quadro');
  await page.evaluate(() => { const m = S.priv.posta.find((x) => !x.mia); S.con = m ? m.con : 5; disegna(); });
  await scatta('04_conversazione');
  const accettato = await tocca('Accetta', true);
  await dormi(3500);
  await scatta('05_dopo_risposta');
  await page.evaluate(() => { S.con = 2; disegna(); });
  await tocca('Proponi pace', true); await scatta('06_proponi_pace');
  await tocca('Spedisci', true);
  await tocca('Altro dispaccio', true); await scatta('07_altro_dispaccio');
  await tocca('Zona sgombra'); await scatta('08_zona_sgombra');
  await tocca('Annulla', true);
  await page.waitForFunction(() => S.priv.posta.some((m) => m.mia && m.con === 2), { timeout: 15000 }).catch(() => fallisci('il dispaccio spedito non torna nella posta'));
  await dormi(1500);
  await scatta('09_conversazione_francia');
  await page.evaluate(() => { S.con = -1; S.scheda = 'ord'; disegna(); });
  await scatta('10_ordini');
  await tocca('Armata Venezia'); await scatta('11_che_cosa_fa');
  await tocca('Muove...', true); await scatta('12_dove_muove');
  await tocca('Trieste', true);
  await tocca('Armata Roma'); await tocca('Sostiene'); await scatta('13_chi_sostiene');
  await tocca('Armata Venezia (Italia)', true); await scatta('14_sostegno_dove');
  await tocca('che resta ferma', true);
  await scatta('15_ordini_dati');
  const bozza = await page.evaluate(() => JSON.stringify(S.bozza));
  if (!bozza.includes('"t":"muove in Trieste"') || !bozza.includes('sostiene Armata Venezia (Italia) che resta ferma')) await fallisci('gli ordini scelti non sono nella bozza: ' + bozza);
  await tocca('Consegna gli ordini', true);
  await page.waitForFunction(() => S.priv.consegnato || S.pub.chiave !== '1901-0-0', { timeout: 20000 }).catch(() => fallisci('gli ordini non arrivano a chi ospita'));
  await scatta('16_consegnati');
  // avanti: a ogni fase consegna (sciogliendo o costruendo quel che serve) fino al 1903
  const t0 = Date.now(); let fasi = new Set(); let fotoSit = false, fotoRit = false, fotoInv = false;
  for (;;) {
    const s = await stato();
    fasi.add(s.chiave);
    if (s.finita || /190[3-9]/.test(s.titolo)) break;
    if (Date.now() - t0 > 400000) await fallisci('tempo scaduto a ' + s.titolo);
    if (!fotoSit && fasi.size > 1) { fotoSit = true; await page.evaluate(() => { S.scheda = 'sit'; disegna(); }); await scatta('17_situazione'); }
    if (s.puo) {
      await page.evaluate(() => { S.scheda = 'ord'; disegna(); });
      const tipo = await page.evaluate(() => S.pub.tipo + (S.pub.tipo === 'agg' ? (S.priv.saldo > 0 ? '+' : '-') : ''));
      if (tipo === 'rit' && !fotoRit) { fotoRit = true; await scatta('18_ritirate'); }
      if (tipo === 'agg+') {
        if (!fotoInv) { fotoInv = true; await scatta('19_costruzioni'); }
        await page.evaluate(() => { let n = 0; for (const k of S.priv.case) if (n < S.priv.saldo) { S.bozza['c' + k.p] = { o: k.o[0][1], t: k.o[0][0] }; n++; } disegna(); });
      }
      if (tipo === 'agg-') await page.evaluate(() => { S.priv.scio.slice(0, -S.priv.saldo).forEach((x) => { S.bozza['s' + x[0]] = 1; }); disegna(); });
      await tocca('Consegna');
    }
    await dormi(1500);
  }
  await page.evaluate(() => { S.scheda = 'sit'; disegna(); });
  await scatta('20_situazione_finale');
  const fine = await stato();
  console.log(`PAGINA: ${fine.titolo}, fasi viste ${fasi.size}, dispacci ${fine.posta}, azioni spedite ${fine.seq}, proposta accettata ${accettato}, errori ${errori.length}`);
  for (const e of errori.slice(0, 10)) console.log('  ', e);
  await browser.close();
  console.log(errori.length === 0 && fasi.size >= 5 ? 'PAGINA TELEFONO OK' : 'PAGINA TELEFONO: CONTROLLARE');
  process.exit(errori.length === 0 && fasi.size >= 5 ? 0 : 1);
})();
