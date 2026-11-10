const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const stats = {};
vm.createContext(stats);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../dots/.config/quickshell/ii/services/CryoDAppStats.js'), 'utf8'), stats);
const now = 1800000000000;
let history = stats.observe([], [{app_id:'z.desktop',pid:42,start_ticks:'10',cpu_percent_x100:'2500'},
    {app_id:'b.desktop',pid:43,start_ticks:'11'}, {app_id:'a.desktop',pid:44,start_ticks:'12',cpu_percent_x100:'500'}], now);
history = stats.observe(history, [{app_id:'z.desktop',pid:42,start_ticks:'10',cpu_percent_x100:'1000'}], now+10);
assert.equal(history[0].cpu_peak_x100,2500);
assert.equal(history[0].cpu_seen,now);
assert.equal(history[0].last_seen,now+10);
const apps = history.map(row=>({app_id:row.app_id,stats:row})).concat([
    {app_id:'never.desktop',installed:true}, {app_id:'configured.desktop',rule:{permissions:{freeze:'allow'}}},
    {app_id:'running.desktop',pid:99}]);
const ids = (filter, order='relevant', min=0, query='') => Array.from(stats.select(apps,x=>x,query,filter,order,min), a=>a.app_id);
assert.deepEqual(ids('relevant'),['z.desktop','a.desktop','b.desktop','running.desktop','configured.desktop']);
assert.equal(ids('seen').includes('configured.desktop'),false);
assert.deepEqual(ids('cpu','cpu',10),['z.desktop']);
assert.deepEqual(ids('running'),['running.desktop']);
assert.deepEqual(ids('all','name',0,'NEVER'),['never.desktop']);
assert.equal(ids('all','cpu',1).includes('b.desktop'),false);
assert.equal(stats.validNumber(null),false);
assert.equal(stats.validNumber(''),false);
assert.equal(stats.sanitize(history,now+stats.retentionMs+100).length,0);
assert.equal(stats.sanitize([{app_id:'future',last_seen:now+100}],now).length,0);
const many = Array.from({length:300},(_,i)=>({app_id:String(i),pid:42,start_ticks:'1'}));
assert.equal(stats.observe([],many,now).length,256);
assert.equal(stats.summary(apps.find(a=>a.app_id==='a.desktop')).includes('not measured'),false); // a has a measured CPU value
assert.equal(stats.summary({app_id:'unknown'}).includes('not measured'),true);
console.log('PASS: observed-only defaults, CPU ranking/thresholds, search, unknowns, peak timestamp, expiry and bounded retention');
