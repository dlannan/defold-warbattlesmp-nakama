local nk    = require("nakama")

function pprint(t, tabs)
    tabs = tabs or 0
    if type(t) ~= "table" then
        if(type(t) == "string") then 
            print(string.rep(" ",tabs).."[Type: "..type(t).."] "..t)
        else 
            print(string.rep(" ",tabs).."[Type: "..type(t).."] "..tostring(t))
        end
    else
        for k,v in pairs(t) do
            if(type(v) == "table") then 
                print(string.rep(" ", tabs)..tostring(k).."= {")
                pprint(v, tabs+2)
                print(string.rep(" ", tabs).."}")
            else
                print(string.format(string.rep(" ", tabs).."%s = %s,", tostring(k), tostring(v)))
            end
        end
    end
end

function plog(fmt, ...)
    nk.logger_info(string.format(fmt, ...))
end

function tcount(t) 
	local count = 0
	if(t == nil) then return count end
	for k,v in pairs(t) do 
		count = count + 1
	end 
	return count
end

function tclean(t)
    if type(t) == "table" then
        for k,v in pairs(t) do
            if(type(v) == "table") then 
                t[k] = tclean(v)
            elseif(type(v) == "function") then 
                t[k] = nil               
            end
        end
        return t
    end
end
