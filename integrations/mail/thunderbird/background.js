/* Mail remains in Thunderbird. No credentials, remote content or attachments
 * cross this bridge. Native host exits when disabled; no reconnect timer. */
let port = null;
let config = {enabled: false, accounts: []};
let queue = Promise.resolve();
const seen = new Set();

function post(data) { if (port) port.postMessage(data); }
async function accounts() {
  const list = await messenger.accounts.list(false);
  post({type: "accounts", accounts: list.filter(a => a.type !== "none").map(a => ({
    id: a.id, name: a.name, type: a.type,
    email: a.identities?.[0]?.email || ""
  }))});
}
function parts(node, out = [], depth = 0) {
  // Attached emails and attachments are never scanned.
  if (depth > 16 || out.length >= 32 || (node.contentDisposition || "").startsWith("attachment") || node.contentType === "message/rfc822") return out;
  const remaining = 131072 - out.reduce((n, p) => n + p.text.length, 0);
  if (remaining <= 0) return out;
  if (["text/plain", "text/html"].includes(node.contentType) && typeof node.body === "string")
    out.push({type: node.contentType, text: node.body.slice(0, Math.min(remaining, 65536))});
  for (const child of node.parts || []) parts(child, out, depth + 1);
  return out;
}
async function deliver(folder, list, preview = false) {
  while (list && port && config.enabled && config.notifications) {
    for (const msg of list.messages) {
      const account = folder.accountId;
      if (!config.accounts.includes(account) || msg.read || msg.junk) continue;
      const key = `${account}:${msg.headerMessageId || msg.id}`;
      if (!preview && seen.has(key)) continue;
      // Suppress historic sync floods. Explicit preview is a separate action.
      if (!preview && Date.now() - new Date(msg.date).getTime() > 15 * 60000) continue;
      let bodies = [];
      if ((config.preview || config.codes || config.links) && (msg.size || 0) <= 2 * 1024 * 1024) {
        try { bodies = parts(await messenger.messages.getFull(msg.id, {decrypt: false})); }
        catch (_) { /* Still deliver the envelope when the body is unavailable. */ }
      }
      if (!port || !config.enabled || !config.accounts.includes(account)) return;
      post({type: "mail", key, account, messageId: msg.id, headerMessageId: msg.headerMessageId || "",
        sender: msg.author, subject: msg.subject, date: new Date(msg.date).getTime(), bodies, preview});
      seen.add(key);
      if (seen.size > 512) seen.delete(seen.values().next().value);
      if (preview) return;
    }
    list = list.id ? await messenger.messages.continueList(list.id) : null;
  }
}
async function command(data) {
  if (data.type === "config") { config = data.config; await accounts(); return; }
  if (!config.enabled) return;
  if (data.type === "open") {
    // Internal IDs are valid only during this native-host session.
    await messenger.messageDisplay.open({messageId: data.messageId, location: "tab", active: true});
    const win = await messenger.windows.getLastFocused();
    await messenger.windows.update(win.id, {focused: true});
  } else if (data.type === "preview") {
    const all = await messenger.accounts.list(true);
    const walk = nodes => nodes.flatMap(f => [f, ...walk(f.subFolders || [])]);
    for (const account of all.filter(a => config.accounts.includes(a.id))) {
      const inbox = walk(account.folders || account.rootFolder?.subFolders || []).find(f => f.type === "inbox" || f.specialUse?.includes("inbox"));
      if (!inbox) continue;
      const list = await messenger.messages.query({folderId: inbox.id, unread: true, messagesPerPage: 1});
      if (list.messages.length) await deliver(inbox, list, true);
    }
    post({type: "status", status: "Preview requested. Any unread message is shown only in Quickshell."});
  }
}
function connect() {
  if (port) return;
  port = messenger.runtime.connectNative("org.quickshell.mail");
  port.onMessage.addListener(data => { command(data).catch(() => post({type: "status", status: "Mail action failed. Open Thunderbird to check the account."})); });
  port.onDisconnect.addListener(() => { port = null; config = {enabled: false, accounts: []}; });
  accounts().catch(() => {});
}
messenger.messages.onNewMailReceived.addListener((folder, list) => {
  if (!config.enabled || !config.notifications || !config.accounts.includes(folder.accountId)) return;
  if (!(folder.type === "inbox" || folder.specialUse?.includes("inbox"))) return;
  queue = queue.then(() => deliver(folder, list)).catch(() => post({type: "status", status: "Message preview unavailable. Open Thunderbird to check mail."}));
});
for (const event of [messenger.accounts.onCreated, messenger.accounts.onDeleted, messenger.accounts.onUpdated])
  event.addListener(() => accounts().catch(() => {}));
messenger.browserAction.onClicked.addListener(connect);
connect();
