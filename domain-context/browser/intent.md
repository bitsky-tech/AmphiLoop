# Browser Domain — Intent

Match this domain when the task is **browser automation**: driving a real web browser to navigate pages, click elements, fill forms, scrape DOM/a11y content, manage tabs/sessions, or interact with web UIs.

**Strong signals** (any one is enough):
- Mentions URLs, websites, web pages, login flows, forms, buttons, search results, pagination, listings.
- Mentions browsers/Chromium/Chrome/Playwright, headless mode, cookies/sessions, CAPTCHAs.
- Goal requires "open ... in a browser", "navigate to ...", "click ...", "extract ... from a site", "log in to ...", "scrape ...".

**Negative signals** (do NOT match):
- Pure HTTP/REST API calls without a browser.
- File-system, database, or local CLI orchestration with no web UI.
- LLM-only text processing.
