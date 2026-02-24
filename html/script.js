let conversationOpen = false;
let isTyping = false;

// DOM Elements
const conversationContainer = document.getElementById('conversation-container');
const npcNameElement = document.getElementById('npc-name');
const npcRoleElement = document.getElementById('npc-role');
const messagesContainer = document.getElementById('conversation-messages');
const messageInput = document.getElementById('message-input');
const sendButton = document.getElementById('send-btn');
const endButton = document.getElementById('end-conversation-btn');
const closeButton = document.getElementById('close-btn');
const paymentButton = document.getElementById('payment-btn');

// Event Listeners
messageInput.addEventListener('keypress', function(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        sendMessage();
    }
});

sendButton.addEventListener('click', sendMessage);
endButton.addEventListener('click', endConversation);
closeButton.addEventListener('click', closeConversation);
paymentButton.addEventListener('click', offerPayment);

// Prevent default browser behavior
document.addEventListener('keydown', function(e) {
    if (conversationOpen) {
        // Allow typing in input field
        if (document.activeElement === messageInput) {
            return;
        }

        // Prevent other keys when conversation is open
        if (e.key === 'Escape') {
            closeConversation();
        }
        e.preventDefault();
    }
});

// NUI Message Handler
window.addEventListener('message', function(event) {
    const data = event.data;

    switch (data.action) {
        case 'openConversation':
            openConversation(data.npcName, data.npcRole);
            break;
        case 'closeConversation':
            closeConversation();
            break;
        case 'receiveMessage':
            receiveMessage(data.message, data.npcName);
            break;
    }
});

// Open conversation UI
function openConversation(npcName, npcRole) {
    conversationOpen = true;
    npcNameElement.textContent = npcName;
    npcRoleElement.textContent = npcRole.replace('_', ' ').toUpperCase();

    // Clear previous messages
    messagesContainer.innerHTML = '';

    // Show container
    conversationContainer.classList.remove('hidden');

    // Focus input
    setTimeout(() => {
        messageInput.focus();
    }, 100);

    console.log(`[AI NPCs] Opened conversation with ${npcName}`);
}

// Close conversation UI
function closeConversation() {
    conversationOpen = false;
    conversationContainer.classList.add('hidden');

    // Clear input
    messageInput.value = '';

    // Notify client
    fetch(`https://${GetParentResourceName()}/closeUI`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({})
    });

    console.log('[AI NPCs] Closed conversation UI');
}

// Send message to NPC
function sendMessage() {
    if (isTyping) return;

    const message = messageInput.value.trim();
    if (!message) return;

    // Add player message to UI
    addMessage(message, 'player', 'You');

    // Clear input
    messageInput.value = '';

    // Set typing state
    setTyping(true);

    // Send to server
    fetch(`https://${GetParentResourceName()}/sendMessage`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            message: message
        })
    }).then(response => response.text()).then(result => {
        if (result !== 'ok') {
            console.error('[AI NPCs] Failed to send message');
            setTyping(false);
        }
    });
}

// Receive message from NPC
function receiveMessage(message, npcName) {
    setTyping(false);
    addMessage(message, 'npc', npcName);
}

// Add message to conversation
function addMessage(text, sender, senderName) {
    const messageDiv = document.createElement('div');
    messageDiv.className = `message ${sender}`;

    const senderDiv = document.createElement('div');
    senderDiv.className = 'message-sender';
    senderDiv.textContent = senderName;

    const textDiv = document.createElement('div');
    textDiv.textContent = text;

    messageDiv.appendChild(senderDiv);
    messageDiv.appendChild(textDiv);

    messagesContainer.appendChild(messageDiv);

    // Scroll to bottom
    messagesContainer.scrollTop = messagesContainer.scrollHeight;
}

// Set typing indicator
function setTyping(typing) {
    isTyping = typing;
    sendButton.disabled = typing;

    if (typing) {
        // Add typing indicator
        const typingDiv = document.createElement('div');
        typingDiv.className = 'typing-indicator';
        typingDiv.id = 'typing-indicator';
        typingDiv.textContent = `${npcNameElement.textContent} is thinking...`;

        messagesContainer.appendChild(typingDiv);
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
    } else {
        // Remove typing indicator
        const typingIndicator = document.getElementById('typing-indicator');
        if (typingIndicator) {
            typingIndicator.remove();
        }
    }
}

// Offer payment to NPC
function offerPayment() {
    if (!conversationOpen) return;

    fetch(`https://${GetParentResourceName()}/offerPayment`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({})
    });
}

// End conversation
function endConversation() {
    fetch(`https://${GetParentResourceName()}/endConversation`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({})
    });

    closeConversation();
}

// Utility function to get resource name
function GetParentResourceName() {
    return 'dps-ainpcs';
}