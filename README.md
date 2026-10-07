# RoPOS

A complete restaurant and shop system for Roblox games:

- **Till:** staff ring up orders. The customer approves the payment on their own screen, and a big "Your order" screen shows each item as it's added.
- **Self-order kiosks:** customers walk up, choose eat in or take away, tap their items and pay. They get an order number.
- **Kitchen display:** every order appears as a ticket with a timer. Staff tap **Ready** when it's made.
- **Order status board:** order numbers move from **Preparing** to **Ready**, and the customer gets a "your order is ready" alert.
- **Menu boards:** live prices on the wall, with sold-out items marked.
- **Back office:** shift reports, refunds, price and stock control, 7-day reports and an audit log.

Money, stock and sales are saved and shared across every server of your game.

The demo shop, **Blox Mart**, sells classic Roblox items (Bloxy Cola, Gravity Coil, Linked Sword, Golden Crown and more), priced in pounds (£).

**You need:** [Roblox Studio](https://create.roblox.com/) (free). You don't need to write any code.

## Download

**[Download RoPOS-Studio.zip](https://github.com/JuanDosTresCuatro/roblox-pos/releases/latest/download/RoPOS-Studio.zip)**

Unzip it anywhere. Inside you'll find:

| File | What it is |
| --- | --- |
| `RoPOS.rbxlx` | A complete demo game. Open it to try RoPOS |
| `Models/` | 3 files that add RoPOS to your own game |
| `READ ME FIRST.txt` | These instructions, for offline use |
| `Scripts/` | The code as plain files, if you want to read it. You don't need these |

No Roblox Studio to hand? Download [`RoPOS-Simulator.html`](https://github.com/JuanDosTresCuatro/roblox-pos/releases/latest/download/RoPOS-Simulator.html) and double-click it to try RoPOS in your browser.

## Try the demo

1. Open **`RoPOS.rbxlx`** (double-click it, or in Studio choose **File > Open from File**).
2. Press **Play** (F5). The Blox Mart restaurant appears in front of you: a wall of screens, a counter with a till, and 2 self-order kiosks on the right.

**Order at a kiosk (as a customer):**

1. Walk up to a kiosk and click **Touch to start** on its screen.
2. Choose **Eat in** or **Take away**.
3. Tap a category on the left, then tap items to add them.
4. Press **View order**, then **Pay**.

You get an order number. It appears under **Preparing** on the order board and as a ticket on the kitchen display.

**Make the order (as staff):**

5. Click **Ready** on the order's ticket on the kitchen display. The number moves to **Ready** on the board and you get a "your order is ready" alert.
6. Click **Collected** in the Ready strip at the bottom of the kitchen display.

**Sell at the till (as staff):**

1. Walk round to the back of the counter and hold **E** on the till. The POS window opens.
2. Go to the **Shift** tab and press **Open shift**.
3. Go to the **Sell** tab, choose **Eat in** or **Take away**, and tap some items. The big "Your order" screen on the wall lists them.
4. Press **Choose customer**, pick yourself, then press **Charge**.
5. Your payment screen pops up. Press **Pay**.

The items appear in your backpack and your Cash (top right of the screen) goes down. A receipt pops up and the order goes to the kitchen like a kiosk order.

In Studio, everyone is a manager and you can charge yourself, so you can try everything on your own. To try it with a separate cashier and customer, go to **Test > Clients and Servers**, choose 2 players and press **Start**.

## Add RoPOS to your own game

1. Open your game in Roblox Studio.
2. In the **Explorer** panel, right-click **ReplicatedStorage**, choose **Insert from File...** and pick `Models/POS.rbxmx`.
3. Right-click **ServerScriptService**, choose **Insert from File...** and pick `Models/POSServer.rbxmx`.
4. Open **StarterPlayer**, right-click **StarterPlayerScripts**, choose **Insert from File...** and pick `Models/POSClient.rbxmx`.
5. Press **Play**. If your game has no till yet, RoPOS builds the demo restaurant so you can check it works.

Keep the names `POS`, `POSServer` and `POSClient` exactly as they are. The scripts find each other by name.

## Set up your shop

All the settings are in one script: **ReplicatedStorage > POS > Config**. Double-click it to open it. Each setting has a comment that explains it.

### Shop name and receipts

```lua
Config.Store = {
	Name = "Blox Mart",
	ReceiptPrefix = "BM",          -- receipts are numbered BM-000001, BM-000002, ...
	Footer = "Thanks for shopping at Blox Mart!",
}
```

### Products

Each line in `Config.Products` is one item:

```lua
{ Id = "gravitycoil", Name = "Gravity Coil", Category = "Gear", Price = 25, Stock = 10,
  Colour = rgb(120, 80, 220), Tool = "Gravity Coil" },
```

| Field | What to put |
| --- | --- |
| `Id` | A short unique name with no spaces. **Never change it** once the game is live, because sales and stock refer to it |
| `Name` | What players see |
| `Category` | One of the names in `Config.Categories` |
| `Price` | Whole pounds (£). Roblox money has no pence |
| `Stock` | How many you have. Leave it out for unlimited |
| `Colour` | The colour of the item's tile |
| `Tool` | The Tool the customer receives (see below). Leave it out if they get nothing to hold |

Managers can change prices and stock while the game runs (**Products** tab). Those changes are saved and override the numbers in Config.

### Give customers the items they buy

1. In the Explorer, find or create a Folder called **POSItems** inside **ServerStorage**.
2. Put a **Tool** in it for each product, named exactly like the product's `Tool` setting (for example `Gravity Coil`).

When a customer pays, RoPOS puts a copy of the Tool in their backpack for every one they bought. Until you add your own Tools, RoPOS makes simple coloured blocks as placeholders.

### Money

Players start with £100 in a saved `Cash` value, shown on the leaderboard. To change this, edit `Config.Currency`:

- `StartingBalance`: how much new players get.
- `Provider = "Leaderstats"`: use money your game already has. Set `StatName` to the name of your leaderstats value (for example `"Coins"`). RoPOS then leaves saving that value to your game.

### Your own equipment

Every piece of equipment is a Model (or a single Part) with a **tag**. To add one: select it, and in the **Properties** panel under **Tags**, add the tag from this table. You can have as many of each as you like.

| Equipment | Tag | What it needs |
| --- | --- | --- |
| Till | `POSRegister` | Any parts. Optional: a Part named `Screen` for the customer's "Your order" screen |
| Self-order kiosk | `POSKiosk` | A Part named `Screen`: its front face becomes the touchscreen. Make it taller than it is wide |
| Kitchen display | `POSKitchenDisplay` | A Part named `Screen` (or tag the Part itself), facing the staff |
| Order status board | `POSOrderBoard` | A Part named `Screen` (or tag the Part itself), facing the customers |
| Menu board | `POSMenuBoard` | A Part named `Screen`. Optional attribute `Category` (for example `Gear`) to show just that category |

A screen is drawn on the Part's **front** face. If yours shows on the wrong side, rotate the Part 180°.

When your equipment is in place, set `Config.Demo.SpawnRegister = false` so the demo restaurant isn't built.

### Your own till

1. Build a till model, or use a single Part.
2. Select it. In the **Properties** panel, under **Tags**, add the tag `POSRegister`.
3. Optional: add a Part named `Screen` inside the model. Its front face becomes the screen customers see. Without one, a floating screen appears above the till.
4. Optional: in **Attributes**, add `RegisterName` (text, for example `Drive-thru`). With several tills, also add `RegisterId` (text, a different short name for each till).
5. In Config, set `Config.Demo.SpawnRegister = false` so the demo counter is no longer built.

You can have as many tills as you like.

## Staff

| Role | Can |
| --- | --- |
| **Customer** | Buy things. Customers don't see the till prompt |
| **Cashier** | Sell, give discounts up to 10%, open and close shifts, look up receipts |
| **Manager** | Everything a cashier can, plus refunds, any discount, prices, stock, reports and the audit log |

**Set your staff before you publish.** In `Config.Staff`, either:

- use your Roblox group: set `GroupId` to your group's ID, then `CashierRank` and `ManagerRank` to the lowest rank number for each role, or
- list people by user ID: `Users = { [123456789] = "Manager", [987654321] = "Cashier" }`

The owner of the game is always a manager.

Studio makes everyone a manager for testing. To test the real staff rules in Studio, set `Config.Staff.StudioRole = nil`.

## Saving

In a published game, RoPOS saves money, stock, sales, reports and the audit log, and every server of your game shares them.

Studio doesn't save anything until you do both of these:

1. **File > Publish to Roblox**.
2. **Home > Game Settings > Security**, turn on **Enable Studio Access to API Services**, and press **Save**.

Until then, the POS window shows **Studio: data not saved** and everything resets when you stop testing.

## Using the till

| To | Do this |
| --- | --- |
| Start taking payments | **Shift** tab > **Open shift** |
| Sell | **Sell** tab: tap items, **Choose customer**, **Charge**. The customer presses **Pay** on their screen |
| Give a discount | Tap a percentage under **Discount** before pressing Charge |
| Cancel a payment | **Cancel payment** while it's waiting. Payments also cancel after 30 seconds |
| See takings so far | **Shift** tab > **X report** |
| End the day | **Shift** tab > **Close shift** shows the Z report |
| Refund (managers) | **Sales** tab, tap the receipt, **Refund**. Choose whether the items go back into stock |
| Change prices or stock (managers) | **Products** tab |
| See the last 7 days (managers) | **Reports** tab |
| See who did what (managers) | **Audit log** tab |
| Leave the till | Press **✕**, press Esc, or walk away |
| Eat in or take away | Choose it above the order on the **Sell** tab |
| Mark an order made | **Ready** on the kitchen display, or the **Orders** tab |
| Hand an order over | **Collected** on the kitchen display or the **Orders** tab. Ready orders also clear after 2 minutes |
| Put an order back to preparing | **Recall** on the kitchen display or the **Orders** tab |

## If something doesn't work

| Problem | Fix |
| --- | --- |
| Nothing happens when I hold E | You must be a cashier or manager (see [Staff](#staff)) and within about 2.5 m of the till |
| "needs to stand at the register" | The customer must be within 16 studs (about 4.5 m) of the till |
| The POS window closes by itself | The cashier walked more than 20 studs (about 5.6 m) from the till |
| "You don't have enough Cash" | The customer can't afford it. The cashier presses **Cancel payment**, removes some items and charges again |
| A kiosk says "Step closer" | Stand within about 3 m of the kiosk |
| A kiosk says "Someone is ordering" | Another player is using it. It frees itself when they walk away or stop tapping for 60 seconds |
| Kitchen display has no buttons | Only cashiers and managers see **Ready**, **Collected** and **Recall** |
| A screen is on the wrong side | Screens use the Part's front face. Rotate the Part 180° |
| "Prices or stock changed" | A manager changed a price, or an item sold out, while the customer was deciding. Charge again |
| Customers don't get items | Check the Tool in **ServerStorage > POSItems** has exactly the same name as the product's `Tool` setting |
| Data resets between tests | See [Saving](#saving) |
| Anything else | Open **View > Output**. RoPOS messages start with `[RoPOS]` and say what to fix |

## All settings

| Setting | Default | What it does |
| --- | --- | --- |
| `Store.Name`, `ReceiptPrefix`, `Footer` | Blox Mart, `BM` | Shown on the screens and receipts |
| Colours | white and yellow | Edit `ReplicatedStorage > POS > Palette` to rebrand every screen at once |
| `Currency.Provider` | `"Builtin"` | `"Leaderstats"` uses money your game already creates and saves |
| `Currency.StatName`, `Symbol`, `StartingBalance` | `Cash`, `£`, 100 | Prices and balances are whole pounds |
| `Tax.Enabled`, `Name`, `Inclusive` | off, `VAT`, inclusive | Each product's `TaxRate` is a percentage (20 = UK standard rate) |
| `Staff.GroupId`, `ManagerRank`, `CashierRank` | 0, 250, 10 | Roles from your group's ranks. `Users` sets people by user ID |
| `Staff.StudioRole` | `"Manager"` | Role for everyone in Studio tests. `nil` uses the real rules |
| `Discounts.Presets`, `CashierMaxPct` | 0 to 50%, 10% | Discount buttons, and the most a cashier can give |
| `Checkout.CustomerRange` | 16 studs (about 4.5 m) | How close the customer must stand |
| `Checkout.OperatorRange` | 20 studs (about 5.6 m) | The cashier is signed out beyond this |
| `Checkout.PaymentTimeout` | 30 s | Time the customer has to approve |
| `Checkout.AllowSelfCheckout` | `"Studio"` | Let staff charge themselves (Studio only by default) |
| `Checkout.GiveItems` | on | Give customers the Tools they buy |
| `Payouts.CashierCommissionPct` | 0 | Pays cashiers a share of each sale. This adds money to your game's economy |
| `Inventory.LowStockAt` | 5 | Stock badges turn amber at this level |
| `Orders.Enabled` | on | Order numbers, kitchen tickets and the order board |
| `Orders.DiningOptions` | `"Eat in"`, `"Take away"` | Asked at the kiosk and on the till. `{}` to not ask |
| `Orders.ReadyClearAfter` | 120 s | Ready orders leave the board after this if nobody marks them collected |
| `Orders.LateAfter` | 120 s, 300 s | Kitchen tickets turn amber, then red |
| `Kiosk.Enabled`, `Range`, `IdleTimeout` | on, 11 studs (about 3 m), 60 s | Self-order kiosks |
| `Data.Scope` | `"v1"` | Change it (for example to `"v2"`) to start again with empty data |
| `Demo.SpawnRegister`, `CreateItemTools` | on | Build the demo restaurant and placeholder Tools when none exist |
| `Tags` | see [Your own equipment](#your-own-equipment) | The tags RoPOS looks for |

Other scripts in your game can check a player's role with `player:GetAttribute("POSRole")`. It returns `"Customer"`, `"Cashier"` or `"Manager"`, so staff doors and uniforms can follow the same rules.

## For developers

How RoPOS works, the test suite (including a run of the real server code without Roblox), the tools and how to publish a release are in [DEVELOPMENT.md](DEVELOPMENT.md).

RoPOS started as the Roblox version of a web POS (pos-system) and keeps its pricing rules and rounding.
