-- Spoken Wind: random pick, never the same one twice in a row.
local _, ns = ...

-- n choices; rand(m) gives 1..m (math.random by default).
function ns.NewPicker(n, rand)
	rand = rand or math.random
	local last
	return function()
		if n <= 1 then last = 1 return 1 end
		local k
		if last then
			k = rand(n - 1)
			if k >= last then k = k + 1 end
		else
			k = rand(n)
		end
		last = k
		return k
	end
end
