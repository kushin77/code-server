const fs = require("fs");
const p = "/usr/lib/code-server/lib/vscode/product.json";
const product = JSON.parse(fs.readFileSync(p, "utf8"));
delete product.defaultChatAgent;
const trusted = Array.isArray(product.trustedExtensionAuthAccess) ? product.trustedExtensionAuthAccess : [];
product.trustedExtensionAuthAccess = [...new Set([...trusted, "github.copilot", "github.copilot-chat"])];
fs.writeFileSync(p, JSON.stringify(product, null, 2) + "\n");
console.log("patched:", JSON.stringify(product.trustedExtensionAuthAccess));
