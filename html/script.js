// DPS 2026-09-27: subtitle talk layer for dps-ainpcs. Same NUI contract as before:
//   in:  openConversation {npcName, npcRole} · receiveMessage {message, npcName} · closeConversation
//   out: sendMessage {message} · offerPayment · endConversation · closeUI
let conversationOpen = false;
let isTyping = false;
let typeTimer = null;

const talk = document.getElementById('talk');
const nameEl = document.getElementById('npc-name');
const lineEl = document.getElementById('line');
const ringEl = document.getElementById('ring');
const inputEl = document.getElementById('message-input');
const payBtn = document.getElementById('pay-btn');
const leaveBtn = document.getElementById('leave-btn');
const gestureEl = document.getElementById('gesture');

function post(name, body) {
    return fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body || {})
    });
}

inputEl.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') { e.preventDefault(); sendMessage(); }
});
payBtn.addEventListener('click', offerPayment);
leaveBtn.addEventListener('click', endConversation);

document.addEventListener('keydown', function (e) {
    if (!conversationOpen) return;
    if (e.key === 'Escape') { e.preventDefault(); endConversation(); return; }
    if (document.activeElement !== inputEl && e.key.length === 1) {
        inputEl.focus();
    }
});

window.addEventListener('message', function (event) {
    const data = event.data || {};
    switch (data.action) {
        case 'openConversation': openConversation(data.npcName, data.npcRole, data.trust); break;
        case 'closeConversation': closeConversation(); break;
        case 'receiveMessage': receiveMessage(data.message, data.npcName, data.gesture); break;
        case 'setTrust': setTrust(data.trust); break;
    }
});

function setTrust(value) {
    const pct = Math.max(0, Math.min(100, Number(value) || 0));
    ringEl.style.setProperty('--trust', pct + '%');
}

function openConversation(npcName, npcRole, trust) {
    conversationOpen = true;
    nameEl.textContent = npcName || '';
    setTrust(trust);
    showLine('');
    gestureEl.classList.add('hidden');
    inputEl.value = '';
    talk.classList.remove('hidden');
    setTimeout(() => inputEl.focus(), 50);
}

function closeConversation() {
    conversationOpen = false;
    setTyping(false);
    talk.classList.add('hidden');
    inputEl.value = '';
    if (typeTimer) { clearInterval(typeTimer); typeTimer = null; }
    post('closeUI').catch(() => {});
}

function sendMessage() {
    if (isTyping || !conversationOpen) return;
    const message = inputEl.value.trim();
    if (!message) return;
    inputEl.value = '';
    setTyping(true);
    post('sendMessage', { message })
        .then(r => r.json())
        .then(result => { if (result !== 'ok') setTyping(false); })
        .catch(() => setTyping(false));
}

// Type the NPC line out, rendering *stage directions* in italics.
function showLine(text) {
    if (typeTimer) { clearInterval(typeTimer); typeTimer = null; }
    lineEl.classList.remove('thinking');
    lineEl.innerHTML = '';
    if (!text) return;
    const parts = text.split(/(\*[^*]+\*)/g).filter(Boolean);
    const spans = parts.map(p => {
        const el = document.createElement(p.startsWith('*') ? 'em' : 'span');
        el.dataset.full = p.startsWith('*') ? p.slice(1, -1) : p;
        el.textContent = '';
        lineEl.appendChild(el);
        return el;
    });
    let i = 0, j = 0;
    typeTimer = setInterval(() => {
        if (i >= spans.length) { clearInterval(typeTimer); typeTimer = null; return; }
        const full = spans[i].dataset.full;
        j += 2;
        spans[i].textContent = full.slice(0, j);
        if (j >= full.length) { spans[i].textContent = full; i++; j = 0; }
    }, 18);
}

function receiveMessage(message, npcName, gesture) {
    setTyping(false);
    if (npcName) nameEl.textContent = npcName;
    showLine(message || '');
    if (gesture) {
        gestureEl.textContent = '[' + gesture + ']';
        gestureEl.classList.remove('hidden');
        setTimeout(() => gestureEl.classList.add('hidden'), 2500);
    }
    setTimeout(() => inputEl.focus(), 30);
}

function setTyping(typing) {
    isTyping = typing;
    payBtn.disabled = typing;
    if (typing) {
        if (typeTimer) { clearInterval(typeTimer); typeTimer = null; }
        lineEl.classList.add('thinking');
        lineEl.textContent = '…';
    }
}

function offerPayment() {
    if (!conversationOpen) return;
    post('offerPayment').catch(() => {});
}

function endConversation() {
    if (!conversationOpen) return;
    post('endConversation').catch(() => {});
}

function GetParentResourceName() { return 'dps-ainpcs'; }
