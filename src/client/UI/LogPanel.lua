--!strict
-- Log Timeline: ScrollingFrame + UIListLayout. Tiap log = kartu 40px, radius 8.

local UIStyle = require(script.Parent.UIStyle)

local MAX_ROWS = 100         -- samakan dengan batas history di LogSystem (server)
local BOTTOM_THRESHOLD = 24  -- px; dianggap "di bawah" jika selisih <= ini
local ROW_HEIGHT = 40

export type LogEntry = {
	Text: string,
	Type: string?,
	Icon: string?,
	Week: number?,
	Time: number?,
}

type RowRecord = { Frame: Frame, Key: string? }

export type LogPanel = {
	Root: Frame,
	Scroll: ScrollingFrame,
	AddLog: (self: LogPanel, text: string, logType: string?, icon: string?) -> (),
	AddEntry: (self: LogPanel, entry: LogEntry) -> (),
	Clear: (self: LogPanel) -> (),
	_rows: { RowRecord },
	_seen: { [string]: boolean },
	_autoScroll: boolean,
	_order: number,
}

local LogPanel = {}
LogPanel.__index = LogPanel

local function MaxCanvasY(scroll: ScrollingFrame): number
	return math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
end

function LogPanel.new(parent: Instance?): LogPanel
	local colors = UIStyle.Colors

	local title = UIStyle.CreateLabel({
		Name = "Title",
		Text = "📜 Timeline",
		Font = UIStyle.Fonts.Bold,
		TextSize = UIStyle.TextSize.Title,
		Size = UDim2.new(1, 0, 0, 28),
	})

	local scroll = UIStyle.CreateComponent("ScrollingFrame", {
		Name = "LogScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = colors.Muted,
	}, {
		UIStyle.CreateComponent("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- Root transparan: panel putihnya adalah Main Container di DashboardUI.
	local root = UIStyle.CreateComponent("Frame", {
		Name = "LogPanel",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, { title, scroll })

	if parent then
		root.Parent = parent
	end

	local self = setmetatable({
		Root = root,
		Scroll = scroll,
		_rows = {},
		_seen = {},
		_autoScroll = true,
		_order = 0,
	}, LogPanel)
	local panel = (self :: any) :: LogPanel

	-- Canvas membesar -> tetap di bawah selama user tidak scroll ke atas.
	scroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
		if panel._autoScroll then
			scroll.CanvasPosition = Vector2.new(0, MaxCanvasY(scroll))
		end
	end)
	-- Scroll manual menjauhi bawah -> matikan auto-scroll.
	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		panel._autoScroll = (MaxCanvasY(scroll) - scroll.CanvasPosition.Y) <= BOTTOM_THRESHOLD
	end)

	return panel
end

function LogPanel.AddEntry(self: LogPanel, entry: LogEntry)
	-- Dedupe: riwayat GetData bisa tumpang tindih dengan event LogAdded yang datang lebih dulu.
	local key: string? = nil
	if entry.Time then
		local k = ("%d|%s|%s"):format(entry.Time, tostring(entry.Week), entry.Text)
		if self._seen[k] then
			return
		end
		self._seen[k] = true
		key = k
	end

	self._order += 1
	local colors = UIStyle.Colors

	local row = UIStyle.CreateComponent("Frame", {
		Name = "LogRow",
		BackgroundColor3 = colors.RowLight,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y, -- tinggi minimum 40, melebar kalau teks 2 baris
		Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
		LayoutOrder = self._order,
		Corner = UIStyle.RadiusSmall,
	}, {
		UIStyle.CreateLabel({
			Name = "Icon",
			Text = entry.Icon or "📝",
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.fromOffset(28, ROW_HEIGHT),
		}),
		UIStyle.CreateLabel({
			Name = "Text",
			Text = entry.Text,
			Font = UIStyle.Fonts.Bold,
			TextSize = 13,
			TextColor3 = UIStyle.GetLogColor(entry.Type),
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Center,
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.fromOffset(44, 0),
			Size = UDim2.new(1, -52, 0, ROW_HEIGHT),
		}, {
			UIStyle.CreateComponent("UIPadding", {
				PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
			}),
		}),
	})
	row.Parent = self.Scroll

	table.insert(self._rows, { Frame = row, Key = key })
	while #self._rows > MAX_ROWS do
		local oldest = table.remove(self._rows, 1)
		if oldest then
			oldest.Frame:Destroy()
			if oldest.Key then
				self._seen[oldest.Key] = nil
			end
		end
	end
end

function LogPanel.AddLog(self: LogPanel, text: string, logType: string?, icon: string?)
	self:AddEntry({ Text = text, Type = logType, Icon = icon })
end

function LogPanel.Clear(self: LogPanel)
	for _, record in ipairs(self._rows) do
		record.Frame:Destroy()
	end
	table.clear(self._rows)
	table.clear(self._seen)
	self._autoScroll = true
end

return LogPanel