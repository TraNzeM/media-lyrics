-- fake_noctalia.lua: lightweight stand-in for the noctalia host used by
-- behavioral tests. Provides controllable callbacks: ordering, delay, kill.
local fake = {}
function fake.new() return { callbacks = {}, now = 0 } end
return fake
