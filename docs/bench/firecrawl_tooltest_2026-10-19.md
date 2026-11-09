# Firecrawl tooltest 2026-10-19 (upgraded deployment: local-transformers embeddings, camofox fixed)

Question: which tools work with CORRECT calls. Prior lanes failed with bad bodies and gave up after one try.
Method: full catalog enumerated via `search()`, then minimal-valid-body-first, ≥3 shaped attempts per tool before declaring broken.
Target file verified absent via glob before writing. READ ONLY except this file — no addon/test edits, no git.

## 0. Catalog (28 tools — COMPLETE, no truncation)

`search({query:"firecrawl"})` @ offset 0/9/19, remaining 0. Full path list:

1. firecrawl_agent 2. firecrawl_agent_status 3. firecrawl_check_crawl_status 4. firecrawl_credit_usage
5. firecrawl_find_tools 6. firecrawl_gov_search 7. firecrawl_map 8. firecrawl_parse
9. firecrawl_scrape 10. firecrawl_search 11. firecrawl_search_feedback 12. firecrawl_crawl
13. firecrawl_developer_search 14. firecrawl_feedback 15. firecrawl_interact 16. firecrawl_interact_stop
17. firecrawl_monitor_check 18. firecrawl_monitor_checks 19. firecrawl_monitor_create 20. firecrawl_monitor_delete
21. firecrawl_monitor_get 22. firecrawl_monitor_list 23. firecrawl_monitor_run 24. firecrawl_monitor_update
25. firecrawl_research_inspect_paper 26. firecrawl_research_read_paper 27. firecrawl_research_related_papers 28. firecrawl_research_search_papers

KEY FINDING: there is NO standalone `firecrawl_extract` tool in this catalog. Extraction = `firecrawl_scrape`
with `formats:["markdown","json"|"query"]` + `jsonOptions`/`queryOptions`, or `firecrawl_agent` with a schema.
Prior-lane "extract" failures are explained: they called a tool/shape that does not exist here.

## 1. WORKS — copy-paste recipes

### 1a. firecrawl_scrape minimal (static/SSR pages) — ~1s, 1 credit
```js
const r = await tools.firecrawl["firecrawl_scrape"]({url: "https://wago.io/OHhIsG8F4"});
// → {markdown, metadata} metadata.statusCode 200, proxyUsed "basic", creditsUsed 1. No error.
```
Caveat: on JS SPAs (wago.io) the default call returns EMPTY markdown (md_len 0) with status 200 — no error, just no content.

### 1b. firecrawl_scrape JS-SPA recipe (PROVEN on wago.io) — ~4s
```js
const r = await tools.firecrawl["firecrawl_scrape"]({url: "https://wago.io/OHhIsG8F4",
  formats: ["markdown","html"], waitFor: 3000});
// → markdown 3852 chars (wago nav shell + page content), html 336802 chars, status 200. No error.
```
`waitFor` is the load-bearing field: without it, empty markdown; with `waitFor: 3000`, full content.
Do NOT use `proxy:"stealth"` here — it flips the result to hard failure
("All scraping engines failed… [pdf, document]", wago blocking automated access).

## 2. STILL BROKEN (exact error text, attempts logged)

### 2a. firecrawl_search — "Error: Invalid request body" on ALL 5 shapes (server-side validation rejects everything)
```js
{query: "…"}                                                          // FAIL
{query: "…", sources: ["web"], limit: 5}                              // FAIL
{query: "…", limit: 5}                                                // FAIL
{query: "…", sources: [{type: "web"}]}                               // FAIL (typed-union form)
{query: "…", categories: ["developer"]}                               // FAIL
```
Verdict: NOT a body-shape problem anymore — 5/5 shapes rejected identically, fail-fast (~ms class, no backend wait).
Embeddings fix did NOT repair search. SearxNG stays the search carrier (standing lesson holds).

### 2b. firecrawl_agent — 3 attempts, 2 distinct server errors
```js
{prompt, urls, effort:"low", maxCredits:500}  // FAIL: "Unrecognized key in body -- please review the v2 API documentation for request body changes (unrecognized key(s) effort)"
{prompt}                                      // FAIL: "An error occurred. Please check your logs for more details. Error ID: d9666d7548d04160b8f4f0afaf212e9a"
{prompt, urls:["https://wago.io/OHhIsG8F4"]}  // FAIL: "An error occurred. … Error ID: 73ca25cbe36245549fa27862500e09aa"
```
Signature advertises `effort`/`maxCredits`; server rejects `effort` as unrecognized → signature/server version skew.
Minimal bodies reach the backend then die generically. Agent path unusable.

### 2c. firecrawl_developer_search — `Request failed with status code 404` (1 attempt, {query, k:5}). Unchanged from lessons.

### 2d. firecrawl_credit_usage — `Request failed with status code 500` (1 attempt, {}). Cannot check balance; credit burn is unobservable.

### 2e. scrape-LLM extract layer — fetch works, model世代 fails (2 attempts, both on top of proven §1b fetch)
- `formats:["query"]` alone → `warning: "Query was skipped because the markdown content is empty."` (no waitFor → no content → skip; combine with waitFor).
- `formats:["markdown","query"]` + waitFor + queryOptions → `answer: null, warning: "Query generation failed after all models."` Layout: page fetched (3852 chars) but every answer model failed. LLM-answer path DOWN.
- `formats:["markdown","json"]` + waitFor + jsonOptions(schema) → `json: null, warning: "JSON extraction failed: Request is missing x-opencode-session and cannot be routed efficiently. Please see https://opencode.ai/docs/go/#where-can-i-use-it"` — routing/infra failure, not body shape.

### 2f. firecrawl_map — DEGRADED (UNCONFIRMED, not conclusively broken)
3 variants, zero errors, but `links: []` every time: `{url:"https://wago.io",limit:10}`, `{url:"https://wago.io",search:"weakaura",limit:10}`, `{url:"https://addons.wago.io",limit:10}`. example.com also `[]` (correct there — single page, no sub-links). Map may be JS-blinded like §1a, or the deployment returns empty. Needs a link-rich STATIC site to adjudicate — not proven either way.

## 3. Latency classes observed
- scrape minimal: ~1s. scrape + waitFor 3000: ~4s. scrape-LLM variants: ~1s (skip) / ~4s (model-fail).
- search/dev/credit rejections: fail-fast, ms class (validation/proxy, no backend work).
- agent: reaches backend, then generic error (server-processing class, no timing recorded).
- map: fast (~350ms), empty.

## 4. Bottom line for research lanes
- Scrape-by-URL is the ONLY working Firecrawl path, and on JS sites it REQUIRES the §1b recipe (`formats:["markdown","html"], waitFor:3000`, basic proxy, never stealth).
- No LLM extraction (query/json/agent), no search, no balance check. For wago WeakAura description + custom-code presence: scrape §1b, then read the markdown/html locally — do not ask Firecrawl to answer.
- Standing lessons CONFIRMED unchanged: search broken → SearxNG carries; enumerate catalog first (28 tools, no extract tool).
