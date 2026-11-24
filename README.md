# Receipt Ingester

A small Mac app that turns AirDropped receipt photos into rows in a Numbers spreadsheet.

Open the app, AirDrop receipt photos from your iPhone to your Mac, and each one is read automatically and added to your spreadsheet:

| Business | Cost | Payment Date | Notes | Payment (Chq#) |
|---|---|---|---|---|
| Home Depot | $42.18 | 11/23/26 | Lumber, deck screws, wood stain | 4417 |

A notification confirms every receipt, with your running totals:

> ✅ Home Depot · $42.18 · Card 4417
> This month: $412.60 · Total: $4,870.15

The original photo is filed in a **Receipts** folder next to your spreadsheet, sorted by year and month.

---

## Install (one time, about 5 minutes)

1. **Download** [**Receipt-Ingester.zip**](../../releases/latest) from the latest release (click the file name under *Assets*).
2. **Double-click** the zip in your Downloads folder. Drag **Receipt Ingester** into your **Applications** folder.
3. **Open it the first time.** Double-click **Receipt Ingester** in Applications. macOS will say it can't verify the app. That's expected for small personal apps. Click **Done**, then:
   - Open **System Settings → Privacy & Security**.
   - Scroll down and click **Open Anyway** next to "Receipt Ingester", then enter your Mac password.
4. **Paste the Claude API key** when asked. It's saved in your Mac's Keychain.
5. **Choose your spreadsheet** (for example, *Outgoing_Expenses* in iCloud Drive).
6. **Allow the permission prompts.** Each one appears once:
   - Access to the **Downloads** folder (and iCloud Drive, if asked)
   - Permission to control **Numbers**
   - **Notifications**

## Everyday use

1. **Open Receipt Ingester.** Click **Start** (or wait a few seconds). A notification says it's on.
2. **AirDrop your receipt photos** from your iPhone to the Mac. You can send several at once.
3. **Watch for the notifications.** Each receipt takes a few seconds.
4. **When you're done,** quit the app: right-click its icon in the Dock and choose **Quit** (or press ⌘Q).

The app only looks at photos that arrive *while it's open*. Old pictures in Downloads are never touched.

### Tips for good results

- **One receipt per photo**, flat and well lit, with the total and date visible.
- If a notification says **"needs a look"**, the photo was moved to **Receipts › Needs Review**. Either type the row in yourself, or retake the photo and AirDrop it again. To retry the same photo, drag it from *Needs Review* back into **Downloads** while the app is open.
- If a receipt doesn't show which card was used, the card column is left blank for you to fill in.
- Receipts already in the spreadsheet (same business, amount and date) aren't added twice.

### Please don't

- **Rename or move the spreadsheet**, or rename its column headings. (If you do, click the app's Dock icon while it's open and choose a different spreadsheet.)
- **Turn off "Keep Downloaded"** for the spreadsheet. In Finder, right-click it and make sure **Keep Downloaded** is checked.

### Settings

While the app is open, **click its Dock icon** to change the API key or the spreadsheet. You can also click **Settings…** on the start-up window.

---

## Troubleshooting

| Message | What to do |
|---|---|
| "The API key was rejected" | Get a new key from the Claude Console and enter it in Settings. |
| "Your credit balance is too low" or "spend limit" | Add credit or raise the limit in the Claude Console (Billing / Limits). |
| "Couldn't reach Claude" | Check the internet connection, then drag the photo from *Needs Review* back into Downloads. |
| "Couldn't find a table with Business and Cost columns" | The spreadsheet's headings were changed. Rename them back, or choose the right spreadsheet in Settings. |
| Nothing happens after AirDrop | Make sure the app is open (it's in the Dock), and check System Settings → Privacy & Security → Files and Folders that Downloads access is allowed. |

---

## For the maintainer

**How it works.** `src/ReceiptIngester.applescript` is a stay-open applet that checks `~/Downloads` every 3 seconds for new images (JPG, PNG, HEIC). `src/ingest.sh` converts each photo to a JPEG at most 1568 px wide with `sips`, sends it to the Claude Messages API with a forced `record_receipt` tool call, validates the fields, and returns them. The applet then writes the row through Numbers' AppleScript support, so iCloud syncing behaves exactly as if it were typed by hand. Everything uses tools built into macOS. Nothing needs to be installed.

**Column mapping.** Columns are found by heading text, so their order doesn't matter: *Business*, *Cost*, a heading containing *Date*, *Notes*, and a heading containing *Chq*, *Card* or *Payment (*. The first empty row is reused; otherwise a row is added above any footer rows. Rows whose Business contains "total" are left out of the running totals.

**Settings and secrets.** The API key lives in the login Keychain (service "Receipt Ingester API Key"). The spreadsheet path is in `defaults read com.receipt-ingester`. No personal data is stored in this repo.

**Model and cost.** The default model is Claude Haiku 5.5, about $0.0004 per receipt (well under $1 a month at 200 receipts). For tougher receipts, switch to Sonnet:

```sh
defaults write com.receipt-ingester Model claude-sonnet-5-5
```

Go back with `defaults delete com.receipt-ingester Model`. Use a dedicated Console workspace with a monthly spend limit for this key.

**Building and releasing.** GitHub Actions builds on macOS for every push and runs the tests. To publish a new download:

```sh
git tag v1.0.1 && git push origin v1.0.1
```

This creates a Release with `Receipt-Ingester.zip` attached, and the install link above always points to the latest one. After updating, macOS asks for the permissions again once, because each build gets a new ad-hoc signature.

**Tests.** `bash tests/test_ingest.sh` runs the helper against stand-ins for the macOS tools and the API (needs `python3`).
