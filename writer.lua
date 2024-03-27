--
-- Copyright (C) 2024 Masatoshi Fukunaga
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
local concat = table.concat
local isfile = require('io.isfile')
local fopen = require('io.fopen')
local fileno = require('io.fileno')
local writev = require('io.writev')
local wait_writable = require('gpoll').wait_writable
local new_deadline = require('time.clock.deadline').new
-- constants
local EINVAL = require('errno').EINVAL

--- @class io.writer
--- @field private fd integer
--- @field private file? file*
--- @field private waitsec number?
local Writer = {}

--- init
--- @param fd integer
--- @param f file*
--- @return io.writer
function Writer:init(fd, f, sec)
    self.fd = fd
    self.file = f
    self.waitsec = sec
    return self
end

--- getfd
--- @return integer fd
function Writer:getfd()
    return self.fd
end

--- write
--- @param ... string
--- @return integer? n
--- @return any err
--- @return boolean? timeout
function Writer:write(...)
    -- check arguments
    local narg = select('#', ...)
    local args = {
        ...,
    }
    assert(narg > 0, 'data argument is required')
    -- convert arguments to string
    for i = 1, narg do
        if type(args[i]) ~= 'string' then
            args[i] = tostring(args[i])
        end
    end

    local fd = self.fd
    local str = concat(args)
    local sec = self.waitsec
    local deadline = sec and new_deadline(sec)
    local n, err, again, remain = writev(fd, str)
    local total = 0
    while again do
        total = total + n
        if deadline then
            -- check deadline
            sec = deadline:remain()
            if sec <= 0 then
                return total, nil, true
            end
        end

        -- wait for writable
        fd, err, again = wait_writable(fd, sec)
        if not fd then
            return total, err, again
        end
        -- write remaining data
        n, err, again, remain = writev(fd, remain)
    end

    if n then
        total = total + n
        return total, err
    end

    -- closed by peer
end

Writer = require('metamodule').new(Writer)

--- new
--- @param file string|integer|file*
--- @param sec number?
--- @return io.writer? rdr
--- @return any err
local function new(file, sec)
    local t = type(file)
    local f, err
    if isfile(file) then
        -- duplicate the file handle
        f, err = fopen(fileno(file), 'r+')
    elseif t == 'string' then
        -- open the file with read-write mode
        f, err = fopen(file, 'r+')
    elseif t == 'number' then
        -- open the file descriptor with write mode
        f, err = fopen(file, 'w')
    else
        return nil, EINVAL:new(
                   'FILE*, pathname or file descriptor expected, got ' .. t)
    end

    if not f then
        return nil, err
    end

    assert(sec == nil or type(sec) == 'number', 'sec must be number or nil')
    return Writer(fileno(f), f, sec)
end

return {
    new = new,
}
