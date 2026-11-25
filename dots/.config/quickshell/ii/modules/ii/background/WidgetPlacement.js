.pragma library

function clamp(value, low, high) {
    if (!Number.isFinite(value)) return low;
    return Math.max(low, Math.min(high, value));
}

function monitorObstacles(windowList, monitorId, monitorX, monitorY, activeWorkspaceId) {
    if (!Array.isArray(windowList) || monitorId == null || monitorId < 0 || activeWorkspaceId == null || activeWorkspaceId < 0)
        return [];
    const mx = Number.isFinite(monitorX) ? monitorX : 0;
    const my = Number.isFinite(monitorY) ? monitorY : 0;
    const result = [];
    for (let i = 0; i < windowList.length; ++i) {
        const win = windowList[i];
        if (!win || win.mapped === false || win.hidden === true) continue;
        if (win.monitor !== monitorId) continue;
        if (!win.workspace || win.workspace.id !== activeWorkspaceId) continue;
        const at = win.at;
        const size = win.size;
        if (!at || !size || size[0] <= 0 || size[1] <= 0) continue;
        result.push({
            x: at[0] - mx,
            y: at[1] - my,
            width: size[0],
            height: size[1],
        });
    }
    return result;
}

function findMaxEmptyRect(bounds, obstacles, widgetW, widgetH, obstaclePad) {
    const x0 = bounds.x;
    const y0 = bounds.y;
    const x1 = bounds.x + bounds.width;
    const y1 = bounds.y + bounds.height;
    if (x1 - x0 < widgetW || y1 - y0 < widgetH) return null;

    const clipped = [];
    const xs = [x0, x1];
    const ys = [y0, y1];
    for (let i = 0; i < obstacles.length; ++i) {
        const rect = obstacles[i];
        if (!rect || rect.width <= 0 || rect.height <= 0) continue;
        const rx0 = Math.max(x0, rect.x - obstaclePad);
        const ry0 = Math.max(y0, rect.y - obstaclePad);
        const rx1 = Math.min(x1, rect.x + rect.width + obstaclePad);
        const ry1 = Math.min(y1, rect.y + rect.height + obstaclePad);
        if (rx1 <= rx0 || ry1 <= ry0) continue;
        clipped.push({ x0: rx0, y0: ry0, x1: rx1, y1: ry1 });
        xs.push(rx0, rx1);
        ys.push(ry0, ry1);
    }

    xs.sort((a, b) => a - b);
    ys.sort((a, b) => a - b);
    const ux = [];
    for (let i = 0; i < xs.length; ++i) {
        if (ux.length === 0 || xs[i] - ux[ux.length - 1] > 0.5) ux.push(xs[i]);
    }
    const uy = [];
    for (let i = 0; i < ys.length; ++i) {
        if (uy.length === 0 || ys[i] - uy[uy.length - 1] > 0.5) uy.push(ys[i]);
    }

    const cols = ux.length - 1;
    const rows = uy.length - 1;
    if (cols <= 0 || rows <= 0) return null;

    const blocked = new Array(rows);
    for (let r = 0; r < rows; ++r) {
        const row = new Array(cols);
        const cy = (uy[r] + uy[r + 1]) * 0.5;
        for (let c = 0; c < cols; ++c) {
            const cx = (ux[c] + ux[c + 1]) * 0.5;
            let hit = false;
            for (let k = 0; k < clipped.length; ++k) {
                const o = clipped[k];
                if (cx > o.x0 && cx < o.x1 && cy > o.y0 && cy < o.y1) {
                    hit = true;
                    break;
                }
            }
            row[c] = hit;
        }
        blocked[r] = row;
    }

    let best = null;
    let bestScore = -1;
    for (let rTop = 0; rTop < rows; ++rTop) {
        const colOpen = new Array(cols);
        for (let c = 0; c < cols; ++c) colOpen[c] = true;
        for (let rBot = rTop; rBot < rows; ++rBot) {
            const rectH = uy[rBot + 1] - uy[rTop];
            let anyOpen = false;
            for (let c = 0; c < cols; ++c) {
                if (blocked[rBot][c]) colOpen[c] = false;
                if (colOpen[c]) anyOpen = true;
            }
            if (!anyOpen) break;
            if (rectH < widgetH) continue;

            let cStart = -1;
            for (let c = 0; c <= cols; ++c) {
                if (c < cols && colOpen[c]) {
                    if (cStart < 0) cStart = c;
                } else if (cStart >= 0) {
                    const rectW = ux[c] - ux[cStart];
                    if (rectW >= widgetW) {
                        const area = rectW * rectH;
                        const clearance = Math.min(rectW - widgetW, rectH - widgetH);
                        const score = area + clearance * Math.min(widgetW, widgetH) * 0.5;
                        if (score > bestScore) {
                            bestScore = score;
                            best = { x: ux[cStart], y: uy[rTop], width: rectW, height: rectH };
                        }
                    }
                    cStart = -1;
                }
            }
        }
    }
    return best;
}

function bestOpenSpot(screenWidth, screenHeight, reserved, obstacles, widgetWidth, widgetHeight, options) {
    const sw = Math.max(1, Number(screenWidth) || 1920);
    const sh = Math.max(1, Number(screenHeight) || 1080);
    const ww = Math.max(1, Number(widgetWidth) || 230);
    const wh = Math.max(1, Number(widgetHeight) || 230);
    if (!Array.isArray(obstacles) || obstacles.length === 0) return null;

    const edgeMargin = options && Number.isFinite(options.edgeMargin) ? options.edgeMargin : 24;
    const obstaclePadding = options && Number.isFinite(options.obstaclePadding) ? options.obstaclePadding : 16;
    const res = Array.isArray(reserved) && reserved.length >= 4 ? reserved : [0, 0, 0, 0];

    const left = Math.max(0, (Number(res[0]) || 0) + edgeMargin);
    const top = Math.max(0, (Number(res[1]) || 0) + edgeMargin);
    const right = Math.min(sw, sw - (Number(res[2]) || 0) - edgeMargin);
    const bottom = Math.min(sh, sh - (Number(res[3]) || 0) - edgeMargin);
    const bounds = { x: left, y: top, width: Math.max(0, right - left), height: Math.max(0, bottom - top) };

    let rect = findMaxEmptyRect(bounds, obstacles, ww, wh, obstaclePadding);
    if (!rect && obstaclePadding > 0) {
        rect = findMaxEmptyRect(bounds, obstacles, ww, wh, 0);
    }
    if (!rect && edgeMargin > 8) {
        const tightBounds = {
            x: Math.max(0, (Number(res[0]) || 0) + 8),
            y: Math.max(0, (Number(res[1]) || 0) + 8),
            width: Math.max(0, sw - (Number(res[0]) || 0) - (Number(res[2]) || 0) - 16),
            height: Math.max(0, sh - (Number(res[1]) || 0) - (Number(res[3]) || 0) - 16),
        };
        rect = findMaxEmptyRect(tightBounds, obstacles, ww, wh, 0);
    }
    if (!rect) return null;

    return {
        x: clamp(rect.x + rect.width * 0.5, ww * 0.5, sw - ww * 0.5),
        y: clamp(rect.y + rect.height * 0.5, wh * 0.5, sh - wh * 0.5),
        rect: rect,
    };
}
