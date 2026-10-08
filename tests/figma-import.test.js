const assert = require('node:assert/strict');
const fs = require('node:fs');
const { validate, importLayout, exportSelection } = require('../Resources/FigmaImport/code.js');
assert.equal(require('../Resources/FigmaImport/manifest.json').name, 'Typefield Layout Importer');
const pluginUI = fs.readFileSync(require.resolve('../Resources/FigmaImport/ui.html'), 'utf8');
assert.match(pluginUI, /layout\.typefield\.json/);
assert.match(pluginUI, /Figma-typeboard\.typefield\.json/);
const black = { r: 0, g: 0, b: 0, a: 1 };
function fixture() { return { format: 'fontshelf-figma', version: 1, name: 'Client', frames: [{ name: 'A', width: 390, height: 800, paper: black, elements: [{ kind: 'text', section: 'Hero', role: 'Display', x: 24, y: 24, width: 342, height: 140, text: 'Editable text', fontFamily: 'Georgia', fontStyle: 'Regular', fontSize: 64, lineHeight: 80, letterSpacing: 1, paragraphSpacing: 12, paragraphIndent: 0, alignment: 'CENTER', color: black, axes: {}, features: {}, kerning: true }] }] }; }
function mock(failFont = false, failText = false) {
  const frames = [];
  function node() { return { children: [], removed: false, resize(w, h) { this.width = w; this.height = h; }, appendChild(n) { this.children.push(n); }, remove() { this.removed = true; }, setPluginData() { throw Error('Private metadata requires a registered plugin ID'); }, setSharedPluginData(ns, k, v) { this[ns + '/' + k] = v; } }; }
  return { frames, currentPage: { selection: [] }, viewport: { center: { x: 0, y: 0 }, scrollAndZoomIntoView() {} }, createFrame() { const n = node(); frames.push(n); return n; }, createText() { if (failText) throw Error('simulated creation failure'); return node(); }, createRectangle: node, async loadFontAsync(font) { if (failFont && font.family !== 'Inter') throw Error('missing font'); } };
}
(async () => {
  const mirrored = fixture(); mirrored.frames[0].elements[0].flipX = true;
  const mirroredAPI = mock(); await importLayout(mirrored, mirroredAPI);
  assert.deepEqual(mirroredAPI.frames[0].children[0].relativeTransform, [[-1,0,366],[0,1,24]]);
  mirrored.frames[0].elements[0].flipX = 'yes'; assert.throws(() => validate(mirrored), /reflection/);
  const data = fixture(); validate(data);
  const api = mock(); const result = await importLayout(data, api);
  assert.match(result, /1 editable frames/); assert.equal(api.frames[0].children[0].characters, 'Editable text'); assert.equal(api.frames[0].children[0].textAlignHorizontal, 'CENTER'); assert.equal(api.frames[0].children[0].lineHeight.value, 80); assert.equal(api.currentPage.selection.length, 1);
  assert.equal(api.frames[0].children[0].textAutoResize, 'HEIGHT');
  assert.equal(JSON.parse(api.frames[0].children[0]['fontshelf/typography']).kerning, true);
  const missing = mock(true); assert.match(await importLayout(data, missing), /Missing font/); assert.equal(missing.frames[0].children[0].fontName.family, 'Inter');
  const failing = mock(false, true); await assert.rejects(importLayout(data, failing), /simulated/); assert(failing.frames.every(f => f.removed));
  const invalid = fixture(); invalid.frames[0].elements[0].width = -1; const clean = mock(); await assert.rejects(importLayout(invalid, clean), /bounds/); assert.equal(clean.frames.length, 0);
  const badName = fixture(); badName.frames[0].elements[0].section = { unexpected: 'object' }; assert.throws(() => validate(badName), /layer name/);
  const badAxes = fixture(); badAxes.frames[0].elements[0].axes = JSON.parse('{"__proto__":100}'); assert.throws(() => validate(badAxes), /text layer/);
  const largeUnicodeText = fixture(); largeUnicodeText.frames[0].elements[0].text = '👋'.repeat(50001); assert.throws(() => validate(largeUnicodeText), /text layer/);
  const excessiveText = fixture(); excessiveText.frames[0].elements = Array.from({ length: 26 }, () => ({ ...fixture().frames[0].elements[0], text: 'A'.repeat(200000) })); assert.throws(() => validate(excessiveText), /too much text/);
  const warn = fixture(); warn.frames[0].elements[0].wordSpacing = 3; assert.match(await importLayout(warn, mock()), /manual|Review/);
  warn.warnings = ['Spaces image artwork is omitted from editable Figma export.'];
  assert.match(await importLayout(warn, mock()), /Spaces image artwork is omitted/);
  const outlined = fixture(); outlined.frames[0].elements.push({ kind: 'rectangle', section: 'Card', x: 10, y: 180, width: 200, height: 100,
    color: { r: 0, g: 0, b: 0, a: 0 }, radius: 8, stroke: { r: .2, g: .3, b: .4, a: .75 }, strokeWidth: 4 });
  const outlinedApi = mock(); await importLayout(outlined, outlinedApi);
  assert.equal(outlinedApi.frames[0].children[1].strokeWeight, 4);
  assert.equal(outlinedApi.frames[0].children[1].strokes[0].opacity, .75);
  const badStroke = fixture(); badStroke.frames[0].elements.push({ ...outlined.frames[0].elements[1], strokeWidth: Infinity });
  assert.throws(() => validate(badStroke), /stroke/);
  badStroke.frames[0].elements[1].strokeWidth = 4; badStroke.frames[0].elements[1].stroke.a = 2;
  assert.throws(() => validate(badStroke), /color/);
  const solid = [{ type: 'SOLID', color: { r: .2, g: .3, b: .4 }, opacity: 1 }];
  const text = { type: 'TEXT', name: 'Headline', width: 300, height: 90, absoluteTransform: [[1,0,140],[0,1,260]], characters: 'From Figma', fontName: { family: 'Georgia', style: 'Regular' }, fontSize: 72, lineHeight: { unit: 'PIXELS', value: 100 }, letterSpacing: { unit: 'PIXELS', value: 2 }, textAlignHorizontal: 'CENTER', fills: solid, textCase: 'ORIGINAL' };
  const outlinedShape = { type: 'RECTANGLE', name: 'Border', width: 200, height: 100, absoluteTransform: [[1,0,130],[0,1,420]], fills: [], strokes: [{ type: 'SOLID', color: { r: .2, g: .3, b: .4 }, opacity: .75 }], strokeWeight: 4, cornerRadius: 8 };
  const frame = { type: 'FRAME', name: 'Website', width: 960, height: 800, absoluteTransform: [[1,0,100],[0,1,200]], fills: solid, children: [text, outlinedShape, { type: 'VECTOR', name: 'Logo', width: 10, height: 10, absoluteTransform: [[1,0,110],[0,1,220]], fills: solid }] };
  const reverse = exportSelection({ root: { name: 'Round trip' }, currentPage: { selection: [frame] }, mixed: Symbol('mixed') });
  assert.equal(reverse.frames[0].elements[0].x, 40); assert.equal(reverse.frames[0].elements[0].y, 60);
  assert.equal(reverse.frames[0].elements[0].fontSize, 72); assert.match(reverse.warnings.join(' '), /Logo.*not supported/);
  assert.equal(reverse.frames[0].elements[1].strokeWidth, 4);
  assert.equal(reverse.frames[0].elements[1].stroke.a, .75);
  assert.equal(reverse.frames[0].elements[1].color.a, 0);
  const mirrorReturn = exportSelection({ root: { name: 'Mirror' }, currentPage: { selection: [{ ...frame, children: [{ ...text, absoluteTransform: [[-1,0,440],[0,-1,350]] }] }] }, mixed: Symbol('mixed') });
  assert.equal(mirrorReturn.frames[0].elements[0].x, 40); assert.equal(mirrorReturn.frames[0].elements[0].y, 60);
  assert.equal(mirrorReturn.frames[0].elements[0].flipX, true); assert.equal(mirrorReturn.frames[0].elements[0].flipY, true);
  const oversized = { ...frame, name: 'Too wide', width: 10001 };
  assert.throws(() => exportSelection({ root: { name: 'Round trip' }, currentPage: { selection: [oversized] }, mixed: Symbol('mixed') }), /10,000/);
  assert.throws(() => exportSelection({ currentPage: { selection: [] } }), /Select/);
  console.log('PASS: editable layers, typography, missing-font fallback, validation and rollback. Figma API mocked; live editor validation remains separate.');
})().catch(error => { console.error(error); process.exitCode = 1; });
