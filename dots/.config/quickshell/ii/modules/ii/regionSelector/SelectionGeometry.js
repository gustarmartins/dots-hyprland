function clip(rect, width, height) {
    if (!rect || ![rect.x, rect.y, rect.width, rect.height, width, height].every(Number.isFinite)) return null;
    const left = Math.max(0, rect.x), top = Math.max(0, rect.y);
    const right = Math.min(width, rect.x + rect.width), bottom = Math.min(height, rect.y + rect.height);
    return right > left && bottom > top ? {x: left, y: top, width: right - left, height: bottom - top} : null;
}
function bounds(points, padding) {
    if (!points.length) return null;
    let left = points[0].x, right = left, top = points[0].y, bottom = top;
    for (const p of points) {
        left = Math.min(left, p.x); right = Math.max(right, p.x);
        top = Math.min(top, p.y); bottom = Math.max(bottom, p.y);
    }
    return {x: left - padding, y: top - padding, width: right - left + padding * 2, height: bottom - top + padding * 2};
}
function pixels(rect, scale, width, height) {
    const r = clip(rect, width, height);
    if (!r || !Number.isFinite(scale) || scale <= 0) return null;
    const x = Math.floor(r.x * scale), y = Math.floor(r.y * scale);
    const right = Math.min(Math.round(width * scale), Math.ceil((r.x + r.width) * scale));
    const bottom = Math.min(Math.round(height * scale), Math.ceil((r.y + r.height) * scale));
    return {x: x, y: y, width: right - x, height: bottom - y};
}
