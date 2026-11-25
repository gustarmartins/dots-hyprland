// A sparse grid: saved positions are preferred, collisions flow into free cells.
// Keep legacy `size` as the horizontal span; missing height means one row.
var TILE_CATEGORIES = {
    network: "essentials",
    bluetooth: "essentials",
    audio: "essentials",
    mic: "essentials",
    easyEffects: "essentials",
    powerProfile: "essentials",
    darkMode: "comfort",
    nightLight: "comfort",
    idleInhibitor: "comfort",
    notifications: "comfort",
    screenSnip: "comfort",
    colorPicker: "comfort",
    musicRecognition: "comfort",
    antiFlashbang: "comfort",
    onScreenKeyboard: "comfort",
    focusMode: "performance",
    directScanout: "performance",
    tearing: "performance",
    gameMode: "performance",
    vrr: "performance",
    lsfg: "performance",
    tripleBuffer: "performance",
    memoryMode: "advanced",
    gpuMemory: "advanced",
    zramAlgo: "advanced",
    zramWriteback: "advanced",
    zramRecompress: "advanced",
    memoryCompact: "advanced",
    dropCaches: "advanced",
    buildCache: "advanced"
};

function categoryOf(type) {
    return TILE_CATEGORIES[type] || "comfort";
}

function defaultColumns() {
    return 8;
}

function defaultToggles() {
    return [
        // Row 0: Daily connectivity & audio
        { column: 0, row: 0, size: 2, height: 1, type: "network" },
        { column: 2, row: 0, size: 2, height: 1, type: "bluetooth" },
        { column: 4, row: 0, size: 2, height: 1, type: "audio" },
        { column: 6, row: 0, size: 2, height: 1, type: "mic" },
        // Row 1: Power, audio engine & display comfort
        { column: 0, row: 1, size: 2, height: 1, type: "powerProfile" },
        { column: 2, row: 1, size: 2, height: 1, type: "easyEffects" },
        { column: 4, row: 1, size: 2, height: 1, type: "darkMode" },
        { column: 6, row: 1, size: 2, height: 1, type: "nightLight" },
        // Row 2: Compact 1-tap utilities strip
        { column: 0, row: 2, size: 1, height: 1, type: "idleInhibitor" },
        { column: 1, row: 2, size: 1, height: 1, type: "notifications" },
        { column: 2, row: 2, size: 1, height: 1, type: "screenSnip" },
        { column: 3, row: 2, size: 1, height: 1, type: "colorPicker" },
        { column: 4, row: 2, size: 1, height: 1, type: "musicRecognition" },
        { column: 5, row: 2, size: 1, height: 1, type: "antiFlashbang" },
        { column: 6, row: 2, size: 1, height: 1, type: "onScreenKeyboard" },
        { column: 7, row: 2, size: 1, height: 1, type: "vrr" },
        // Row 3: Performance & compositor graphics tweaks
        { column: 0, row: 3, size: 2, height: 1, type: "focusMode" },
        { column: 2, row: 3, size: 2, height: 1, type: "directScanout" },
        { column: 4, row: 3, size: 2, height: 1, type: "tearing" },
        { column: 6, row: 3, size: 2, height: 1, type: "gameMode" },
        // Row 4: Memory & VRAM controls (safe left-click, hold right-click)
        { column: 0, row: 4, size: 2, height: 1, type: "memoryMode" },
        { column: 2, row: 4, size: 3, height: 1, type: "gpuMemory" },
        { column: 5, row: 4, size: 3, height: 1, type: "zramAlgo" },
        // Row 5: ZRAM writeback & tier recompression
        { column: 0, row: 5, size: 4, height: 1, type: "zramWriteback" },
        { column: 4, row: 5, size: 4, height: 1, type: "zramRecompress" },
        // Row 6: Press-and-hold heavy system actions
        { column: 0, row: 6, size: 2, height: 1, type: "memoryCompact" },
        { column: 2, row: 6, size: 2, height: 1, type: "dropCaches" },
        { column: 4, row: 6, size: 2, height: 1, type: "buildCache" },
        { column: 6, row: 6, size: 2, height: 1, type: "tripleBuffer" }
    ];
}

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
