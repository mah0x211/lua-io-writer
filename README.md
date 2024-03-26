# lua-io-writer

[![test](https://github.com/mah0x211/lua-io-writer/actions/workflows/test.yml/badge.svg)](https://github.com/mah0x211/lua-io-writer/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/mah0x211/lua-io-writer/branch/master/graph/badge.svg)](https://codecov.io/gh/mah0x211/lua-io-writer)

A writer that writes data to a file or file descriptor.


## Installation

```
luarocks install io-writer
```


## Error Handling

the following functions return the `error` object created by https://github.com/mah0x211/lua-errno module.


## w, err = io.writer.new( f [, sec] )

create a new writer instance that writes data to a file or file descriptor.

**Parameters**

- `f:file*|string|integer`: file, filename or file descriptor.
- `sec:number`: timeout seconds. if `nil` or `<0`, wait forever.

**Returns**

- `w:writer`: a writer instance.
- `err:any`: error message.


**Example**

```lua
local dump = require('dump')
local writer = require('io.writer')

local f = assert(io.tmpfile())
local w = writer.new(f)
local n, err, again, remain = w:write('hello', ' writer ', 'world!')

f:seek('set')
print(dump({
    n = n,
    err = err,
    again = again,
    remain = remain,
    content = f:read('*a'),
}))
-- {
--     content = "hello writer world!",
--     n = 19
-- }
```


## n, err, timeout = writer:write( data [, ...] )

write data to the file or file descriptor.

**NOTE**

if the file descriptor's peer is closed, this method returns nothing.

**Parameters**

- `data:any`: data to write. if a non-string value is specified, it is converted to a string by `tostring` function.
- `...:any`: additional data to write. these are concatenated with `data`.

**Returns**

- `n:integer`: number of bytes written.
- `err:any`: error message.
- `timeout:boolean`: `true` if timed out.
