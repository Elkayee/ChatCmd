import http from "node:http";
import crypto from "node:crypto";

const chatcmdPort = Number(process.env.CHATCMD_PORT || 8080);
const bridgePort = Number(process.env.CHATCMD_BRIDGE_PORT || 8082);
const token = process.env.CHATCMD_MCP_TOKEN;

if (!token) throw new Error("CHATCMD_MCP_TOKEN is required");

const json = (res, status, body, headers = {}) => {
  res.writeHead(status, { "content-type": "application/json", ...headers });
  res.end(JSON.stringify(body));
};

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || "127.0.0.1"}`);
  const issuer = `http://${req.headers.host || `127.0.0.1:${bridgePort}`}`;

  if (url.pathname === "/health") {
    return json(res, 200, { status: "ok" });
  }
  if (url.pathname.startsWith("/.well-known/oauth-protected-resource")) {
    return json(res, 200, {
      resource: issuer,
      authorization_servers: [issuer],
      bearer_methods_supported: ["header"],
      scopes_supported: ["mcp:tools"],
    });
  }
  if (url.pathname.startsWith("/.well-known/oauth-authorization-server")) {
    return json(res, 200, {
      issuer,
      authorization_endpoint: `${issuer}/oauth/authorize`,
      token_endpoint: `${issuer}/oauth/token`,
      registration_endpoint: `${issuer}/oauth/register`,
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      token_endpoint_auth_methods_supported: ["none", "client_secret_post"],
      code_challenge_methods_supported: ["S256"],
      scopes_supported: ["mcp:tools"],
    });
  }
  if (url.pathname === "/oauth/register" && req.method === "POST") {
    return json(res, 201, {
      client_id: `client_${crypto.randomUUID()}`,
      client_secret: `secret_${crypto.randomUUID()}`,
      client_id_issued_at: Math.floor(Date.now() / 1000),
      client_secret_expires_at: 0,
      grant_types: ["authorization_code", "refresh_token"],
      response_types: ["code"],
      token_endpoint_auth_method: "client_secret_post",
    });
  }
  if (url.pathname === "/oauth/authorize" && req.method === "GET") {
    const redirectUri = url.searchParams.get("redirect_uri");
    if (!redirectUri) return json(res, 400, { error: "invalid_request" });
    const target = new URL(redirectUri);
    target.searchParams.set("code", crypto.randomUUID());
    if (url.searchParams.has("state")) target.searchParams.set("state", url.searchParams.get("state"));
    res.writeHead(302, { location: target.toString() });
    return res.end();
  }
  if (url.pathname === "/oauth/token" && req.method === "POST") {
    return json(res, 200, {
      access_token: `mcp_${crypto.randomUUID()}`,
      token_type: "Bearer",
      expires_in: 86400,
      refresh_token: `refresh_${crypto.randomUUID()}`,
      scope: "mcp:tools",
    });
  }

  const suffix = url.pathname.replace(/^\/mcp\/?/, "");
  const path = `/mcp/${encodeURIComponent(token)}${suffix ? `/${suffix}` : ""}${url.search}`;
  const proxy = http.request({
    hostname: "127.0.0.1",
    port: chatcmdPort,
    path,
    method: req.method,
    headers: { ...req.headers, host: `127.0.0.1:${chatcmdPort}` },
  }, (upstream) => {
    res.writeHead(upstream.statusCode || 502, upstream.headers);
    upstream.pipe(res);
  });
  proxy.on("error", (error) => {
    const code = ["ECONNREFUSED", "ECONNRESET"].includes(error.code) ? error.code : "UPSTREAM_ERROR";
    console.error(`[bridge] upstream unavailable (${code})`);
    if (!res.headersSent) {
      json(res, 503, { error: "chatcmd_unavailable", retryable: true }, { "retry-after": "2" });
    } else {
      res.destroy();
    }
  });
  req.pipe(proxy);
});

server.listen(bridgePort, "127.0.0.1", () => {
  console.log(`[bridge] ready on 127.0.0.1:${bridgePort}`);
});
