# Screenshot assets

Only publish real screenshots supplied by the user from the actual homelab. No screenshots are included yet.

Planned files in this directory:

| File | Content | Suggested caption |
|---|---|---|
| `homepage.png` | Homepage service entry point | Homepage — central entry point for the homelab services. |
| `grafana-service-health-v3.png` | Homelab Service Health V3 dashboard | Grafana Service Health V3 — eight internal HTTPS checks; values reflect the capture time. |

Before committing, inspect the full image for passwords, tokens, private addresses or URLs, account details, document titles and other personal data. Crop or redact sensitive content while keeping the operational view understandable. Record the actual capture date in the caption; do not imply continuous availability from a screenshot.

After both files exist, add these relative embeds under the root README's Screenshots section and replace its pending text:

```markdown
![Homepage service entry point](docs/assets/screenshots/homepage.png)

Homepage — central entry point for the homelab services. Captured: <actual date>.

![Grafana Service Health V3 dashboard](docs/assets/screenshots/grafana-service-health-v3.png)

Grafana Service Health V3 — eight internal HTTPS checks. Captured: <actual date>; values are a snapshot.
```

The filenames above are planned assets, not existing images. Do not add broken image embeds to the root README.
