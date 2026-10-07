# RoPOS for developers

How RoPOS is built, how it is tested and how to release it. For setup instructions, see [README.md](README.md).

## How it works

```
 Cashier client                      Server                              Customer client
 ──────────────                      ──────                              ───────────────
 Sell screen ── checkout.start ────▶ validate cart, role, distance
 (live totals from                   price from live catalogue
  shared Pricing)                    create pending order ── PaymentRequest ──▶ bill + countdown
                                                                               Pay / Decline
                                     ◀───────────────────── checkout.respond ──
                                     re-price (must match)
                                     debit wallet ┐ one step,
                                     take stock   ┘ no yields
                                     record sale, give Tools,
 receipt ◀──────── OrderUpdate ───── update shift and reports ── Receipt ─────▶ receipt
                                     register screen: "Thank you!"
```

- **Server-authoritative.** The client sends only product IDs and quantities. The server prices every order from its own catalogue and re-prices on approval. If anything changed, the payment is cancelled instead of charging a different amount.
- **One API, one router.** A single `RemoteFunction` carries every request as an action name (`"sales.refund"`). The router rate-limits each player, checks the role the action needs, runs it in a `pcall` and returns `{ ok, data }` or `{ ok = false, error }`. Internal errors are logged and never sent to the client.
- **The server never calls `InvokeClient`.** Server-to-client traffic goes through one `RemoteEvent`, so a client cannot hang a server thread.
- **Shared pricing.** `Pricing.luau` runs on both sides, so the cart preview always matches the charge. It is a port of the web POS pricing function, and the test suite runs the same cases as the web POS tests.

## Data and multiple servers

Each server keeps a queue of *changes* and applies them inside `UpdateAsync` transforms, so many servers can write the same key without overwriting each other. Writes are batched every 20 seconds and on shutdown.

| DataStore | Key | Contents | How it is written |
| --- | --- | --- | --- |
| `RoPOS_Wallets_v1` | `u<UserId>` | balance | Change since last save, so a refund from another server is merged |
| `RoPOS_Catalogue_v1` | `products` | price, on sale, stock per product | Queued operations (`stock -2`), versioned, other servers told by MessagingService |
| `RoPOS_Sales_v1` | `counter` | last receipt number | Atomic increment |
| | `s/<receipt>` | full sale | Once, then the refund flag. The transform refuses a second refund |
| | `recent` | latest 200 sale summaries | Merged |
| `RoPOS_Reports_v1` | `d/<YYYY-MM-DD>` | daily totals (UTC) | Per-day totals merged |
| `RoPOS_Shifts_v1` | `z/<shiftId>` | Z report | Once |
| `RoPOS_Audit_v1` | `log` | latest 500 actions | Merged |

Change `Config.Data.Scope` to start again with empty data.

## Security model

- Every remote argument is type-checked and range-checked (`Validate.luau`). Carts are capped, merged and rejected if malformed.
- Roles are resolved on the server only. The client hides staff prompts for customers, but the server checks the role on every action.
- Cashiers are limited to `Config.Discounts.CashierMaxPct`. Refunds, prices, stock, reports and the audit log need a manager.
- The customer must be within `CustomerRange` of the register, must approve the payment themselves, and can have only one payment waiting.
- The wallet debit and the stock decrement happen in one step with no yields, so two payments cannot spend the same money or the last item.

## Project layout

```
roblox-pos/
├── .github/workflows/        CI on every push, releases on v* tags
├── default.project.json      Rojo project: where each folder goes in the place
├── rokit.toml                Pinned tool versions (rojo, selene, stylua, luau-lsp, lune)
├── src/
│   ├── shared/               ReplicatedStorage.POS
│   │   ├── Config.luau       All settings and the product list
│   │   ├── Pricing.luau      Line pricing (client preview and server totals)
│   │   ├── Validate.luau     Remote input checks
│   │   ├── Aggregate.luau    Report totals that merge across servers
│   │   ├── Format.luau       Money, dates, receipt rows
│   │   ├── Palette.luau      Colours shared by the POS window, kiosks and world screens
│   │   ├── Roles.luau, Signal.luau, Net.luau
│   ├── server/               ServerScriptService.POSServer
│   │   ├── init.server.luau  Start-up order
│   │   ├── Handlers.luau     Every client action and the role it needs
│   │   └── Services/         Store, Api, Staff, Wallet, Catalogue, Checkout,
│   │                         Registers, Kiosks, Orders, Boards, Surface,
│   │                         Shifts, Sales, Reports, Audit, Demo
│   └── client/               StarterPlayerScripts.POSClient
│       ├── App.luau          Window, header, tabs, screen scaling
│       ├── PaymentPrompt.luau, Receipt.luau, Api.luau, State.luau
│       ├── UI/               Theme tokens, UI kit, toasts
│       ├── World/            Kiosk touchscreen and kitchen display (drawn on parts)
│       └── Screens/          Sell, Orders, Sales, Shift, Products, Reports, Audit
├── tests/
│   ├── Specs.luau            Unit specs for the pure modules (Luau CLI and Studio)
│   ├── simulate.luau         End-to-end run of the server code on 2 fake servers (Lune)
│   └── sim/                  The fake Roblox engine and loader used by simulate.luau
├── simulator/index.html      Browser simulator, no Roblox needed
├── studio/                   Studio-only package: place, models, scripts, READ ME FIRST.txt
├── packaging/                Builds studio/ and RoPOS-Studio.zip
└── RoPOS.rbxlx               Ready-to-open place file (built with `rojo build`)
```

## Test without Roblox

`tests/simulate.luau` runs the **real** RoPOS server code, every module unchanged, on 2 simulated game servers that share one set of DataStores. Fake players walk up to the counter and the kiosks, ring up orders, pay, decline, get refunds and change servers. 130 checks cover permissions, malformed requests, payments, timeouts, a price changing mid-payment, stock sold on 2 servers at once, a refund to a player who left, 2 managers refunding the same sale at the same moment, kiosk ordering and occupancy, order numbers, the kitchen Ready and Collected flow, the order and menu boards, reports, rate limiting and a DataStore outage.

```sh
rokit install          # once: installs lune and the other tools from rokit.toml
lune run tests/simulate
```

It ends with `RoPOS simulation: 130 passed, 0 failed`. The fake engine (`tests/sim/Engine.luau`) is stricter than Roblox in one useful way: it fails on anything a RemoteEvent or DataStore would refuse, such as a mixed table or a Color3 saved to a DataStore.

## Tools

```sh
rokit install                                   # rojo, selene, stylua, luau-lsp, lune
lune run tests/simulate                         # end-to-end run of the server code (no Roblox)
luau tests/run.luau                             # unit tests (Luau CLI)
selene src tests                                # lint
stylua --check src tests                        # formatting
rojo sourcemap -o sourcemap.json
luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json src tests
rojo build -o RoPOS.rbxlx                       # rebuild the place file after changing code
rojo serve                                      # live sync into Studio with the Rojo plugin
```

The same specs also run in the Output window at the start of every Studio play test. `globalTypes.d.luau` comes from the [luau-lsp repository](https://github.com/JohnnyMorganz/luau-lsp/tree/main/scripts).

## Build the Studio package

The [`studio/`](studio/) folder has everything Roblox Studio needs and nothing else: the demo place, one model file per Studio location (for **Insert from File**), the scripts as plain files, and a `READ ME FIRST.txt` with setup steps. To make a zip to send, run this in the repo folder:

```powershell
powershell -ExecutionPolicy Bypass -File packaging/package-studio.ps1
```

It rebuilds `studio/` from the current code and writes `RoPOS-Studio.zip`. Run it again after changing the code.

## Publish a release

Push a version tag and GitHub builds the downloads and publishes the release by itself (see `.github/workflows/release.yml`). It runs the tests first, so a broken version is never released.

```sh
git tag v1.1.0
git push origin v1.1.0
```

## Reading roles from other scripts

Every player gets a `POSRole` attribute (`"Customer"`, `"Cashier"` or `"Manager"`), so doors, uniforms and staff-only areas can use the same rules.

## Studio acceptance checklist

Run this in a **Local Server** test with 2 players (Test > Clients and Servers), and record the result before you release:

| # | Step | Expected |
| --- | --- | --- |
| 1 | Player 1 holds E on the till | POS window opens on Sell, shift shows "closed" |
| 2 | Open a shift | Header pill turns green, register screen shows "Welcome!" |
| 3 | Add 2 Bloxy Colas and 1 Boombox | Totals update, register screen shows "3 items" and the total |
| 4 | Player 2 stands at the counter, Player 1 chooses them and presses Charge | Player 2 sees the bill with countdown, the screen shows "Please approve" |
| 5 | Player 2 presses Pay | Both get a receipt, Player 2's Cash goes down, Tools appear in Player 2's backpack, Boombox stock goes down by 1 |
| 6 | Charge again and Player 2 presses Decline | Player 1 sees "declined", nothing is charged |
| 7 | Charge again and wait 30 s | Payment expires on both sides |
| 8 | Sales tab, open the receipt, Refund with restock | Player 2 gets the money back, stock returns, the receipt shows REFUNDED |
| 9 | Try to refund the same receipt again | Refused |
| 10 | Shift tab, Close shift | Z report shows 1 sale and 1 refund, net 0 |
| 11 | Open the till again, then walk more than 20 studs (about 5.6 m) away | Window closes, register screen shows "Closed" |
| 12 | Reports and Audit log tabs | The sale, refund and shift actions are listed |
| 13 | Player 2 taps **Touch to start** on a kiosk, picks Eat in, adds items and pays | Player 2 gets an order number. It shows under Preparing on the board and as a ticket on the kitchen display |
| 14 | Player 1 taps the kiosk while Player 2 is using it | It says "Someone is ordering" |
| 15 | Player 1 taps **Ready** on the ticket | The number moves to Ready, Player 2 gets "Order N is ready to collect!" |
| 16 | Player 1 taps **Collected** | The number leaves the board |
| 17 | Manager changes a Snacks price on the Products tab | The Snacks menu board shows the new price |
