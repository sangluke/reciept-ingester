-- Adds one receipt row to the Numbers spreadsheet and returns running totals.
-- Run by Receipt Ingester with: run script ... with parameters {sheetPath, business, cost, "YYYY-MM-DD", notes, last4}
-- Kept separate so it compiles on the user's Mac, where Numbers (and its scripting terms) exist.

on run {sheetPath, biz, costValue, ymd, itemNotes, last4}
	set purchaseDate to my makeDate(ymd)
	set nowDate to current date
	tell application "Numbers"
		set countBefore to count of documents
		set doc to open (POSIX file sheetPath)
		set wasOpen to ((count of documents) = countBefore)

		-- Find the table whose first row has "Business" and "Cost" headings.
		set targetTable to missing value
		repeat with s in sheets of doc
			repeat with t in tables of s
				set hdr to value of cells of row 1 of t
				if my findCol(hdr, {"business"}) > 0 and my findCol(hdr, {"cost"}) > 0 then
					set targetTable to contents of t
					exit repeat
				end if
			end repeat
			if targetTable is not missing value then exit repeat
		end repeat
		if targetTable is missing value then error "Couldn't find a table with Business and Cost columns in the spreadsheet."

		tell targetTable
			set bizCol to my findCol(hdr, {"business"})
			set costCol to my findCol(hdr, {"cost"})
			set dateCol to my findCol(hdr, {"date"})
			set notesCol to my findCol(hdr, {"notes"})
			set payCol to my findCol(hdr, {"chq", "card", "payment ("})
			set lastBody to (row count) - (footer row count)
			if lastBody < 1 then set lastBody to 1
			set bizVals to value of cells of column bizCol
			set costVals to value of cells of column costCol
			if dateCol > 0 then
				set dateVals to value of cells of column dateCol
			else
				set dateVals to {}
			end if
		end tell

		-- Running totals, duplicate check, and the first empty row.
		set monthTotal to 0
		set allTotal to 0
		set isDuplicate to false
		set targetRow to 0
		repeat with r from 2 to lastBody
			set b to item r of bizVals
			set c to item r of costVals
			set dv to missing value
			if dateCol > 0 then set dv to item r of dateVals
			if b is missing value and c is missing value then
				if targetRow = 0 then set targetRow to r
			else if (class of c is real or class of c is integer) then
				set isTotalRow to false
				if b is not missing value then
					if (b as text) contains "total" then set isTotalRow to true
				end if
				if not isTotalRow then
					set allTotal to allTotal + c
					if class of dv is date then
						if (year of dv = year of nowDate) and (month of dv = month of nowDate) then set monthTotal to monthTotal + c
						if b is not missing value and purchaseDate is not missing value then
							if ((b as text) = biz) and (my absValue(c - costValue) < 0.005) and my sameDay(dv, purchaseDate) then set isDuplicate to true
						end if
					end if
				end if
			end if
		end repeat

		if isDuplicate then
			if not wasOpen then close doc saving no
			return {wasDuplicate:true, monthTotal:monthTotal, allTotal:allTotal}
		end if

		tell targetTable
			if targetRow = 0 then
				add row below row lastBody
				set targetRow to lastBody + 1
			end if
			set value of cell bizCol of row targetRow to biz
			set alignment of cell bizCol of row targetRow to right
			set format of cell costCol of row targetRow to currency
			set value of cell costCol of row targetRow to costValue
			if dateCol > 0 and purchaseDate is not missing value then set value of cell dateCol of row targetRow to purchaseDate
			if notesCol > 0 then set value of cell notesCol of row targetRow to itemNotes
			if payCol > 0 and last4 is not "" then
				set format of cell payCol of row targetRow to text
				set value of cell payCol of row targetRow to last4
				set alignment of cell payCol of row targetRow to center
			end if
		end tell
		save doc
		if not wasOpen then close doc saving yes
	end tell

	set allTotal to allTotal + costValue
	if purchaseDate is not missing value then
		if (year of purchaseDate = year of nowDate) and (month of purchaseDate = month of nowDate) then set monthTotal to monthTotal + costValue
	end if
	return {wasDuplicate:false, monthTotal:monthTotal, allTotal:allTotal}
end run

on findCol(hdr, keys)
	repeat with k in keys
		repeat with i from 1 to count of hdr
			set h to item i of hdr
			if h is not missing value then
				if (h as text) contains (contents of k) then return i
			end if
		end repeat
	end repeat
	return 0
end findCol

on makeDate(ymd)
	if ymd is "" then return missing value
	set d to current date
	set day of d to 1
	set year of d to (text 1 thru 4 of ymd) as integer
	set month of d to (text 6 thru 7 of ymd) as integer
	set day of d to (text 9 thru 10 of ymd) as integer
	set time of d to 0
	return d
end makeDate

on sameDay(a, b)
	return (year of a = year of b) and (month of a = month of b) and (day of a = day of b)
end sameDay

on absValue(x)
	if x < 0 then return -x
	return x
end absValue
