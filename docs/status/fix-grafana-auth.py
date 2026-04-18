import re

with open("/home/akushnir/code-server-enterprise-deploy/docker-compose.yml", "r") as f:
    content = f.read()

# Remove malformed lines from previous bad sed
for pat in [
    r"      GF_SERVER_SERVE_FROM_SUB_PATH:.*\n",
    r"      GF_AUTH_PROXY_ENABLED:.*\n",
    r"      GF_AUTH_PROXY_HEADER_NAME:.*\n",
    r"      GF_AUTH_PROXY_HEADER_PROPERTY:.*\n",
    r"      GF_AUTH_PROXY_AUTO_SIGN_UP:.*\n",
    r"      GF_AUTH_DISABLE_LOGIN_FORM:.*\n",
    r"      GF_AUTH_PROXY_WHITELIST:.*\n",
]:
    content = re.sub(pat, "", content)

# Fix root URL (handle both old and already-partially-updated)
content = content.replace(
    'GF_SERVER_ROOT_URL: "http://localhost:3000"',
    'GF_SERVER_ROOT_URL: "https://ide.kushnir.cloud/grafana"'
)

# Insert auth.proxy env block after root URL line
NEW_BLOCK = '''GF_SERVER_ROOT_URL: "https://ide.kushnir.cloud/grafana"
      GF_SERVER_SERVE_FROM_SUB_PATH: "true"
      GF_AUTH_PROXY_ENABLED: "true"
      GF_AUTH_PROXY_HEADER_NAME: "X-WEBAUTH-USER"
      GF_AUTH_PROXY_HEADER_PROPERTY: "email"
      GF_AUTH_PROXY_AUTO_SIGN_UP: "true"
      GF_AUTH_DISABLE_LOGIN_FORM: "true"'''

OLD = 'GF_SERVER_ROOT_URL: "https://ide.kushnir.cloud/grafana"'
if OLD in content and "GF_AUTH_PROXY_ENABLED" not in content:
    content = content.replace(OLD, NEW_BLOCK)

with open("/home/akushnir/code-server-enterprise-deploy/docker-compose.yml", "w") as f:
    f.write(content)

print("Done")
