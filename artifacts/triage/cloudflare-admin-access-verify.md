# Cloudflare Admin Access Verification

- Timestamp (UTC): 2026-04-20T13:42:02Z
- Base URL: https://ide.kushnir.cloud
- Expected block/challenge status codes: 302,401,403

| Endpoint | HTTP | Result | Reason | Redirect/Location |
|---|---:|---|---|---|
| /grafana/ | 302 | PASS | Returned expected block/challenge status code (oauth2_proxy) | https://kushnir.cloud/oauth2/start?rd=https://kushnir.cloud/ |
| /prometheus/ | 302 | PASS | Returned expected block/challenge status code (oauth2_proxy) | https://kushnir.cloud/oauth2/start?rd=https://kushnir.cloud/ |
| /alertmanager/ | 302 | PASS | Returned expected block/challenge status code (oauth2_proxy) | https://kushnir.cloud/oauth2/start?rd=https://kushnir.cloud/ |
| /jaeger/ | 302 | PASS | Returned expected block/challenge status code (oauth2_proxy) | https://kushnir.cloud/oauth2/start?rd=https://kushnir.cloud/ |
