require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local fileno = require('io.fileno')
local writer = require('io.writer')
local pipe = require('os.pipe')
local gettime = require('time.clock').gettime

local TEST_TXT = 'test.txt'

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

    -- test that throws an error if sec is invalid
    err = assert.throws(writer.new, f, true)
    assert.match(err, 'sec must be number or nil')
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

function testcase.write_timeout()
    local pr, pw, perr = pipe(true)
    assert(perr == nil, perr)
    local w = assert(writer.new(pw:fd(), 0.1))
    -- calculate the capacity of pipe
    local cap = 0
    repeat
        local n, _, again = assert(pw:write(string.rep('x', 1024)))
        cap = cap + n
    until again == true
    pr:read(cap)

    -- test that return again=true if timeout
    assert(pw:write(string.rep('x', cap - 4)))
    local t = gettime()
    local n, err, again = w:write('hello')
    t = gettime() - t
    assert.is_nil(err)
    assert.is_true(again)
    assert.equal(n, 0)
    assert.greater(t, 0.09)
    assert.less(t, 0.11)
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
