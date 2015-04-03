﻿Type=StaticCode
Version=1.50
@EndOfDesignText@
'Code module
'Version 1.07
Sub Process_Globals
	Dim DB_REAL, DB_INTEGER, DB_BLOB, DB_TEXT As String
	DB_REAL = "REAL"
	DB_INTEGER = "INTEGER"
	DB_BLOB = "BLOB"
	DB_TEXT = "TEXT"
	Dim HtmlCSS As String
	HtmlCSS = "table {width: 100%;border: 1px solid #cef;text-align: left; }" _
		& " th { font-weight: bold;	background-color: #acf;	border-bottom: 1px solid #cef; }" _ 
		& "td,th {	padding: 4px 5px; }" _
		& ".odd {background-color: #def; } .odd td {border-bottom: 1px solid #cef; }" _
		& "a { text-decoration:none; color: #000;}"
End Sub
'Copies a database file that was added in the Files tab. The database must be copied to a writable location.
'This method copies the database to the storage card. If the storage card is not available the file is copied to the internal folder.
'The target folder is returned.
'If the database file already exists then no copying is done.
Sub CopyDBFromAssets (FileName As String) As String
	Dim TargetDir As String
	If File.ExternalWritable Then TargetDir = File.DirDefaultExternal Else TargetDir = File.DirInternal
	If File.Exists(TargetDir, FileName) = False Then
			File.Copy(File.DirAssets, FileName, TargetDir, FileName)
	End If
	Return TargetDir
End Sub
'Creates a new table with the given name.
'FieldsAndTypes - A map with the fields names as keys and the types as values.
'You can use the DB_... constants for the types.
'PrimaryKey - The column that will be the primary key. Pass empty string if not needed.
Sub CreateTable(SQL As SQL, TableName As String, FieldsAndTypes As Map, PrimaryKey As String)
	Dim sb As StringBuilder
	sb.Initialize
	sb.Append("(")
	For i = 0 To FieldsAndTypes.Size - 1
		Dim field, ftype As String
		field = FieldsAndTypes.GetKeyAt(i)
		ftype = FieldsAndTypes.GetValueAt(i)
		If i > 0 Then sb.Append(", ")
		sb.Append("[").Append(field).Append("] ").Append(ftype)
		If field = PrimaryKey Then sb.Append(" PRIMARY KEY")
	Next
	sb.Append(")")
	Dim query As String
	query = "CREATE TABLE IF NOT EXISTS [" & TableName & "] " & sb.ToString
	Log("CreateTable: " & query)
	SQL.ExecNonQuery(query)
End Sub

'Deletes the given table.
Sub DropTable(SQL As SQL, TableName As String)
	Dim query As String
	query = "DROP TABLE IF EXISTS [" & TableName & "]"
	Log("DropTable: " & query)
	SQL.ExecNonQuery(query)
End Sub
'Inserts the data to the table.
'ListOfMaps - A list with maps as items. Each map represents a record where the map keys are the columns names
'and the maps values are the values.
'Note that you should create a new map for each record (this can be done by calling Dim to redim the map).
Sub InsertMaps(SQL As SQL, TableName As String, ListOfMaps As List)
	Dim sb, columns, values As StringBuilder
	'Small check for a common error where the same map is used in a loop
	If ListOfMaps.Size > 1 AND ListOfMaps.Get(0) = ListOfMaps.Get(1) Then
		Log("Same Map found twice in list. Each item in the list should include a different map object.")
		ToastMessageShow("Same Map found twice in list. Each item in the list should include a different map object.", True)
		Return
	End If
	SQL.BeginTransaction
	Try
		For i1 = 0 To ListOfMaps.Size - 1
			sb.Initialize
			columns.Initialize
			values.Initialize
			Dim listOfValues As List
			listOfValues.Initialize
			sb.Append("INSERT INTO [" & TableName & "] (")
			Dim m As Map
			m = ListOfMaps.Get(i1)
			For i2 = 0 To m.Size - 1
				Dim col As String
				Dim value As Object	
				col = m.GetKeyAt(i2)
				value = m.GetValueAt(i2)
				If i2 > 0 Then
					columns.Append(", ")
					values.Append(", ")
				End If
				columns.Append("[").Append(col).Append("]")
				values.Append("?")
				listOfValues.Add(value)
			Next
			sb.Append(columns.ToString).Append(") VALUES (").Append(values.ToString).Append(")")
			If i1 = 0 Then Log("InsertMaps (first query out of " & ListOfMaps.Size & "): " & sb.ToString)
			SQL.ExecNonQuery2(sb.ToString, listOfValues)
		Next
		SQL.TransactionSuccessful
	Catch
		ToastMessageShow(LastException.Message, True)
		Log(LastException)
	End Try
	SQL.EndTransaction
End Sub
Sub UpdateRecord(SQL As SQL, TableName As String, Field As String, NewValue As Object, _
	WhereFieldEquals As Map)
	Dim sb As StringBuilder
	sb.Initialize
	sb.Append("UPDATE [").Append(TableName).Append("] SET [").Append(Field).Append("] = ? WHERE ")
	If WhereFieldEquals.Size = 0 Then
		Log("WhereFieldEquals map empty!")
		Return
	End If
	Dim args As List
	args.Initialize
	args.Add(NewValue)
	For i = 0 To WhereFieldEquals.Size - 1
		If i > 0 Then sb.Append(" AND ")
		sb.Append("[").Append(WhereFieldEquals.GetKeyAt(i)).Append("] = ?")
		args.Add(WhereFieldEquals.GetValueAt(i))
	Next
	Log("UpdateRecord: " & sb.ToString)
	SQL.ExecNonQuery2(sb.ToString, args)
End Sub
'Executes the query and returns the result as a list of arrays.
'Each item in the list is a strings array.
'StringArgs - Values to replace question marks in the query. Pass Null if not needed.
'Limit - Limits the results. Pass 0 for all results.
Sub ExecuteMemoryTable(SQL As SQL, Query As String, StringArgs() As String, Limit As Int) As List
	Dim c As Cursor
	If StringArgs <> Null Then 
		c = SQL.ExecQuery2(Query, StringArgs)
	Else
		c = SQL.ExecQuery(Query)
	End If
	Log("ExecuteMemoryTable: " & Query)
	Dim table As List
	table.Initialize
	If Limit > 0 Then Limit = Min(Limit, c.RowCount) Else Limit = c.RowCount
	For row = 0 To Limit - 1
		c.Position = row
		Dim values(c.ColumnCount) As String
		For col = 0 To c.ColumnCount - 1
			values(col) = c.GetString2(col)
		Next
		table.Add(values)
	Next
	c.Close
	Return table
End Sub

'Executes the query and returns a Map with the column names as the keys 
'and the first record values As the entries values.
'The keys are lower cased.
'Returns Null if no results found.
Sub ExecuteMap(SQL As SQL, Query As String, StringArgs() As String) As Map
	Dim c As Cursor
	If StringArgs <> Null Then 
		c = SQL.ExecQuery2(Query, StringArgs)
	Else
		c = SQL.ExecQuery(Query)
	End If
	Log("ExecuteMap: " & Query)
	If c.RowCount = 0 Then
		Log("No records found.")
		Return Null
	End If
	Dim res As Map
	res.Initialize
	c.Position = 0
	For i = 0 To c.ColumnCount - 1
		res.Put(c.GetColumnName(i).ToLowerCase, c.GetString2(i))
	Next
	c.Close
	Return res
End Sub
'Executes the query and fills the Spinner with the values in the first column
Sub ExecuteSpinner(SQL As SQL, Query As String, StringArgs() As String, Limit As Int, Spinner1 As Spinner)
	Spinner1.Clear
	Dim Table As List
	Table = ExecuteMemoryTable(SQL, Query, StringArgs, Limit)
	Dim Cols() As String
	For i = 0 To Table.Size - 1
		Cols = Table.Get(i)
		Spinner1.Add(Cols(0))
	Next
End Sub
'Executes the query and fills the ListView with the value.
'If TwoLines is true then the first column is mapped to the first line and the second column is mapped
'to the second line.
'In both cases the value set to the row is the array with all the records values.
Sub ExecuteListView(SQL As SQL, Query As String, StringArgs() As String, Limit As Int, ListView1 As ListView, _
	TwoLines As Boolean)
	ListView1.Clear
	Dim Table As List
	Table = ExecuteMemoryTable(SQL, Query, StringArgs, Limit)
	Dim Cols() As String
	For i = 0 To Table.Size - 1
		Cols = Table.Get(i)
		If TwoLines Then
			ListView1.AddTwoLines2(Cols(0), Cols(1), Cols)
		Else
			ListView1.AddSingleLine2(Cols(0), Cols)
		End If
	Next
End Sub
'Executes the given query and creates a Map that you can pass to JSONGenerator and generate JSON text.
'DBTypes - Lists the type of each column in the result set.
'Usage example: (don't forget to add a reference to the JSON library)
'	Dim gen As JSONGenerator
'	gen.Initialize(DBUtils.ExecuteJSON(SQL, "SELECT Id, Birthday FROM Students", Null, _
'		0, Array As String(DBUtils.DB_TEXT, DBUtils.DB_INTEGER)))
'	Dim JSONString As String
'	JSONString = gen.ToPrettyString(4)
'	Msgbox(JSONString, "")
Sub ExecuteJSON (SQL As SQL, Query As String, StringArgs() As String, Limit As Int, DBTypes As List) As Map
	Dim Table As List
	Dim c As Cursor
	If StringArgs <> Null Then 
		c = SQL.ExecQuery2(Query, StringArgs)
	Else
		c = SQL.ExecQuery(Query)
	End If
	Log("ExecuteJSON: " & Query)
	Dim table As List
	table.Initialize
	If Limit > 0 Then Limit = Min(Limit, c.RowCount) Else Limit = c.RowCount
	For row = 0 To Limit - 1
		c.Position = row
		Dim m As Map
		m.Initialize
		For i = 0 To c.ColumnCount - 1
			Select DBTypes.Get(i)
				Case DB_TEXT
					m.Put(c.GetColumnName(i), c.GetString2(i))
				Case DB_INTEGER
					m.Put(c.GetColumnName(i), c.GetLong2(i))
				Case DB_REAL
					m.Put(c.GetColumnName(i), c.GetDouble2(i))
				Case Else
					Log("Invalid type: " & DBTypes.Get(i))
			End Select
		Next
		table.Add(m)
	Next
	c.Close
	Dim root As Map
	root.Initialize
	root.Put("root", table)
	Return root
End Sub
'Creates a html text that displays the data in a table.
'The style of the table can be changed by modifying HtmlCSS variable.
Sub ExecuteHtml(SQL As SQL, Query As String, StringArgs() As String, Limit As Int, Clickable As Boolean) As String
	Dim Table As List
	Dim c As Cursor
	If StringArgs <> Null Then 
		c = SQL.ExecQuery2(Query, StringArgs)
	Else
		c = SQL.ExecQuery(Query)
	End If
	Log("ExecuteHtml: " & Query)
	If Limit > 0 Then Limit = Min(Limit, c.RowCount) Else Limit = c.RowCount
	Dim sb As StringBuilder
	sb.Initialize
	sb.Append("<html><body>").Append(CRLF)
	sb.Append("<style type='text/css'>").Append(HtmlCSS).Append("</style>").Append(CRLF)
	sb.Append("<table><tr>").Append(CRLF)
	For i = 0 To c.ColumnCount - 1
		sb.Append("<th>").Append(c.GetColumnName(i)).Append("</th>")
	Next
	sb.Append("</tr>").Append(CRLF)
	For row = 0 To Limit - 1
		c.Position = row
		If row Mod 2 = 0 Then
			sb.Append("<tr>")
		Else
			sb.Append("<tr class='odd'>")
		End If
		For i = 0 To c.ColumnCount - 1
			sb.Append("<td>")
			If Clickable Then
				sb.Append("<a href='http://").Append(i).Append(".")
				sb.Append(row)
				sb.Append(".com'>").Append(c.GetString2(i)).Append("</a>")
			Else
				sb.Append(c.GetString2(i))
			End If
			sb.Append("</td>")
		Next
		sb.Append("</tr>").Append(CRLF)
	Next
	c.Close
	sb.Append("</table></body></html>")
	Return sb.ToString
End Sub
