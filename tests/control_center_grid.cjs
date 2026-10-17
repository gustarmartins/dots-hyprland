const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const grid = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../dots/.config/quickshell/ii/modules/ii/sidebarRight/quickToggles/TileGrid.js'), 'utf8'), grid);

function verify(tiles, columns) {
    const result = grid.layout(tiles, columns, 7);
    const cells = new Set();
    assert.equal(result.tiles.length, tiles.filter(t => t?.type).length);
    for (const tile of result.tiles) {
        assert(tile.gridColumn >= 0 && tile.gridColumn + tile.size <= columns);
        assert(tile.gridRow >= 0 && tile.gridRow + tile.height <= result.rows);
        for (let y = tile.gridRow; y < tile.gridRow + tile.height; y++) {
            for (let x = tile.gridColumn; x < tile.gridColumn + tile.size; x++) {
                const key = `${x}:${y}`;
                assert(!cells.has(key), `overlap at ${key}`);
                cells.add(key);
            }
        }
    }
    return result;
}

const singles = Array.from({length: 49}, (_, i) => ({type: `tile${i}`, size: 1}));
const full = verify(singles, 7);
assert.equal(full.rows, 7);
assert.equal(full.tiles[48].gridColumn, 6);
assert.equal(full.tiles[48].gridRow, 6);
const legacy = [{type:'audio',size:2},{type:'mic',size:1}];
assert.equal(verify(legacy, 7).tiles[0].height, 1);
for (let width = 1; width <= 7; width++) {
    for (let height = 1; height <= 7; height++) {
        const resized = grid.resize(singles, 0, width, height, 7);
        const result = verify(resized, 7);
        assert.equal(result.tiles[0].size, width);
        assert.equal(result.tiles[0].height, height);
        assert.equal(singles[0].size, 1, 'resize mutated the previous config');
        assert.equal(singles[0].height, undefined);
    }
}
const moved = grid.move(legacy, 1, 6, 6, 7);
const positions = verify(moved, 7);
assert.equal(positions.tiles[0].type, 'mic');
assert.equal(positions.tiles[0].gridColumn, 6);
assert.equal(positions.tiles[0].gridRow, 6);
const duplicatePosition = [{type:'audio',size:7,height:7,column:0,row:0},{type:'mic',size:3,height:2,column:0,row:0}];
assert.equal(verify(duplicatePosition,7).tiles[1].gridRow,7);
for (let columns = 1; columns <= 12; columns++) verify(duplicatePosition,columns);
verify([{type:'bad',size:99,height:-4},{type:'null-size',size:null},null],7);
// User extension properties and explicit placement survive save/reload.
const custom = [{type:'audio',size:2,height:3,column:4,row:2,custom:{keep:true}}];
const resized = grid.resize(custom,0,3,4,7);
assert(resized[0].custom.keep);
const reloaded = JSON.parse(JSON.stringify(resized));
assert.equal(JSON.stringify(grid.layout(resized,7,7)),JSON.stringify(grid.layout(reloaded,7,7)));
console.log('PASS: 49 size combinations, all 49 grid cells, collision reflow, legacy sizes, exact columns, and persistence');
// Enlarging a later tile keeps its anchor and displaces only collisions.
const anchored = [{type:'a',size:1,column:0,row:0},{type:'b',size:1,column:1,row:0},{type:'c',size:1,column:2,row:0},{type:'d',size:1,column:6,row:5}];
const enlarged = verify(grid.resize(anchored,1,2,2,7),7).tiles;
assert.equal(enlarged.find(t=>t.type==='b').gridColumn,1);
assert.equal(enlarged.find(t=>t.type==='b').gridRow,0);
assert.equal(enlarged.find(t=>t.type==='d').gridColumn,6);
assert.equal(enlarged.find(t=>t.type==='d').gridRow,5);
const shifted = grid.move(anchored,0,1,0,7);
const stable = verify(shifted,7).tiles;
assert.equal(stable.find(t=>t.type==='c').gridColumn,2);
assert.equal(stable.find(t=>t.type==='d').gridRow,5);
assert.equal(verify(shifted.filter(t=>t.type!=='b'),7).tiles.find(t=>t.type==='c').gridColumn,2);
console.log('PASS: resize anchor, collision priority, unaffected placement, and deletion gaps');
