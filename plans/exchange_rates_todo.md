# ExchangeRates Refactor TODO

Issues found across documentation, tests, design, and architecture.
Each item is scoped to be addressed independently.

---

## 1. Documentation Typos

Small copy errors across multiple modules. Fix in place.

- [x] **1.1** `callback_module.ex:7` — "proocessing" → "processing"
- [x] **1.2** `exchange_rates_cache.ex:3` — "inplementation" → "implementation"
- [x] **1.3** `exchange_rates_cache.ex:14` — "retriver" → "retriever"
- [x] **1.4** `exchange_rates_supervisor.ex:56` — "rumtime" → "runtime"
- [x] **1.5** `exchange_rates_supervisor.ex:74` — "eanple" → "example"
- [x] **1.6** `exchange_rates_retriever.ex:4` — "retrieveal" → "retrieval"
- [x] **1.7** `exchange_rates_retriever.ex:62` — "ot the" → "to the"
- [x] **1.8** `exchange_rates_retriever.ex:98` — "ot the" → "to the"
- [x] **1.9** `exchange_rates_retriever.ex:165` — "Updated" → "Updates" (in `reconfigure/1` doc)

---

## 2. Doc References to Non-Existent or Wrong Identifiers

These produce misleading hover docs and broken `@doc` links.

- [x] **2.1** `exchange_rates_supervisor.ex:113` — References `Money.ExchangeRates.Service.stop/0` which does not exist. The module `Money.ExchangeRates.Service` was never created. Should read `Money.ExchangeRates.Retriever.stop/0`.

- [x] **2.2** `exchange_rates.ex:113,125` — Both `@callback` docs write `%Money.ExchangeRataes.Config{}` ("Rataes"). Should be `%Money.ExchangeRates.Config{}`.

- [x] **2.3** `exchange_rates.ex:39` — The `:callback_module` config key doc says the function `rates_retrieved/2` is invoked, but the actual callback names are `latest_rates_retrieved/2` and `historic_rates_retrieved/2`. Wrong function name.

- [x] **2.4** `callback_module.ex:13` — The `@callback latest_rates_retrieved` doc says "Defines the behaviour to **retrieve** the latest exchange rates from an external data source." This callback is invoked *after* retrieval as a side-effect hook, not to perform retrieval. Doc is semantically wrong.

---

## 3. Missing or Incomplete Behaviour Callbacks

- [x] **3.1** `exchange_rates_cache.ex` — `last_updated/0` is used through `cache().last_updated()` in `Money.ExchangeRates.last_updated/0` but is **not declared as a `@callback`** in the `Money.ExchangeRates.Cache` behaviour. It is only provided via the `EtsDets` macro. Any custom cache module that implements this behaviour will silently omit `last_updated/0` and crash at runtime when `Money.ExchangeRates.last_updated/0` is called.

- [x] **3.2** `callback_module.ex` — The test support module `Money.ExchangeRates.CallbackTest` defines `def init/0` (test/support/exchange_rate_callback_module.ex:4), but `init/0` is not a `@callback` in `Money.ExchangeRates.Callback`. Either the behaviour is missing this callback (and the Retriever should call it after retrieving config), or the test module has a dead function. Needs a decision. **Decision: removed dead `def init/0` from callback mock.**

- [x] **3.3** `exchange_rates_cache.ex` — The `@callback store_latest_rates/2` and `@callback store_historic_rates/2` docs say they return `:ok`, but the typespec says `:: :ok` with no error path. Custom implementations that need to return `{:error, reason}` on failure have no way to signal it. Consider widening the return type. **Decision: kept `:ok`-only; store operations should raise on failure.**

---

## 4. Missing Tests

Modules and functions with no or almost no test coverage.

- [x] **4.1** `Money.ExchangeRates.Supervisor` — Only one test exists (`application_test.exs:10` checks `default_supervisor/0`). No tests for `start_retriever/1`, `stop_retriever/0`, `restart_retriever/0`, `delete_retriever/0`, `retriever_running?/0`, `retriever_status/0`.

- [x] **4.2** `Money.ExchangeRates.Callback` — No tests at all for the default no-op implementation or the behaviour contract.

- [x] **4.3** `Money.ExchangeRates.Cache` (behaviour module) — No functional tests. The `doctest` declaration in `money_test.exs` covers it but the module has no doctests, so nothing runs.

- [x] **4.4** `Money.ExchangeRates.Cache.EtsDets` — The macro generates `latest_rates/0`, `historic_rates/1`, `store_latest_rates/2`, `store_historic_rates/2`, and `last_updated/0` shared by both `Ets` and `Dets`. None of these generated functions are directly tested; they are only implicitly exercised through the retriever integration tests.

- [x] **4.5** `Money.ExchangeRates.Retriever` unit coverage gaps:
  - `retrieve_rates/2` (HTTP call + ETag logic) is not unit-tested; only integration-tested when the env var `OPEN_EXCHANGE_RATES_APP_ID` is set.
  - `reconfigure/1` is tested indirectly via callback tests, but the reconfiguration state change is not explicitly asserted.
  - `start/1`, `stop/0`, `restart/0`, `delete/0` lifecycle transitions are not tested.
  - `historic_rates/2` (the two-date range variant) is not tested.
  - The ETag cache path (`:not_modified` response) is not tested.

- [x] **4.6** `Money.ExchangeRates.Cache.Dets` — Only referenced by a `doctest` with no actual doctests. No tests for `init/0`, `terminate/0`, `get/1`, `put/2` or any persistence behaviour across restarts.

---

## 5. `Money.ExchangeRates.Callback` — Purpose and Design

*Context:* Added in commit `b0dc63e` ("Add exchange rates callback module and bump to 0.0.7") to allow post-retrieval side effects such as saving rates to a database via Ecto.

- [x] **5.1** The module conflates two things: the **behaviour definition** (`@callback`) and the **default no-op implementation** (`def latest_rates_retrieved`, `def historic_rates_retrieved`). This is confusing because implementing `@behaviour Money.ExchangeRates.Callback` and inheriting the default makes it look like the module provides something useful, but the defaults are pure no-ops. Consider separating the behaviour into its own file or using `@optional_callbacks` to mark these. **Decision: removed default no-ops; `Money.ExchangeRates.Callback` is now a pure behaviour. Default `callback_module` changed to `nil`; Retriever skips the call when nil.**

- [x] **5.2** Callbacks are invoked with bare `apply(callback_module, :latest_rates_retrieved, [...])` (retriever.ex:365, 383). If the configured callback module raises, the exception propagates up through `retrieve_latest_rates` and is unhandled. Add error handling or document this expectation explicitly. **Decision: documented in `@moduledoc` that implementations must not raise. Also replaced `apply/3` with direct `module.function(args)` calls since the function names are known at compile time.**

- [ ] **5.3** There is no mechanism to chain multiple callbacks or broadcast to subscribers. The single `callback_module` config key means only one module can react to rate retrievals. A more composable alternative (e.g., PubSub, a list of callbacks) should be evaluated as part of the architecture review (see §7). **Deferred to §7.**

---

## 6. `Money.ExchangeRates.Retriever` Impurity and Coupling

`Retriever` is not part of the pluggable config pipeline — it is a concrete GenServer hardcoded into the system. Custom `Money.ExchangeRates` behaviour implementations cannot replace or bypass it.

- [x] **6.1** `Money.ExchangeRates.OpenExchangeRates.get_latest_rates/1` and `get_historic_rates/2` call `Retriever.retrieve_rates/2` directly (open_exchange_rates.ex:101, 138). This means the `Money.ExchangeRates` api behaviour is implicitly coupled to the `Retriever` module's HTTP helper. Any developer implementing a custom api module must either call `Retriever.retrieve_rates/2` or re-implement HTTP fetching. **Decision: `Retriever.retrieve_rates/2` removed entirely. `OpenExchangeRates` handles HTTP and ETag caching directly, with its own ETS table. Each api module owns its transport.**

- [x] **6.2** `Money.ExchangeRates.Cache.cache/0` calls `Money.ExchangeRates.Retriever.config()` — a live GenServer call — to discover which cache module is configured (exchange_rates_cache.ex:51). If the Retriever is not running, this crashes. The cache resolution should not go through the running GenServer; it should read from config directly. This also means `Money.ExchangeRates.latest_rates/0` and friends silently depend on the Retriever being up even just to resolve the cache. **Decision: replaced `Retriever.config().cache_module` with `config().cache_module` at all four call sites in `exchange_rates.ex`.**

- [x] **6.3** `Money.ExchangeRates.latest_rates/0`, `historic_rates/1`, and `latest_rates_available?/0` each contain a `try/catch` that hardcodes the pattern `{GenServer, :call, [Money.ExchangeRates.Retriever, :config, _]}` to detect a dead Retriever (exchange_rates.ex:249, 282, 299). If the GenServer name changes or a pool is introduced, these catches silently stop working. This is a brittle approach — the Retriever check should be factored into one place (see issue 6.2 fix).

- [x] **6.4** ETag caching lives inside the `Retriever` module using a hardcoded ETS table name `:etag_cache` (retriever.ex:20). It is created in `Retriever.init/1` and is deleted when the Retriever stops. This couples HTTP-level caching to the GenServer lifecycle and makes it inaccessible to any custom HTTP implementation. **Decision: ETag logic moved into `OpenExchangeRates`, which owns its own `:open_exchange_rates_etag_cache` ETS table created in `init/1`.**

- [x] **6.6** `Money.ExchangeRates.Retriever.reconfigure/1` is not idiomatic OTP: it calls the `init/1` framework callback directly from inside `handle_call`, and it allows `cache_module` in the live GenServer state to diverge from `default_config()`, which complicates the 6.2 fix. The OTP equivalent already exists and is already documented on `delete_retriever/0`: `stop_retriever/0` → `delete_retriever/0` → `start_retriever/1`. **Decision: remove `Retriever.reconfigure/1` and its `handle_call` clause. Update tests that use it for setup/teardown to use the supervisor API instead. This is a prerequisite for 6.2.**

- [x] **6.7** `Money.ExchangeRates.Cache` is a behaviour but also exposes three concrete functions: `cache/0`, `latest_rates/0`, and `historic_rates/1`. A behaviour module should only declare `@callback`s. The concrete functions are also misplaced: `latest_rates/0` and `historic_rates/1` are dead code — no external caller uses them; `exchange_rates.ex` imports `cache/0` and calls the resolved module directly (e.g. `cache().latest_rates()`). Remove all three concrete functions from `Cache`, drop the `import Money.ExchangeRates.Cache` in `exchange_rates.ex`, and resolve the cache module inline via `default_config().cache_module`. Addressed together with 6.2.

- [x] **6.8** `Cache.Ets.get/1` and `Cache.Dets.get/1` (via `EtsDets` macro) call `:ets.lookup` / `:dets.lookup` without checking whether the table exists. If the supervisor has never been started, or if the Retriever process just crashed and has not yet been restarted, the lookup raises `ArgumentError` rather than returning `nil`. The current `try/catch` in `exchange_rates.ex` incidentally swallows this, but removing that catch (6.3) exposes callers to the exception. Fix: add an `:ets.info` / `:dets.info` guard in `get/1` that returns `nil` when the table is undefined. This is a prerequisite for 6.3. See `supervision_refactor_plan.md` Step 1c.

- [ ] **6.5** `Money.ExchangeRates.get_latest_rates/1` and `get_historic_rates/2` return `{:ok, :not_modified}` as a signal that rates are unchanged and the Retriever should read from cache. This leaks HTTP/ETag terminology into the behaviour contract. A database- or file-backed api module has no meaningful concept of `:not_modified`. Consider renaming to a transport-agnostic term (e.g., `{:ok, :unchanged}`) or removing it entirely — though removal requires api modules to have access to previously fetched rates when they detect no change, which currently only the Retriever cache holds. Tied to §7 read-path decoupling.

---

## 7. Architecture and Pipeline Refactor (from Issue #158)

The following are systemic concerns about the overall design.

- [x] **7.1** **Forced supervision startup** — The `Money.ExchangeRates.Supervisor` is always started by the application, even when `auto_start_exchange_rates_service: false`. Only the child `Retriever` is not started in that case. This forces the supervisor into `ex_money`'s supervision tree, making it awkward to integrate in umbrella apps or when the caller's supervision tree order matters (e.g., Ecto must start before the callback module). The supervisor should be opt-in and easy to start from a host application's own supervisor. **Decision: `Money.ExchangeRates.Supervisor` deleted entirely. `Retriever` updated to standard OTP `start_link/1` with opts; users add it directly to their own supervision tree. `auto_start_exchange_rate_service` config key removed.**

- [ ] **7.2** **Single Retriever bottleneck** — Only one `Money.ExchangeRates.Retriever` GenServer runs per node. Under high message volume (many `latest_rates/0` calls triggering GenServer calls), this becomes a bottleneck. The architecture should support pooled retrievers or decouple cache reads from the GenServer entirely (reads go straight to ETS, GenServer only handles scheduled updates).

- [x] **7.3** **`retrieve_every: :never` type mismatch** — `@default_retrieval_interval` is `:never` (an atom), but `Config.t` types `retrieve_every` as `non_neg_integer | nil`. The atom `:never` is neither. The check `is_integer(config.retrieve_every)` silently accepts this (falls to no-op), but it's a documentation and typespec lie. Decide: use `nil` as "no polling" and remove `:never`, or add `:never` to the typespec and handle it explicitly.

- [ ] **7.4** **`Money.ExchangeRates.Cache.EtsDets` macro** — Using a `defmacro` to share code between `Ets` and `Dets` modules is non-idiomatic. It hides the implementation, makes the generated functions hard to trace in stack traces, and cannot be tested in isolation. Replace with a regular shared module whose functions both `Ets` and `Dets` delegate to.

- [ ] **7.5** **`Money.ExchangeRates.Config` nested inside `Money.ExchangeRates`** — The `Config` struct is defined as a nested module inside `Money.ExchangeRates` (exchange_rates.ex:183). It is referenced throughout the codebase as `Money.ExchangeRates.Config`. Moving it to its own file (`lib/money/exchange_rates/config.ex`) would improve clarity and allow it to carry its own docs and typespecs without being buried.

- [ ] **7.6** **Pure helper extraction** — Rate decoding and ETag handling have been moved out of `Retriever` into `OpenExchangeRates`. The remaining pure logic still inside the GenServer module is `schedule_work`, `log`, `log_init_message`, and `seconds`. These could be extracted into module-level functions callable without the GenServer being alive, making unit testing trivial and reuse possible for custom pipeline implementations.

- [ ] **7.7** **Pluggable config pipeline** — The current pipeline is: config → `api_module.init/1` → `Retriever` (hardcoded). A custom `api_module` has no way to inject its own retriever GenServer, caching strategy, or scheduling. Design a clear, documented contract for what a fully custom exchange rates pipeline looks like, addressing the three proposals in issue #158 (lightweight functions, pluggable GenServer, pooled architecture).

- [ ] **7.9** **`Money.ExchangeRates` conflates two audiences** — The module simultaneously defines the behaviour that api modules implement (`@callback get_latest_rates/1`, `@callback get_historic_rates/2`, `@callback init/1`) and the user-facing API that end-users call (`latest_rates/0`, `historic_rates/1`, etc.). These are separate concerns for separate audiences. An api module implementor writes `@behaviour Money.ExchangeRates`, which is confusing because that name reads as the user API, not a contract to implement. The api-module callbacks could move to a dedicated `Money.ExchangeRates.Api` module, leaving `Money.ExchangeRates` as a pure user-facing API module. This is not the same cleanup as §5.1 (Callback) or §6.7 (Cache) — those removed dead/default implementations; this would extract the behaviour contract to a better-named module. Deferred: this touches the public behaviour API and is a breaking change for existing custom api modules. Evaluate as part of 7.7.

- [x] **7.8** **`historic_rates/1` in EtsDets macro** uses a bare match `{:ok, date} = Date.new(year, month, day)` without handling the `{:error, reason}` path (etsdets.ex:26). Invalid date structs passed to `historic_rates/1` will raise `MatchError` instead of returning `{:error, reason}`.

---

## 8. Full ExchangeRates Logic Audit

A sweep of all `Money.ExchangeRates.*` modules looking for dead functions, misleading or stale docs, workarounds, and general code smells not already captured above. Each finding should be fixed or escalated to §6/§7 as appropriate.

- [x] **8.1** Audit `Money.ExchangeRates` (`exchange_rates.ex`) — dead public functions, stale `@doc` references, misleading typespecs, duplicated logic, and any `try/catch` or other workarounds left over from earlier coupling (see 6.3).

- [x] **8.2** Audit `Money.ExchangeRates.Retriever` (`exchange_rates_retriever.ex`) — dead clauses, unreachable `handle_*` branches, stale comments referencing removed features (e.g. ETag cache, `reconfigure/1`), and any residual coupling to `OpenExchangeRates`.

- [ ] **8.3** Audit `Money.ExchangeRates.OpenExchangeRates` (`open_exchange_rates.ex`) — verify ETag logic is complete and correct after the move from `Retriever`; check for dead helpers, missing error paths, and undocumented assumptions.

- [ ] **8.4** Audit `Money.ExchangeRates.Cache` (`exchange_rates_cache.ex`) and both implementations (`Ets`, `Dets`) — dead callbacks, stale macro expansion artefacts, misleading `@moduledoc`/`@doc` strings, and any functions whose return types don't match their specs.

- [x] **8.5** Audit `Money.ExchangeRates.Supervisor` (`exchange_rates_supervisor.ex`) — **N/A: module deleted in 7.1.**

- [x] **8.6** Audit `Money.ExchangeRates.Callback` (`callback_module.ex`) — verify the `@moduledoc` accurately reflects the pure-behaviour, no-default-impl state after §5.1; check for any leftover references to removed defaults.

- [ ] **8.7** Audit `Money.ExchangeRates.Config` (nested in `exchange_rates.ex`) — confirm all struct fields have accurate typespecs, defaults, and `@doc` descriptions; flag any fields that are effectively dead (never read by the pipeline).

- [ ] **8.9** **`Money.ExchangeRates.Config` option validation** — Exchange-rate config is currently read via individual `Money.get_env/2` calls for top-level `:ex_money` keys (e.g. `:exchange_rates_retrieve_every`, `:api_module`). Unknown or misspelled keys (e.g. `exchange_rates_retriev_every:`) are silently dropped with no error.

  **Decision: group all exchange-rate config under a single `config :ex_money, :exchange_rates, [...]` key.** `default_config/0` will read `Application.get_env(:ex_money, :exchange_rates, [])` and call `Keyword.validate!/2` on the resulting keyword list against a short, well-named set of keys (`:retrieve_every`, `:api_module`, `:callback_module`, `:cache_module`, `:verify_peer`, `:preload_historic_rates`, `:log_success`, `:log_failure`, `:log_info`). Unknown keys raise `ArgumentError` immediately.

  `Retriever.start_link/1` (the only other keyword-list entry point) gets `Keyword.validate!(options, [:config])`.

  The `{:system, "ENV_VAR"}` indirection currently handled by `Money.get_env/2` must be preserved — add a private `resolve/2` helper that unwraps `{:system, key}` tuples and is called per-field after validation.

  **Breaking change**: flat top-level keys (`:exchange_rates_retrieve_every`, `:log_success`, etc.) are removed. Migration note required in the changelog.

  Open exchange rates keys (`:open_exchange_rates_app_id`, `:open_exchange_rates_url`, `:exchange_rates_http_client`) remain top-level `:ex_money` keys since they are read by `OpenExchangeRates.init/1`, not by `default_config/0`. They may be addressed separately.

- [ ] **8.8** **Cyclic dependency audit** — Map all inter-module calls within `Money.ExchangeRates.*` and identify any cycles (e.g. `ExchangeRates` → `Cache` → `Retriever` → `ExchangeRates`). Verify that each module's dependencies flow in one direction: user-facing API → Retriever → Cache/Api → Config. Flag any module that calls back into a higher-level module, any compile-time cycles (`alias`/`import`/`use` that form a loop), and any runtime cycles (GenServer calls that re-enter the same process or call a module that calls back into the caller). Fix or escalate each cycle found.
