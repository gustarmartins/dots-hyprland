const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.join(__dirname, '..');
const listeners = {};
const sent = [];
let bodyReads = 0;
const event = name => ({addListener: fn => listeners[name] = fn});
const folder = {id:'inbox', accountId:'account1', type:'inbox'};
const message = {id:1, headerMessageId:'synthetic@local', subject:'Verify', author:'Synthetic', date:new Date(), read:false, junk:false};
const api = {
  accounts: {list:async () => [{id:'account1',type:'imap',name:'Fixture',identities:[{email:'fixture@example.invalid'}],folders:[folder]}], onCreated:event('created'),onDeleted:event('deleted'),onUpdated:event('updated')},
  messages: {onNewMailReceived:event('new'),getFull:async () => {bodyReads++;return {parts:[{contentType:'text/plain',body:'Your verification code is 123456'},{contentType:'text/plain',contentDisposition:'attachment',body:'Must never cross bridge'},{contentType:'message/rfc822',parts:[{contentType:'text/plain',body:'Attached message'}]}]};},query:async()=>({messages:[message]}),continueList:async()=>({messages:[]})},
  messageDisplay:{open:async data=>sent.push({opened:data.messageId})},
  windows:{getLastFocused:async()=>({id:1}),update:async()=>{}},
  runtime:{connectNative:()=>({postMessage:data=>sent.push(data),onMessage:event('command'),onDisconnect:event('disconnect')})},
  browserAction:{onClicked:event('reconnect')}
};
vm.runInNewContext(fs.readFileSync(path.join(root,'integrations/mail/thunderbird/background.js'),'utf8'), {messenger:api,Date,Set,Promise});
const flush = () => new Promise(resolve=>setImmediate(resolve));
(async()=>{
 await flush();assert(sent.some(x=>x.type==='accounts'));
 listeners.new(folder,{messages:[message]});await flush();assert.equal(bodyReads,0);
 listeners.command({type:'config',config:{enabled:true,notifications:true,preview:true,codes:true,links:true,accounts:['account1']}});await flush();
 listeners.new(folder,{messages:[message]});await flush();
 const mail=sent.find(x=>x.type==='mail');assert(mail);assert.equal(mail.bodies.length,1);assert.equal(bodyReads,1);
 listeners.new(folder,{messages:[message]});await flush();assert.equal(bodyReads,1,'duplicate suppressed');
 listeners.new(folder,{messages:[{...message,id:2,headerMessageId:'old',date:new Date(0)}]});await flush();assert.equal(bodyReads,1,'historic sync suppressed');
 listeners.new({...folder,accountId:'other'},{messages:[{...message,id:3}]});await flush();assert.equal(bodyReads,1,'unselected account gated');
 listeners.command({type:'config',config:{enabled:true,notifications:true,preview:false,codes:false,links:false,accounts:['account1']}});await flush();
 listeners.new(folder,{messages:[{...message,id:4,headerMessageId:'envelope-only'}]});await flush();assert.equal(bodyReads,1,'all content features off skips body fetch');
 listeners.command({type:'open',messageId:1});await flush();assert(sent.some(x=>x.opened===1));
 listeners.disconnect();listeners.new(folder,{messages:[{...message,id:5}]});await flush();assert.equal(bodyReads,1,'disconnected extension dormant');
 const actions={};vm.createContext(actions);vm.runInContext(fs.readFileSync(path.join(root,'dots/.config/quickshell/ii/services/MailActions.js'),'utf8').replace('.pragma library',''),actions);
 const data=actions.parse(JSON.stringify({session:'a'.repeat(32),ref:'b'.repeat(24),account:'account1',code:'123456',expiresAt:Date.now()+900000,links:[{url:'https://example.invalid/verify',label:'example.invalid'},{url:'javascript:bad()',label:'bad'}]}));
 assert.equal(data.links.length,1);
 const cfg={enabled:true,notifications:true,codes:true,links:true,accounts:['account1']};
 assert.equal(actions.actions(data,cfg,0).length,3);
 assert.equal(actions.actions(data,cfg,1000000).length,2,'expired code gated');
 assert.equal(actions.actions({...data,expiresAt:Date.now()-1},cfg,0).length,2,'email age gates codes too');
 assert.equal(actions.actions(data,{...cfg,enabled:false},0).length,0);
 assert.equal(actions.actions(data,{...cfg,accounts:[]},0).length,0);
 console.log('PASS: extension events, account gates, body fetch controls, dedup, old mail, attachment exclusion, disconnect and action validation');
})().catch(e=>{console.error(e);process.exitCode=1;});
