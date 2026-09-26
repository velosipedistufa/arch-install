--- USB flash drives in the header.
--- Dark icon: not mounted. Light icon: mounted (after it is opened).
--- g u  opens the only drive (mounts first), or a list when there are several.
--- In the list, Enter / left click does the same. x unmounts.

local RUNTIME = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local JSON = RUNTIME .. "/yazi-usb.json"
local SCRIPT = os.getenv("HOME") .. "/.config/yazi/plugins/usb.yazi/volumes.py"

local DARK = "#3a4254"
local LIGHT = "#e8ecf4"

local function decode(raw)
	if not raw or raw == "" then
		return {}
	end
	local parsed = ya.json_decode(raw)
	if type(parsed) ~= "table" then
		return {}
	end
	return parsed
end

local function read_vols()
	local f = io.open(JSON, "r")
	if not f then
		return {}
	end
	local raw = f:read("*a")
	f:close()
	return decode(raw)
end

local function write_vols(raw)
	local f = io.open(JSON, "w")
	if not f then
		return
	end
	f:write(raw)
	f:close()
end

local function icon(mounted, label)
	return ui.Span(" " .. utf8.char(0xf287) .. " " .. (label or "usb") .. " "):fg(mounted and LIGHT or DARK)
end

local set_parts = ya.sync(function(self, parts)
	self.parts = parts
	self.cursor = math.max(0, math.min(self.cursor or 0, math.max(#parts - 1, 0)))
	ui.render()
end)

local move_cursor = ya.sync(function(self, delta)
	local n = #(self.parts or {})
	if n == 0 then
		self.cursor = 0
	else
		self.cursor = ya.clamp(0, (self.cursor or 0) + delta, n - 1)
	end
	ui.render()
end)

local current = ya.sync(function(self)
	return (self.parts or {})[(self.cursor or 0) + 1]
end)

local toggle_ui = ya.sync(function(self)
	if self.child then
		Modal:children_remove(self.child)
		self.child = nil
	else
		self.child = Modal:children_add(self, 10)
	end
	ui.render()
end)

local M = {
	keys = {
		{ on = "q", run = "quit" },
		{ on = "<Esc>", run = "quit" },
		{ on = "k", run = "up" },
		{ on = "<Up>", run = "up" },
		{ on = "j", run = "down" },
		{ on = "<Down>", run = "down" },
		{ on = "<Enter>", run = "open" },
		{ on = "l", run = "open" },
		{ on = "<Right>", run = "open" },
		{ on = "x", run = "unmount" },
	},
}

function M.scan()
	local out, err = Command("python3"):arg(SCRIPT):output()
	if err or not out then
		return read_vols()
	end
	write_vols(out.stdout or "[]")
	return decode(out.stdout)
end

function M.mount_point(vol)
	if vol.mounted and vol.mountpoint and vol.mountpoint ~= "" then
		return vol.mountpoint
	end
	local child, err = Command("udisksctl"):arg({ "mount", "-b", vol.path }):output()
	local text = ""
	if child then
		text = (child.stdout or "") .. (child.stderr or "")
	end
	if err and text == "" then
		text = tostring(err)
	end
	local dest = text:match(" at (.-)%s*$") or text:match(" at (.-)\n")
	if dest then
		dest = dest:gsub("%.$", ""):gsub("%s+$", "")
	end
	if not dest or dest == "" then
		ya.notify {
			title = "USB",
			content = "Could not mount " .. (vol.label or vol.path) .. "\n" .. text,
			timeout = 4,
			level = "error",
		}
		return nil
	end
	return dest
end

function M.open(vol)
	if not vol then
		return
	end
	local dest = M.mount_point(vol)
	if not dest then
		return
	end
	M.scan()
	ya.render()
	ya.emit("cd", { dest })
end

function M.unmount(vol)
	if not vol then
		return
	end
	local child, err = Command("udisksctl"):arg({ "unmount", "-b", vol.path }):output()
	local text = ""
	if child then
		text = (child.stdout or "") .. (child.stderr or "")
	end
	if err then
		ya.notify {
			title = "USB",
			content = text ~= "" and text or tostring(err),
			timeout = 4,
			level = "error",
		}
	end
	set_parts(M.scan())
end

function M:setup()
	ps.sub_remote("usb", function()
		ya.render()
	end)
	Header:children_add(function()
		local vols = read_vols()
		if #vols == 0 then
			return ui.Line {}
		end
		local spans = {}
		for _, vol in ipairs(vols) do
			spans[#spans + 1] = icon(vol.mounted, vol.label)
		end
		return ui.Line(spans)
	end, 1400, Header.RIGHT)
end

function M:entry()
	local vols = M.scan()
	if #vols == 0 then
		ya.notify { title = "USB", content = "No flash drive", timeout = 2, level = "warn" }
		return
	end
	if #vols == 1 then
		M.open(vols[1])
		return
	end

	set_parts(vols)
	toggle_ui()

	local tx, rx = ya.chan("mpsc")
	local function keys()
		while true do
			local idx = ya.which { cands = M.keys, silent = true }
			local cand = M.keys[idx]
			if not cand then
				tx:send("quit")
				break
			end
			tx:send(cand.run)
			if cand.run == "quit" or cand.run == "open" then
				break
			end
		end
	end
	local function act()
		while true do
			local run = rx:recv()
			if run == "quit" or not run then
				break
			elseif run == "up" then
				move_cursor(-1)
			elseif run == "down" then
				move_cursor(1)
			elseif run == "open" then
				M.open(current())
				break
			elseif run == "unmount" then
				M.unmount(current())
			end
		end
		local close_ui = ya.sync(function(state)
			if state.child then
				Modal:children_remove(state.child)
				state.child = nil
				ui.render()
			end
		end)
		close_ui()
	end
	ya.join(keys, act)
end

function M:new(area)
	self:layout(area)
	return self
end

function M:layout(area)
	local v = ui.Layout()
		:constraints({
			ui.Constraint.Percentage(15),
			ui.Constraint.Percentage(70),
			ui.Constraint.Percentage(15),
		})
		:split(area)
	local h = ui.Layout()
		:direction(ui.Layout.HORIZONTAL)
		:constraints({
			ui.Constraint.Percentage(15),
			ui.Constraint.Percentage(70),
			ui.Constraint.Percentage(15),
		})
		:split(v[2])
	self._area = h[2]
end

function M:reflow()
	return { self }
end

function M:redraw()
	local rows = {}
	for _, vol in ipairs(self.parts or {}) do
		local where = vol.mounted and (vol.mountpoint or "") or "not mounted"
		rows[#rows + 1] = ui.Row {
			icon(vol.mounted, vol.label),
			where,
			vol.fstype or "",
		}
	end
	return {
		ui.Clear(self._area),
		ui.Border(ui.Edge.ALL):area(self._area):type(ui.Border.ROUNDED):style(ui.Style():fg(LIGHT)),
		ui.Table(rows)
			:area(self._area:pad(ui.Pad(1, 2, 1, 2)))
			:header(ui.Row({ "Drive", "Where", "FS" }):style(ui.Style():bold()))
			:row(self.cursor or 0)
			:row_style(ui.Style():fg(LIGHT):underline())
			:widths {
				ui.Constraint.Length(24),
				ui.Constraint.Percentage(60),
				ui.Constraint.Length(10),
			},
	}
end

function M:click(event)
	local area = self._area
	if not area or not event or not event.is_left then
		return
	end
	local row = event.y - area.y - 2
	local n = #(self.parts or {})
	if row < 0 or row >= n then
		return
	end
	self.cursor = row
	M.open(self.parts[row + 1])
	if self.child then
		toggle_ui()
	end
end

function M:scroll() end

function M:touch() end

return M
