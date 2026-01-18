* Test fixture: Stata compound strings
* These strings use backtick-quote delimiters that break shell quoting

* Simple compound string
display `"Hello World"'

* Compound string with embedded quotes
display `"She said "hello" to me"'

* Compound string with special characters
local myvar = `"$100 & 50% off!"'

* Nested compound strings
display `"outer `"inner"' outer"'

* Compound string in macro
local msg `"This is a test"'
display "`msg'"

* Multi-line with compound string
display `"Line 1" ///
    "Line 2"'
