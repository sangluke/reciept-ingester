-- Receipt Ingester
-- While this app is open, receipt photos AirDropped into ~/Downloads are read by Claude
-- and added as rows to a Numbers spreadsheet. Quit the app to stop.
-- Compiled as a stay-open applet by build.sh; ingest.sh lives in the app's Resources folder.

property appName : "Receipt Ingester"
property settingsDomain : "com.receipt-ingester"
property keyService : "Receipt Ingester API Key"
property pollSeconds : 3

global helperPath, numbersScript, markerPath, sheetPath, receiptsRoot, skippedFiles, isReady

on run
	set isReady to false
	set skippedFiles to {}
	try
		set helperPath to POSIX path of (path to resource "ingest.sh")
		-- Compiled when first used, on a Mac that has Numbers.
		set numbersScript to POSIX path of (path to resource "AddToNumbers.applescript")
		set supportDir to (POSIX path of (path to application support from user domain)) & "Receipt Ingester"
		do shell script "mkdir -p " & quoted form of supportDir
		set markerPath to supportDir & "/started"

		if not my hasAPIKey() then my askForAPIKey()
		set sheetPath to my readSetting("SpreadsheetPath")
		if sheetPath is "" or not my pathExists(sheetPath) then my chooseSpreadsheet()

		set answer to display dialog "Receipt Ingester is ready." & return & return & ¬
			"AirDrop receipt photos to this Mac and they'll be added to “" & my displayName(sheetPath) & "”." & return & return & ¬
			"When you're done, quit Receipt Ingester from the Dock." buttons {"Settings…", "Start"} default button "Start" ¬
			with title appName giving up after 10
		if button returned of answer is "Settings…" then my showSettings()
	on error errMsg number errNum
		if errNum is not -128 then display alert appName message errMsg
		quit
		return
	end try

	-- Only photos that arrive from now on are processed.
	do shell script "touch " & quoted form of markerPath
	set isReady to true
	my notify("Receipt Ingester is on", "AirDrop your receipts now.", "")
end run

on reopen
	-- Clicking the Dock icon while it's running opens Settings.
	try
		my showSettings()
	end try
end reopen

on idle
	if not isReady then return pollSeconds
	try
		set found to paragraphs of (do shell script "/bin/bash " & quoted form of helperPath & " scan " & quoted form of markerPath)
	on error
		set found to {}
	end try
	repeat with f in found
		set f to contents of f
		if f is not "" and skippedFiles does not contain f then
			try
				my handleFile(f)
			on error errMsg
				my notify("Something went wrong", errMsg, "")
				set end of skippedFiles to f
			end try
		end if
	end repeat
	return pollSeconds
end idle

on quit
	if isReady then my notify("Receipt Ingester is off", "AirDropped photos won't be added until you open it again.", "")
	continue quit
end quit

-- ───────────────────────── Receipt handling ─────────────────────────

on handleFile(f)
	set fileName to do shell script "basename " & quoted form of f
	try
		set res to paragraphs of (do shell script "/bin/bash " & quoted form of helperPath & " process " & quoted form of f)
	on error errMsg
		set res to {"ERROR", errMsg, "END"}
	end try
	set status to item 1 of res
	set reviewFolder to receiptsRoot & "/Needs Review"

	if status is "NOTRECEIPT" then
		set end of skippedFiles to f
		my notify("Skipped " & fileName, "This doesn't look like a receipt, so it was left in Downloads.", "")
		return
	end if

	if status is not "OK" then
		set reason to "Unknown problem."
		if (count of res) ≥ 2 then set reason to item 2 of res
		my moveFile(f, reviewFolder, "Needs review - " & my baseName(fileName))
		if status is "NEEDSREVIEW" then
			my notify("⚠️ Receipt needs a look", reason, "Moved to Receipts › Needs Review")
		else
			my notify("⚠️ Couldn't read " & fileName, reason, "Moved to Receipts › Needs Review")
		end if
		return
	end if

	set biz to item 2 of res
	set cents to (item 3 of res) as integer
	set ymd to item 4 of res
	set itemNotes to item 5 of res
	set last4 to item 6 of res
	set amountText to my formatMoney(cents / 100)

	try
		set outcome to run script (POSIX file numbersScript) with parameters {sheetPath, biz, cents / 100, ymd, itemNotes, last4}
	on error errMsg
		my moveFile(f, reviewFolder, "Not added - " & my baseName(fileName))
		my notify("⚠️ Couldn't add " & biz & " " & amountText, errMsg, "Photo moved to Receipts › Needs Review")
		return
	end try

	if wasDuplicate of outcome then
		my moveFile(f, reviewFolder, "Duplicate - " & ymd & " " & biz & " " & amountText)
		my notify("Already logged: " & biz & " " & amountText, "This receipt is already in the spreadsheet, so it wasn't added again.", "")
		return
	end if

	my moveFile(f, receiptsRoot & "/" & (text 1 thru 4 of ymd) & "/" & (text 6 thru 7 of ymd), ymd & " " & biz & " " & amountText)
	set cardText to ""
	if last4 is not "" then set cardText to " · Card " & last4
	my notify("✅ " & biz & " · " & amountText & cardText, ¬
		"This month: " & my formatMoney(monthTotal of outcome) & " · Total: " & my formatMoney(allTotal of outcome), itemNotes)
end handleFile

-- ───────────────────────── Setup & settings ─────────────────────────

on showSettings()
	set choice to choose from list {"Change Claude API key", "Choose a different spreadsheet"} ¬
		with title appName with prompt "Adding receipts to:" & return & my displayName(sheetPath) & return & return & "What would you like to change?" ¬
		OK button name "Change" cancel button name "Done"
	if choice is false then return
	if item 1 of choice is "Change Claude API key" then
		my askForAPIKey()
	else
		my chooseSpreadsheet()
	end if
end showSettings

on askForAPIKey()
	repeat
		set answer to display dialog "Paste the Claude API key (it starts with sk-ant-)." & return & return & ¬
			"It's stored securely in this Mac's Keychain." default answer "" with hidden answer ¬
			buttons {"Cancel", "Save"} default button "Save" with title appName
		set k to my trim(text returned of answer)
		if k starts with "sk-ant-" then exit repeat
		display alert "That doesn't look like a Claude API key." message "API keys start with sk-ant-. Please try again."
	end repeat
	do shell script "security add-generic-password -U -a receipt-ingester -s " & quoted form of keyService & " -w " & quoted form of k
end askForAPIKey

on chooseSpreadsheet()
	repeat
		set f to choose file with prompt "Choose the Numbers spreadsheet where receipts should be added:"
		set p to POSIX path of f
		if p ends with "/" then set p to text 1 thru -2 of p
		if p ends with ".numbers" then exit repeat
		display alert "Please choose a Numbers spreadsheet." message "The file name should end in .numbers."
	end repeat
	set sheetPath to p
	do shell script "defaults write " & settingsDomain & " SpreadsheetPath " & quoted form of p
	my setReceiptsRoot()
end chooseSpreadsheet

on setReceiptsRoot()
	-- Photos are filed in a "Receipts" folder next to the spreadsheet.
	set receiptsRoot to (do shell script "dirname " & quoted form of sheetPath) & "/Receipts"
end setReceiptsRoot

on hasAPIKey()
	return (do shell script "security find-generic-password -s " & quoted form of keyService & " >/dev/null 2>&1 && echo yes || echo no") is "yes"
end hasAPIKey

on readSetting(settingName)
	try
		set v to do shell script "defaults read " & settingsDomain & " " & settingName
		if settingName is "SpreadsheetPath" then
			set sheetPath to v
			my setReceiptsRoot()
		end if
		return v
	on error
		return ""
	end try
end readSetting

-- ───────────────────────── Helpers ─────────────────────────

on moveFile(f, destFolder, newName)
	try
		do shell script "/bin/bash " & quoted form of helperPath & " move " & quoted form of f & " " & quoted form of destFolder & " " & quoted form of newName
	on error
		set end of skippedFiles to f
	end try
end moveFile

on notify(theTitle, theMessage, theSubtitle)
	display notification theMessage with title theTitle subtitle theSubtitle
end notify



on formatMoney(amount)
	set isNegative to amount < 0
	if isNegative then set amount to -amount
	set totalCents to round (amount * 100) rounding as taught in school
	set dollars to totalCents div 100
	set centsPart to totalCents mod 100
	set dollarText to dollars as text
	set grouped to ""
	repeat while (length of dollarText) > 3
		set grouped to "," & (text -3 thru -1 of dollarText) & grouped
		set dollarText to text 1 thru -4 of dollarText
	end repeat
	set centsText to centsPart as text
	if centsPart < 10 then set centsText to "0" & centsText
	set moneyText to "$" & dollarText & grouped & "." & centsText
	if isNegative then set moneyText to "-" & moneyText
	return moneyText
end formatMoney

on displayName(p)
	return do shell script "basename " & quoted form of p & " .numbers"
end displayName

on baseName(fileName)
	set AppleScript's text item delimiters to "."
	set parts to text items of fileName
	if (count of parts) > 1 then set parts to items 1 thru -2 of parts
	set b to parts as text
	set AppleScript's text item delimiters to ""
	return b
end baseName

on trim(s)
	return do shell script "printf '%s' " & quoted form of s & " | tr -d '[:space:]'"
end trim
