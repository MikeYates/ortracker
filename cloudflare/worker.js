// Cloudflare Workers — serves install script at ortracker.yates.id
// Routes: /install.sh → install script

const INSTALL_SCRIPT_URL = 'https://raw.githubusercontent.com/mikeyates/ortracker/main/install.sh';
const APP_VERSION = '1.1.0';
const GITHUB_REPO = 'mikeyates/ortracker';

async function handleRequest(request) {
  const url = new URL(request.url);
  const path = url.pathname;

  // Root — info page
  if (path === '/' || path === '') {
    return new Response(renderPage(), {
      headers: { 'content-type': 'text/html;charset=UTF-8' },
    });
  }

  // /install.sh — proxy install script
  if (path === '/install.sh') {
    const resp = await fetch(INSTALL_SCRIPT_URL);
    const script = await resp.text();
    return new Response(script, {
      headers: {
        'content-type': 'text/plain;charset=UTF-8',
        'cache-control': 'public, max-age=300',
      },
    });
  }

  // /latest — returns latest version info as JSON
  if (path === '/latest') {
    return new Response(JSON.stringify({
      version: APP_VERSION,
      repo: GITHUB_REPO,
      download_url: `https://github.com/${GITHUB_REPO}/releases/latest`,
      install_cmd: `curl -fsSL https://ortracker.yates.id/install.sh | bash`,
    }), {
      headers: { 'content-type': 'application/json' },
    });
  }

  return new Response('Not found', { status: 404 });
}

function renderPage() {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ORTracker — OpenRouter Balance Tracker</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: -apple-system, 'Inter', 'Helvetica Neue', sans-serif;
    background: #0d0d0d;
    color: #e0e0e0;
    line-height: 1.6;
  }
  .container { max-width: 680px; margin: 0 auto; padding: 60px 24px; }
  h1 { font-size: 2.5rem; font-weight: 700; letter-spacing: -0.02em; margin-bottom: 8px; }
  h1 span { background: linear-gradient(135deg, #10b981, #3b82f6); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
  .subtitle { font-size: 1.1rem; color: #888; margin-bottom: 40px; }
  .install-box {
    background: #1a1a1a;
    border: 1px solid #333;
    border-radius: 12px;
    padding: 24px;
    margin-bottom: 40px;
  }
  code {
    background: #2a2a2a;
    padding: 12px 16px;
    border-radius: 8px;
    display: block;
    font-size: 0.9rem;
    color: #10b981;
    word-break: break-all;
  }
  .features { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 40px; }
  .feature {
    background: #1a1a1a;
    border: 1px solid #333;
    border-radius: 10px;
    padding: 20px;
  }
  .feature h3 { font-size: 0.9rem; text-transform: uppercase; letter-spacing: 0.05em; color: #888; margin-bottom: 6px; }
  .feature p { font-size: 0.95rem; color: #ccc; }
  .footer { color: #555; font-size: 0.85rem; }
  .footer a { color: #3b82f6; text-decoration: none; }
  @media (max-width: 480px) {
    .features { grid-template-columns: 1fr; }
    h1 { font-size: 2rem; }
  }
</style>
</head>
<body>
<div class="container">
  <h1><span>OR</span>Tracker</h1>
  <p class="subtitle">OpenRouter balance in your menu bar</p>

  <div class="install-box">
    <p style="margin-bottom: 12px; font-weight: 600;">Install with one command:</p>
    <code>curl -fsSL https://ortracker.yates.id/install.sh | bash</code>
  </div>

  <div class="features">
    <div class="feature">
      <h3>Live balance</h3>
      <p>Your OpenRouter balance in the menu bar, updated every 60 seconds. Green when full, red when running low.</p>
    </div>
    <div class="feature">
      <h3>Top-up detection</h3>
      <p>When you top up, the tracker resets to 100%. No manual entry needed — it just works.</p>
    </div>
    <div class="feature">
      <h3>Auto-update</h3>
      <p>Checks for updates silently every 6 hours. Updates itself in the background with no interruption.</p>
    </div>
    <div class="feature">
      <h3>Privacy first</h3>
      <p>No servers, no analytics, no tracking. Your API key stays on your machine. Open source on GitHub.</p>
    </div>
  </div>

  <p class="footer">
    <a href="https://github.com/mikeyates/ortracker">GitHub</a> &middot;
    <a href="https://openrouter.ai">OpenRouter</a> &middot;
    requires macOS 13+
  </p>
</div>
</body>
</html>`;
}

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request));
});