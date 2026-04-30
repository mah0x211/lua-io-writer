require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local fileno = require('io.fileno')
local fork = require('testcase.fork')
local writer = require('io.writer')
local pipe = require('os.pipe')
local gettime = require('time.clock').gettime
local sleep = require('time.sleep')

local TEST_TXT = 'test.txt'
local DRAIN_DELAY = 0.05

-- Fill the non-blocking pipe until the next write has to retry.
--- @param pw os.pipe.writer
--- @return integer
local function fill_pipe(pw)
    local cap = 0

    repeat
        local n, _, again = assert(pw:write(string.rep('x', 1024)))
        cap = cap + n
    until again == true

    return cap
end

--- Drain bytes from the reader side until the requested size is consumed.
--- @param pr os.pipe.reader
--- @param nbyte integer
local function drain_pipe(pr, nbyte)
    local total = 0

    while total < nbyte do
        local s, err, again = pr:read(nbyte - total)
        if s then
            total = total + #s
        elseif again then
            sleep(0.001)
        elseif err then
            error(err, 0)
        else
            error('unexpected EOF', 0)
        end
    end
end

-- Drain bytes from the reader side in a child process after the writer blocks.
--- @param pr os.pipe.reader
--- @param nbyte integer
--- @param sec? number
--- @return testcase.process
local function spawn_pipe_drain(pr, nbyte, sec)
    local p = assert(fork())
    if p:is_child() then
        local ok, err = pcall(function()
            sleep(sec or DRAIN_DELAY)
            drain_pipe(pr, nbyte)
            assert(pr:close())
        end)
        if not ok then
            io.stderr:write(err, '\n')
            os.exit(1)
        end
        os.exit(0)
    end
    return p
end

--- Create a writer backed by a full non-blocking pipe.
--- @param sec? number
--- @return os.pipe.reader
--- @return io.writer
--- @return integer
local function new_full_pipe_writer(sec)
    local pr, pw, err = pipe(true)
    assert(err == nil, err)

    local w = assert(writer.new(pw:fd(), sec))
    local cap = fill_pipe(pw)
    assert(pw:close())
    return pr, w, cap
end

--- Write after a child process drains the pipe and collect the elapsed time.
--- @param w io.writer
--- @param pr os.pipe.reader
--- @param cap integer
--- @param ... any
--- @return integer? n
--- @return any err
--- @return boolean? again
--- @return any remain
--- @return number elapsed
local function write_after_drain(w, pr, cap, ...)
    local p = spawn_pipe_drain(pr, cap)
    local t = gettime()
    local n, err, again, remain = w:write(...)
    t = gettime() - t

    local res = assert(p:wait())
    assert.equal(res.exit, 0)
    return n, err, again, remain, t
end

function testcase.before_all()
    local f = assert(io.open(TEST_TXT, 'w'))
    f:write('hello world')
    f:close()
end

function testcase.after_all()
    os.remove(TEST_TXT)
end

function testcase.new()
    local f = assert(io.tmpfile())
    local fd = fileno(f)

    -- test that create a new writer from file
    local w, err = writer.new(f)
    assert.is_nil(err)
    assert.match(w, '^io.writer: ', false)

    -- test that craete a new writer from file with timeout sec
    w, err = writer.new(f, 0.1)
    assert.is_nil(err)
    assert.match(w, '^io.writer: ', false)

    -- test that create a new writer from filename
    w, err = writer.new(TEST_TXT)
    assert.is_nil(err)
    assert.match(w, '^io.writer: ', false)

    -- test that return err if file not found
    w, err = writer.new('notfound.txt')
    assert.is_nil(w)
    assert.match(err, 'ENOENT')

    -- test that create a new writer from file descriptor
    w, err = writer.new(fd)
    assert.is_nil(err)
    assert.match(w, '^io.writer: ', false)

    -- test that return err if file descriptor is invalid
    w, err = writer.new(-1)
    assert.is_nil(w)
    assert.match(err, 'EBADF')

    -- test that return err if invalid type of argument
    w, err = writer.new(true)
    assert.is_nil(w)
    assert.match(err, 'FILE*, pathname or file descriptor expected, got boolean')

    -- Stop GC so the check observes whether writer.new validates sec before
    -- duplicating the file handle.
    local base = assert(writer.new(f))
    local basefd = base:getfd()
    assert(base:close())

    collectgarbage('stop')
    local ok, testerr = pcall(function()
        -- test that throws an error if sec is invalid
        err = assert.throws(writer.new, f, true)
        assert.match(err, 'sec must be number or nil')

        w = assert(writer.new(f))
        assert.equal(w:getfd(), basefd)
        assert(w:close())
    end)
    collectgarbage('restart')
    collectgarbage('collect')
    if not ok then
        error(testerr, 0)
    end
end

function testcase.getfd()
    -- test that get file descriptor and it is duplicated from file
    local f = assert(io.tmpfile())
    local w = assert(writer.new(f))
    assert.is_uint(w:getfd())
    assert.not_equal(w:getfd(), fileno(f))

    -- test that get file descriptor and it is duplicated from file descriptor
    local _, pw, err = pipe(true)
    assert(err == nil, err)
    w = assert(writer.new(pw:fd()))
    assert.is_uint(w:getfd())
    assert.not_equal(w:getfd(), pw:fd())
end

function testcase.write()
    local pr, pw, perr = pipe(true)
    assert(perr == nil, perr)
    local w = assert(writer.new(pw:fd()))

    -- test that write data
    local n, err, again, remain = w:write('foo', 'bar', true, 'baz')
    assert.is_nil(err)
    assert.is_nil(again)
    assert.is_nil(remain)
    assert.equal(n, 13)
    assert.equal(pr:read(n), 'foobartruebaz')

    -- test that can write data even if file descriptor is closed
    pw:close()
    n, err, again, remain = w:write('hello')
    assert.is_nil(err)
    assert.is_nil(again)
    assert.is_nil(remain)
    assert.equal(n, 5)
    assert.equal(pr:read(n), 'hello')

    -- test that return nil if peer is closed
    pr:close()
    n, err, again, remain = w:write('world')
    assert.is_nil(n)
    assert.is_nil(err)
    assert.is_nil(again)
    assert.is_nil(remain)

    -- test that throws an error if no data arguments are specified
    err = assert.throws(w.write, w)
    assert.match(err, 'data argument is required')
end

function testcase.write_retries_after_wait()
    local pr, w, cap = new_full_pipe_writer()
    local n, err, again, remain = write_after_drain(w, pr, cap, 'foo', nil,
                                                    true, 'bar')

    assert(w:close())
    assert.equal(n, 13)
    assert.is_nil(err)
    assert.is_nil(again)
    assert.is_nil(remain)
    assert.equal(pr:read(n), 'fooniltruebar')
    assert(pr:close())
end

function testcase.write_timeout()
    local pr, pw, perr = pipe(true)
    assert(perr == nil, perr)
    local w = assert(writer.new(pw:fd(), 0.3))
    -- calculate the capacity of pipe
    local cap = fill_pipe(pw)
    pr:read(cap)
    assert(pw:write(string.rep('x', cap - 4)))

    -- test that return again=true if timeout
    local t = gettime()
    local n, err, again = w:write('hello')
    t = gettime() - t
    assert.is_nil(err)
    assert.is_true(again)
    assert.equal(n, 0)
    assert.greater(t, 0.29)
    assert.less(t, 0.31)

    -- test that change timeout sec
    w:set_timeout(0.1)
    t = gettime()
    n, err, again = w:write('world')
    t = gettime() - t
    assert.is_nil(err)
    assert.is_true(again)
    assert.equal(n, 0)
    assert.greater(t, 0.09)
    assert.less(t, 0.11)

    -- test that throws an error if sec is invalid
    err = assert.throws(w.set_timeout, w, true)
    assert.match(err, 'sec must be number or nil')
end

function testcase.write_negative_timeout()
    --- Assert that a negative timeout keeps waiting until the pipe becomes
    --- writable again.
    --- @param w io.writer
    --- @param pr os.pipe.reader
    --- @param cap integer
    local assert_waits_forever = function(w, pr, cap)
        local n, err, again, remain, t = write_after_drain(w, pr, cap, 'hello')

        assert.equal(n, 5)
        assert.is_nil(err)
        assert.is_nil(again)
        assert.is_nil(remain)
        assert.greater(t, DRAIN_DELAY - 0.01)
        assert.equal(pr:read(n), 'hello')
        assert(pr:close())
    end

    local pr, w, cap = new_full_pipe_writer(-1)
    assert_waits_forever(w, pr, cap)
    assert(w:close())

    pr, w, cap = new_full_pipe_writer()
    w:set_timeout(-1)
    assert_waits_forever(w, pr, cap)
    assert(w:close())
end

function testcase.close()
    local f = assert(io.tmpfile())
    local w = assert(writer.new(f))

    -- test that close the file associated with writer
    local ok, err = w:close()
    assert.is_nil(err)
    assert.is_true(ok)

    -- test that close can be called multiple times
    ok, err = w:close()
    assert.is_nil(err)
    assert.is_true(ok)

    -- test that write method return error if writer is closed
    ok, err = w:write('hello')
    assert.match(err, 'EBADF')
    assert.is_nil(ok)

end
