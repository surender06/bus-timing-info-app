const http = require("http");
const fs = require("fs/promises");
const path = require("path");

const PORT = process.env.PORT || 4173;
const ROOT = __dirname;
const DATA_FILE = path.join(ROOT, "data.json");
const DRIVER_KEY = process.env.DRIVER_KEY || "driver123";
const ADMIN_KEY = process.env.ADMIN_KEY || "admin123";

const contentTypes = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8"
};

async function readData() {
  const raw = await fs.readFile(DATA_FILE, "utf8");
  return JSON.parse(raw);
}

async function writeData(data) {
  await fs.writeFile(DATA_FILE, `${JSON.stringify(data, null, 2)}\n`, "utf8");
}

function sendJson(response, statusCode, payload) {
  response.writeHead(statusCode, { "Content-Type": "application/json; charset=utf-8" });
  response.end(JSON.stringify(payload));
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    let body = "";
    request.on("data", (chunk) => {
      body += chunk;
      if (body.length > 1_000_000) {
        request.destroy();
        reject(new Error("Request body is too large"));
      }
    });
    request.on("end", () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch {
        reject(new Error("Invalid JSON"));
      }
    });
    request.on("error", reject);
  });
}

function cleanRoute(route) {
  return {
    number: String(route.number || "").trim().toUpperCase(),
    from: String(route.from || "").trim(),
    to: String(route.to || "").trim(),
    fare: Number(route.fare || 0),
    duration: String(route.duration || "").trim(),
    stops: Array.isArray(route.stops) ? route.stops.map(String).map((item) => item.trim()).filter(Boolean) : [],
    timings: Array.isArray(route.timings) ? route.timings.map(String).map((item) => item.trim()).filter(Boolean) : []
  };
}

function hasDriverAccess(request) {
  return request.headers["x-driver-key"] === DRIVER_KEY || request.headers["x-admin-key"] === ADMIN_KEY;
}

function hasAdminAccess(request) {
  return request.headers["x-admin-key"] === ADMIN_KEY;
}

async function handleApi(request, response, url) {
  const data = await readData();
  data.routes ||= [];
  data.driverUpdates ||= {};
  data.feedback ||= [];

  if (request.method === "GET" && url.pathname === "/api/routes") {
    sendJson(response, 200, data.routes);
    return;
  }

  if (request.method === "POST" && url.pathname === "/api/routes") {
    if (!hasAdminAccess(request)) {
      sendJson(response, 401, { error: "Admin password is required." });
      return;
    }

    const route = cleanRoute(await readBody(request));
    if (!route.number || !route.from || !route.to || !route.stops.length || !route.timings.length) {
      sendJson(response, 400, { error: "Bus number, from, to, stops, and timings are required." });
      return;
    }

    const index = data.routes.findIndex((item) => item.number.toLowerCase() === route.number.toLowerCase());
    if (index >= 0) {
      data.routes[index] = route;
    } else {
      data.routes.push(route);
    }

    await writeData(data);
    sendJson(response, 200, route);
    return;
  }

  if (request.method === "DELETE" && url.pathname.startsWith("/api/routes/")) {
    if (!hasAdminAccess(request)) {
      sendJson(response, 401, { error: "Admin password is required." });
      return;
    }

    const number = decodeURIComponent(url.pathname.replace("/api/routes/", ""));
    data.routes = data.routes.filter((route) => route.number !== number);
    delete data.driverUpdates[number];
    await writeData(data);
    sendJson(response, 200, { ok: true });
    return;
  }

  if (request.method === "GET" && url.pathname === "/api/driver-updates") {
    sendJson(response, 200, data.driverUpdates || {});
    return;
  }

  if (request.method === "POST" && url.pathname === "/api/driver-updates") {
    if (!hasDriverAccess(request)) {
      sendJson(response, 401, { error: "Driver password is required." });
      return;
    }

    const update = await readBody(request);
    const routeNumber = String(update.routeNumber || "").trim().toUpperCase();
    if (!routeNumber) {
      sendJson(response, 400, { error: "Route number is required." });
      return;
    }

    data.driverUpdates[routeNumber] = {
      driver: String(update.driver || "Driver").trim(),
      stop: String(update.stop || "Not updated").trim(),
      status: String(update.status || "On time").trim(),
      delay: String(update.delay || "0").trim(),
      updatedAt: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
    };

    await writeData(data);
    sendJson(response, 200, data.driverUpdates[routeNumber]);
    return;
  }

  if (request.method === "GET" && url.pathname === "/api/feedback") {
    sendJson(response, 200, data.feedback);
    return;
  }

  if (request.method === "POST" && url.pathname === "/api/feedback") {
    const feedback = await readBody(request);
    const entry = {
      id: Date.now().toString(),
      name: String(feedback.name || "").trim(),
      rating: Math.min(5, Math.max(1, Number(feedback.rating || 5))),
      experience: String(feedback.experience || "").trim(),
      createdAt: new Date().toISOString()
    };

    if (!entry.name || !entry.experience) {
      sendJson(response, 400, { error: "Name and experience are required." });
      return;
    }

    data.feedback.push(entry);
    await writeData(data);
    sendJson(response, 200, entry);
    return;
  }

  sendJson(response, 404, { error: "API route not found." });
}

async function serveFile(request, response, url) {
  const requested = url.pathname === "/" ? "/index.html" : url.pathname;
  const filePath = path.normalize(path.join(ROOT, requested));

  if (!filePath.startsWith(ROOT)) {
    response.writeHead(403);
    response.end("Forbidden");
    return;
  }

  try {
    const content = await fs.readFile(filePath);
    response.writeHead(200, { "Content-Type": contentTypes[path.extname(filePath)] || "application/octet-stream" });
    response.end(content);
  } catch {
    response.writeHead(404);
    response.end("Not found");
  }
}

const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, `http://${request.headers.host}`);
    if (url.pathname.startsWith("/api/")) {
      await handleApi(request, response, url);
      return;
    }
    await serveFile(request, response, url);
  } catch (error) {
    sendJson(response, 500, { error: error.message || "Server error" });
  }
});

server.listen(PORT, () => {
  console.log(`Bus app running at http://localhost:${PORT}`);
});
