-- Convenience re-export so journey specs can `require("tests.e2e.support")`
-- and pull both entry points from one module.

return {
    new_mock = require("tests.e2e.support.love_mock").new,
    start = require("tests.e2e.support.journey").start,
}
