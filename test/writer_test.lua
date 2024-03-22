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
end

function testcase.write()
    local pr, pw, perr = pipe(true)
    assert(perr == nil, perr)
    local w = assert(writer.new(pw:fd()))
    -- calculate the capacity of pipe
    local cap = 0
    repeat
        local n, _, again = assert(pw:write(string.rep('x', 1024)))
        cap = cap + n
    until again == true
    pr:read(cap)

    -- test that write data
    local n, err, again, remain = w:write(nil, 'foo', 'bar', true, 'baz')
    assert.is_nil(err)
    assert.is_nil(again)
    assert.is_nil(remain)
    assert.equal(n, 13)
    assert.equal(pr:read(), 'foobartruebaz')

    -- test that return again=true if deadline is expired
    assert(pw:write(string.rep('x', cap - 4)))
    local t = gettime()
    n, err, again = w:write(0.1, 'hello')
    t = gettime() - t
    assert.is_nil(err)
    assert.is_true(again)
    assert.equal(n, 0)
    assert.greater(t, 0.09)
    assert.less(t, 0.11)

    -- test that throws an error if sec is invalid
    err = assert.throws(w.write, w, true)
    assert.match(err, 'sec must be number or nil')

    -- test that throws an error if no data arguments are specified
    err = assert.throws(w.write, w)
    assert.match(err, 'data argument is required')
end

