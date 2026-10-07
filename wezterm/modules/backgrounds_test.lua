-- Unit tests for the pure logic in backgrounds.lua.
--
-- Run via scripts/test-backgrounds-lua.sh (needs a standalone Lua interpreter).
-- WezTerm is never required: the functions under test do not touch it, and the
-- module is side-effect free at load time (all WezTerm use lives inside
-- M.apply, which we never call here).
--
-- What this guards, and what it deliberately does not:
--   * It locks in the rotation timer's OWNERSHIP decision, whose regression is
--     what repeatedly froze background rotation. It does NOT (and cannot)
--     verify WezTerm runtime behavior -- that update-status is idle-throttled,
--     that config is multi-evaluated, that call_after fires while idle. Those
--     were found empirically; no unit test can assert how WezTerm itself acts.

local script_dir = arg[0]:match('(.*/)') or './'
local M = dofile(script_dir .. 'backgrounds.lua')

local failures = 0
local function check(name, cond)
  if cond then
    print('ok   - ' .. name)
  else
    failures = failures + 1
    print('FAIL - ' .. name)
  end
end

-- Ownership decision: proof-of-life, never id ordering ----------------------

local STALE = 150

check('claims ownership when there is no owner',
  M._should_keep_running(nil, 1, 1000, STALE) == true)

check('refreshes ownership when it is already the owner',
  M._should_keep_running({ id = 2, beat = 1000 }, 2, 1005, STALE) == true)

check('retires when another timer owns with a fresh heartbeat (accumulation cap)',
  M._should_keep_running({ id = 2, beat = 1000 }, 3, 1005, STALE) == false)

check('takes over when the owning timer heartbeat is stale (no stranding)',
  M._should_keep_running({ id = 2, beat = 1000 }, 3, 1000 + STALE + 1, STALE) == true)

check('boundary: a heartbeat exactly at the stale threshold is taken over',
  M._should_keep_running({ id = 2, beat = 1000 }, 3, 1000 + STALE, STALE) == true)

-- REGRESSION GUARD -----------------------------------------------------------
-- The exact invariant whose violation froze rotation: a *newer* timer id must
-- never displace a live owner. Earlier "newest id wins" / "install-once flag"
-- schemes advanced a GLOBAL counter on a throwaway config evaluation whose
-- timer never ran, disabling the timer that did. Here id=2 is the live owner
-- and id=3 evaluates later and ticks: id=3 must retire, id=2 must survive.
check('regression: newer timer retires against a live owner',
  M._should_keep_running({ id = 2, beat = 1010 }, 3, 1010, STALE) == false)

check('regression: live owner keeps running though a newer id exists',
  M._should_keep_running({ id = 2, beat = 1010 }, 2, 1010, STALE) == true)

-- Rotation math: repeat-free, deterministic ---------------------------------

check('current_background returns nil for an empty list',
  M._current_background({}, 60) == nil)

local list = {}
for i = 1, 12 do
  list[i] = 'img' .. i
end

local bg = M._current_background(list, 60)
local is_member = false
for _, v in ipairs(list) do
  if v == bg then
    is_member = true
  end
end
check('current_background returns a member of the list', is_member)

check('shuffled_index is deterministic for the same (count, slot)',
  M._shuffled_index(12, 5) == M._shuffled_index(12, 5))

-- One full cycle of consecutive slots must visit every index exactly once:
-- every wallpaper shows before any repeats.
local count = 12
local seen = {}
local distinct = 0
local in_range = true
for slot = 0, count - 1 do
  local idx = M._shuffled_index(count, slot)
  if idx < 1 or idx > count then
    in_range = false
  end
  if not seen[idx] then
    seen[idx] = true
    distinct = distinct + 1
  end
end
check('shuffled_index stays within [1, count]', in_range)
check('one full cycle of shuffled_index is a repeat-free permutation',
  distinct == count)

-- Per-image brightness -------------------------------------------------------

local plain_file, plain_scale = M._parse_entry('a.png')
check('parse_entry: a bare path has no brightness scale',
  plain_file == 'a.png' and plain_scale == nil)

local tagged_file, tagged_scale = M._parse_entry({ 'b.png', brightness_scale = 0.5 })
check('parse_entry: a table entry yields its path and scale',
  tagged_file == 'b.png' and tagged_scale == 0.5)

local base_hsb = { brightness = 0.4, saturation = 0.9 }
check('image_hsb: an unscaled image keeps the global hsb',
  M._image_hsb(base_hsb, { ['/x/b.png'] = 0.5 }, '/x/a.png') == base_hsb)

local scaled = M._image_hsb(base_hsb, { ['/x/b.png'] = 0.5 }, '/x/b.png')
check('image_hsb: a scaled image multiplies brightness, keeps saturation',
  math.abs(scaled.brightness - 0.2) < 1e-9 and scaled.saturation == 0.9)
check('image_hsb: never mutates the shared global hsb', base_hsb.brightness == 0.4)

-- Result --------------------------------------------------------------------

if failures > 0 then
  print(failures .. ' test(s) failed')
  os.exit(1)
end

print('all backgrounds.lua unit tests passed')
