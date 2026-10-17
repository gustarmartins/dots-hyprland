// A sparse grid: saved positions are preferred, collisions flow into free cells.
// Keep legacy `size` as the horizontal span; missing height means one row.
function span(value, limit) {
    return Math.max(1, Math.min(limit, Math.round(Number(value) || 1)));
}

function layout(tiles, columns, minimumRows) {
    columns = span(columns, 12);
    const occupied = new Set();
    const result = [];
    let rows = minimumRows || 7;
    function fits(column, row, width, height) {
        if (column < 0 || row < 0 || column + width > columns) return false;
        for (let y = row; y < row + height; y++)
            for (let x = column; x < column + width; x++)
                if (occupied.has(y * columns + x)) return false;
        return true;
    }
    const pending = [];
    function place(tile, column, row) {
        for (let y = row; y < row + tile.height; y++)
            for (let x = column; x < column + tile.size; x++) occupied.add(y * columns + x);
        rows = Math.max(rows, row + tile.height);
        result[tile.sourceIndex] = Object.assign({}, tile, {gridColumn: column, gridRow: row});
    }
    // Reserve every valid saved location before filling gaps with displaced tiles.
    for (let index = 0; index < tiles.length; index++) {
        const source = tiles[index];
        if (!source || !source.type) continue;
        const tile = Object.assign({}, source, {size: span(source.size, columns), height: span(source.height, 7), sourceIndex: index});
        const column = Math.round(Number(source.column));
        const row = Math.round(Number(source.row));
        if (Number.isFinite(column) && Number.isFinite(row) && fits(column, row, tile.size, tile.height))
            place(tile, column, row);
        else pending.push(tile);
    }
    for (const tile of pending) {
        let cell = 0;
        while (!fits(cell % columns, Math.floor(cell / columns), tile.size, tile.height)) cell++;
        place(tile, cell % columns, Math.floor(cell / columns));
    }
    return {tiles: result.filter(tile => tile), rows: rows};
}

// Materialize rendered positions before editing so untouched tiles stay put.
function snapshot(tiles, columns) {
    return layout(tiles, columns, 7).tiles.map(tile => {
        const next = Object.assign({}, tile, {column: tile.gridColumn, row: tile.gridRow});
        delete next.gridColumn; delete next.gridRow; delete next.sourceIndex;
        return next;
    });
}

function resize(tiles, index, width, height, columns) {
    const next = snapshot(tiles, columns);
    if (!next[index]) return next;
    const tile = next.splice(index, 1)[0];
    tile.size = span(width, columns);
    tile.height = span(height, 7);
    tile.column = Math.min(tile.column, columns - tile.size);
    next.unshift(tile);
    return snapshot(next, columns);
}

function move(tiles, index, column, row, columns) {
    const next = snapshot(tiles, columns);
    if (!next[index]) return next;
    const tile = next.splice(index, 1)[0];
    tile.column = Math.max(0, Math.min(columns - span(tile.size, columns), Math.round(column)));
    tile.row = Math.max(0, Math.min(48, Math.round(row)));
    next.unshift(tile);
    return snapshot(next, columns);
}
