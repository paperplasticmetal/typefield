/* Local, network-free importer. It only creates new frames; existing nodes are untouched. */
function number(value, min, max) { return typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max; }
function shortText(value, max) { return typeof value === 'string' && value.length <= max; }
function utf8Bytes(value) {
  let bytes = 0;
  for (let i = 0; i < value.length; i++) {
    const unit = value.charCodeAt(i);
    if (unit < 0x80) bytes++;
    else if (unit < 0x800) bytes += 2;
    else if (unit >= 0xd800 && unit <= 0xdbff && i + 1 < value.length && value.charCodeAt(i + 1) >= 0xdc00 && value.charCodeAt(i + 1) <= 0xdfff) { bytes += 4; i++; }
    else bytes += 3;
  }
  return bytes;
}
function tags(value, min, max) {
  if (value === undefined) return true;
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const entries = Object.entries(value);
  return entries.length <= 32 && entries.every(([tag, setting]) => /^[A-Za-z0-9]{4}$/.test(tag) && number(setting, min, max));
}
function paint(c) {
  if (!c || !['r', 'g', 'b', 'a'].every(key => number(c[key], 0, 1))) throw Error('Invalid color.');
  return [{ type: 'SOLID', color: { r: c.r, g: c.g, b: c.b }, opacity: c.a }];
}
function validate(data) {
  if (!data || data.format !== 'fontshelf-figma' || data.version !== 1 || !shortText(data.name, 256) || !Array.isArray(data.frames) || !data.frames.length || data.frames.length > 30) throw Error('Unsupported Typefield layout.');
  if (data.warnings !== undefined && (!Array.isArray(data.warnings) || data.warnings.length > 100 || !data.warnings.every(warning => shortText(warning, 1024)))) throw Error('Invalid import notes.');
  let totalLayers = 0, totalText = 0;
  for (const frame of data.frames) {
    if (!frame || !number(frame.width, 1, 10000) || !number(frame.height, 1, 100000) || !shortText(frame.name, 256) || !Array.isArray(frame.elements) || frame.elements.length > 5000) throw Error('Invalid frame.');
    totalLayers += frame.elements.length;
    if (totalLayers > 50000) throw Error('The layout has too many layers.');
    paint(frame.paper);
    for (const e of frame.elements) {
      if (!e || !shortText(e.section, 256) || (e.name !== undefined && !shortText(e.name, 256)) || (e.role !== undefined && !shortText(e.role, 256))) throw Error('Invalid layer name.');
      if (!['x', 'y'].every(k => number(e[k], 0, 100000)) || !['width', 'height'].every(k => number(e[k], 1, 100000))) throw Error('Invalid layer bounds.');
      paint(e.color);
      if (e.kind === 'text') {
        if (e.stroke !== undefined || e.strokeWidth !== undefined) throw Error('Text strokes are not supported.');
        if (!shortText(e.text, 200000) || !shortText(e.fontFamily, 256) || !shortText(e.fontStyle, 256) || (e.fontName !== undefined && !shortText(e.fontName, 256)) || !number(e.fontSize, 1, 1000) || !number(e.lineHeight, 1, 2000) || !number(e.letterSpacing, -100, 100) || !number(e.paragraphSpacing, 0, 1000) || !number(e.paragraphIndent, 0, 1000) || !['LEFT', 'CENTER', 'RIGHT', 'JUSTIFIED'].includes(e.alignment) || (e.wordSpacing !== undefined && !number(e.wordSpacing, -1000, 1000)) || !tags(e.axes, -10000, 10000) || !tags(e.features, -1, 1000) || ['kerning', 'underline', 'strikethrough'].some(key => e[key] !== undefined && typeof e[key] !== 'boolean')) throw Error('Invalid text layer.');
        const textBytes = utf8Bytes(e.text);
        if (textBytes > 200000) throw Error('Invalid text layer.');
        totalText += textBytes;
        if (totalText > 5000000) throw Error('The layout contains too much text.');
      } else if (e.kind !== 'rectangle' || !number(e.radius, 0, 10000)) throw Error('Invalid shape.');
      if (e.kind === 'rectangle' && (e.stroke !== undefined || e.strokeWidth !== undefined)) {
        if (e.stroke === undefined || !number(e.strokeWidth, 0, 1000)) throw Error('Invalid shape stroke.');
        paint(e.stroke);
      }
    }
  }
}
async function importLayout(data, api) {
  validate(data);
  const created = [], warnings = new Set(data.warnings || []), loaded = new Map();
  let x = api.viewport.center.x;
  try {
    for (const layout of data.frames) {
      const frame = api.createFrame(); created.push(frame);
      frame.name = data.name + ' / ' + layout.name; frame.resize(layout.width, layout.height);
      frame.x = x; frame.y = api.viewport.center.y; frame.fills = paint(layout.paper); frame.clipsContent = false;
      for (const e of layout.elements) {
        let node;
        if (e.kind === 'text') {
          const key = e.fontFamily + '\n' + e.fontStyle;
          if (!loaded.has(key)) {
            let font = { family: e.fontFamily, style: e.fontStyle };
            try { await api.loadFontAsync(font); }
            catch (_) { warnings.add('Missing font: ' + e.fontFamily + ' ' + e.fontStyle + ' → Inter Regular'); font = { family: 'Inter', style: 'Regular' }; await api.loadFontAsync(font); }
            loaded.set(key, font);
          }
          node = api.createText(); frame.appendChild(node);
          node.fontName = loaded.get(key);
          if (e.axes && Object.keys(e.axes).length && node.fontName.family === e.fontFamily) {
            try { node.fontName = { ...loaded.get(key), variationSettings: e.axes }; }
            catch (_) { warnings.add('Variable axes need manual review: ' + e.fontFamily); }
          }
          node.fontSize = e.fontSize; node.characters = e.text;
          node.lineHeight = { value: e.lineHeight, unit: 'PIXELS' };
          node.letterSpacing = { value: e.letterSpacing, unit: 'PIXELS' };
          node.paragraphSpacing = e.paragraphSpacing; node.paragraphIndent = e.paragraphIndent;
          node.textAlignHorizontal = e.alignment;
          node.textDecoration = e.underline ? 'UNDERLINE' : e.strikethrough ? 'STRIKETHROUGH' : 'NONE';
          node.resize(e.width, e.height); node.textAutoResize = 'HEIGHT';
          if (e.wordSpacing || e.kerning === false || (e.features && Object.keys(e.features).length) || (e.underline && e.strikethrough)) warnings.add('Review word spacing, kerning, OpenType or combined decorations in Figma; these settings are retained as layer metadata.');
          // Shared, namespaced metadata also works for an unpublished local manifest without an ID.
          node.setSharedPluginData('fontshelf', 'typography', JSON.stringify({ fontName: e.fontName, axes: e.axes, features: e.features, wordSpacing: e.wordSpacing, kerning: e.kerning, underline: e.underline, strikethrough: e.strikethrough }));
        } else {
          node = api.createRectangle(); frame.appendChild(node); node.resize(e.width, e.height); node.cornerRadius = e.radius;
          node.strokes = e.strokeWidth > 0 ? paint(e.stroke) : [];
          node.strokeWeight = e.strokeWidth || 0;
          node.strokeAlign = 'CENTER';
        }
        node.name = e.section + (e.role ? ' / ' + e.role : ' / Shape'); node.x = e.x; node.y = e.y; node.fills = paint(e.color);
      }
      x += layout.width + 80;
    }
    api.currentPage.selection = created; api.viewport.scrollAndZoomIntoView(created);
    return 'Imported ' + created.length + ' editable frames.' + (warnings.size ? '\n\n' + [...warnings].join('\n') : '\nCheck line breaks before final handoff; Figma and macOS use different text renderers.');
  } catch (error) { for (const node of created) { if (!node.removed) node.remove(); } throw error; }
}
function exportSelection(api) {
  const selected = api.currentPage.selection.filter(n => n.type === 'FRAME' || n.type === 'COMPONENT');
  if (!selected.length || selected.length > 30) throw Error('Select between 1 and 30 frames in Figma first.');
  const warnings = new Set();
  function solid(node, opacity) {
    const fills = Array.isArray(node.fills) ? node.fills.filter(p => p.visible !== false) : [];
    const paint = fills.find(p => p.type === 'SOLID');
    if (fills.some(p => p.type !== 'SOLID') || fills.length > 1) warnings.add(node.name + ': gradients, images and extra fills are omitted.');
    return paint ? { ...paint.color, a: opacity * (paint.opacity === undefined ? 1 : paint.opacity) } : null;
  }
  function solidStroke(node, opacity) {
    const strokes = Array.isArray(node.strokes) ? node.strokes.filter(p => p.visible !== false) : [];
    const paint = strokes.find(p => p.type === 'SOLID');
    if (strokes.some(p => p.type !== 'SOLID') || strokes.length > 1) warnings.add(node.name + ': complex or extra strokes are omitted.');
    if (!paint) return null;
    if (!number(node.strokeWeight, 0, 1000)) { warnings.add(node.name + ': unsupported stroke width was omitted.'); return null; }
    if (node.strokeAlign && node.strokeAlign !== 'CENTER') warnings.add(node.name + ': stroke alignment was converted to center.');
    if (Array.isArray(node.dashPattern) && node.dashPattern.length) warnings.add(node.name + ': stroke dashes were converted to a solid line.');
    return { color: { ...paint.color, a: opacity * (paint.opacity === undefined ? 1 : paint.opacity) }, width: node.strokeWeight };
  }
  const frames = selected.map(root => {
    if (!number(root.width, 1, 10000) || !number(root.height, 1, 100000)) throw Error('Frame "' + root.name + '" exceeds Typefield limits: width must be 1–10,000 px and height must be 1–100,000 px. Resize the frame or export a smaller selection.');
    const elements = [], origin = root.absoluteTransform;
    if (Math.abs(origin[0][1]) > .001 || Math.abs(origin[1][0]) > .001) throw Error('Unrotate the selected frame before exporting: ' + root.name);
    function visit(node, parentOpacity) {
      if (node.visible === false) return;
      const opacity = parentOpacity * (node.opacity === undefined ? 1 : node.opacity), t = node.absoluteTransform;
      if (node.isMask) { warnings.add(node.name + ': masks are omitted.'); return; }
      if (Math.abs(t[0][1]) > .001 || Math.abs(t[1][0]) > .001) { warnings.add(node.name + ': rotated layers are omitted.'); return; }
      if ((node.effects || []).some(e => e.visible !== false)) warnings.add(node.name + ': effects are omitted.');
      if (node.layoutMode && node.layoutMode !== 'NONE') warnings.add(node.name + ': auto layout is captured as fixed positions.');
      const color = solid(node, opacity);
      const base = { name: node.name, section: node.name, x: t[0][2] - origin[0][2], y: t[1][2] - origin[1][2], width: Math.max(.01, node.width), height: Math.max(.01, node.height), color };
      if (base.x < 0 || base.y < 0) { warnings.add(node.name + ': layers outside the top or left of the frame are omitted.'); return; }
      if (node.type === 'TEXT') {
        if (Array.isArray(node.strokes) && node.strokes.some(p => p.visible !== false)) warnings.add(node.name + ': text strokes are omitted.');
        if (!node.characters || !color) { if (node.characters) warnings.add(node.name + ': text without a solid fill is omitted.'); return; }
        const font = node.fontName === api.mixed ? node.getRangeFontName(0, 1) : node.fontName;
        const size = node.fontSize === api.mixed ? node.getRangeFontSize(0, 1) : node.fontSize;
        const line = node.lineHeight === api.mixed ? node.getRangeLineHeight(0, 1) : node.lineHeight;
        const spacing = node.letterSpacing === api.mixed ? node.getRangeLetterSpacing(0, 1) : node.letterSpacing;
        if ([node.fontName, node.fontSize, node.lineHeight, node.letterSpacing, node.fills, node.textCase, node.textDecoration].some(v => v === api.mixed)) warnings.add(node.name + ': mixed text styling uses its first text style.');
        if (node.textAlignVertical && node.textAlignVertical !== 'TOP') warnings.add(node.name + ': vertical alignment uses top alignment.');
        let text = node.characters;
        if (node.textCase === 'UPPER') text = text.toUpperCase(); else if (node.textCase === 'LOWER') text = text.toLowerCase();
        else if (node.textCase && node.textCase !== 'ORIGINAL') warnings.add(node.name + ': text case needs review.');
        elements.push({ ...base, kind: 'text', text, fontFamily: font.family, fontStyle: font.style, fontSize: size,
          lineHeight: line.unit === 'PIXELS' ? line.value : line.unit === 'PERCENT' ? size * line.value / 100 : size * 1.35,
          letterSpacing: spacing.unit === 'PERCENT' ? size * spacing.value / 100 : spacing.value,
          paragraphSpacing: typeof node.paragraphSpacing === 'number' ? node.paragraphSpacing : 0,
          paragraphIndent: typeof node.paragraphIndent === 'number' ? node.paragraphIndent : 0,
          alignment: node.textAlignHorizontal, underline: node.textDecoration === 'UNDERLINE', strikethrough: node.textDecoration === 'STRIKETHROUGH', axes: font.variationSettings || {}, features: {}, kerning: true });
      } else if (node.type === 'RECTANGLE' || ['FRAME', 'COMPONENT', 'INSTANCE', 'GROUP'].includes(node.type)) {
        const stroke = solidStroke(node, opacity);
        if (color || stroke) elements.push({ ...base, color: color || { r: 0, g: 0, b: 0, a: 0 }, kind: 'rectangle', radius: typeof node.cornerRadius === 'number' ? node.cornerRadius : 0, ...(stroke ? { stroke: stroke.color, strokeWidth: stroke.width } : {}) });
        if (node.type === 'INSTANCE' || node.type === 'COMPONENT') warnings.add(node.name + ': component is imported as independent editable layers.');
        if (node.clipsContent) warnings.add(node.name + ': nested clipping needs review.');
        for (const child of node.children || []) visit(child, opacity);
      } else { warnings.add(node.name + ': ' + node.type.toLowerCase() + ' is not supported yet.'); }
      if (elements.length > 5000) throw Error('A frame exceeds the 5,000-layer limit. Export a smaller selection.');
    }
    if (root.layoutMode && root.layoutMode !== 'NONE') warnings.add(root.name + ': auto layout is captured as fixed positions.');
    for (const child of root.children) visit(child, root.opacity === undefined ? 1 : root.opacity);
    return { name: root.name, width: root.width, height: root.height, paper: solid(root, 1) || { r: 1, g: 1, b: 1, a: 1 }, elements };
  });
  return { format: 'fontshelf-figma', version: 1, name: api.root.name, frames, warnings: [...warnings] };
}
if (typeof figma !== 'undefined') {
  figma.showUI(__html__, { width: 460, height: 560 });
  let busy = false;
  figma.ui.onmessage = async message => {
    if (!message || busy) return;
    if (message.type === 'export') {
      try { figma.ui.postMessage({ type: 'export', payload: exportSelection(figma) }); }
      catch (error) { figma.ui.postMessage({ type: 'result', message: error.message }); }
      return;
    }
    if (message.type !== 'import') return;
    busy = true;
    try { figma.ui.postMessage({ type: 'result', message: await importLayout(message.payload, figma) }); }
    catch (error) { figma.ui.postMessage({ type: 'result', message: 'Import failed; new frames removed. ' + error.message }); }
    finally { busy = false; }
  };
}
if (typeof module !== 'undefined') module.exports = { validate, importLayout, exportSelection };
