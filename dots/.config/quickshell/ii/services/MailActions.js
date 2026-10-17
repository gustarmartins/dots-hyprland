.pragma library
function parse(value) {
    try {
        const data = JSON.parse(value || "{}");
        if (!/^[a-f0-9]{32}$/.test(data.session) || !/^[a-f0-9]{24}$/.test(data.ref) || typeof data.account !== "string") return null;
        return {session:data.session, ref:data.ref, account:data.account,
            code:/^[A-Z0-9]{4,8}$/.test(data.code || "") ? data.code : "",
            expiresAt:Number(data.expiresAt) || 0,
            links:(Array.isArray(data.links) ? data.links : []).filter(l => typeof l.url === "string" && /^https?:\/\/[^\s/@]+(?:[/:?#]|$)/i.test(l.url) && !/[\x00-\x20\x7f]/.test(l.url)).slice(0,3)};
    } catch (_) { return null; }
}
function actions(data, config, age) {
    if (!data || !config.enabled || !config.notifications || !(config.accounts || []).includes(data.account)) return [];
    const result = [{identifier:"qs-mail-open", text:"Open mail"}];
    if (config.codes && data.code && data.expiresAt > Date.now() && age < 15 * 60000) result.push({identifier:"qs-mail-code", text:"Copy code"});
    if (config.links) data.links.forEach((l,i) => result.push({identifier:"qs-mail-link-" + i, text:"Open " + l.label}));
    return result;
}
