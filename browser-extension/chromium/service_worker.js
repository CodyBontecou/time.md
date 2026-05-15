const HOST_NAME = 'com.bontecou.time_md.blocking';
const RECENT_WINDOW_MS = 1500;
const recentEvents = new Map();

function shouldReport(url, tabId) {
  if (!url || (!url.startsWith('http://') && !url.startsWith('https://'))) return false;
  const key = `${tabId}:${url}`;
  const now = Date.now();
  const previous = recentEvents.get(key);
  recentEvents.set(key, now);
  for (const [eventKey, timestamp] of recentEvents.entries()) {
    if (now - timestamp > 30_000) recentEvents.delete(eventKey);
  }
  return previous === undefined || now - previous > RECENT_WINDOW_MS;
}

async function showBlockedPage(tabId, response) {
  if (typeof tabId !== 'number' || tabId < 0) return;
  const params = new URLSearchParams({
    domain: response.targetDomain ?? 'this site',
    remaining: String(Math.max(0, Math.ceil(response.remainingSeconds ?? 0))),
    until: response.blockedUntil ? String(response.blockedUntil) : ''
  });
  await chrome.tabs.update(tabId, { url: chrome.runtime.getURL(`blocked.html?${params}`) });
}

async function reportURL(url, tabId, frameId = 0) {
  if (!shouldReport(url, tabId)) return;

  const message = {
    type: 'urlAccess',
    url,
    browser: 'Chromium',
    tabId,
    frameId,
    occurredAt: Date.now() / 1000
  };

  try {
    const response = await chrome.runtime.sendNativeMessage(HOST_NAME, message);
    if (response?.action === 'block' && response.targetDomain) {
      const remaining = Math.max(0, Math.ceil(response.remainingSeconds ?? 0));
      chrome.action.setBadgeText({ text: 'BLOCK' });
      chrome.action.setBadgeBackgroundColor({ color: '#D97706' });
      console.info(`time.md blocked ${response.targetDomain}; ${remaining}s remaining`);
      await showBlockedPage(tabId, response);
    } else if (response?.action === 'allow') {
      chrome.action.setBadgeText({ text: '' });
    }
  } catch (error) {
    // Native host is optional. Keep browsing normally if time.md or the host
    // manifest is not installed, disabled, or unreachable.
    console.debug('time.md native messaging unavailable', error);
  }
}

chrome.webNavigation.onCommitted.addListener((details) => {
  if (details.frameId !== 0) return;
  reportURL(details.url, details.tabId, details.frameId);
});

chrome.webNavigation.onHistoryStateUpdated.addListener((details) => {
  if (details.frameId !== 0) return;
  reportURL(details.url, details.tabId, details.frameId);
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.url) {
    reportURL(changeInfo.url, tabId, 0);
  } else if (changeInfo.status === 'complete' && tab.url) {
    reportURL(tab.url, tabId, 0);
  }
});
