--------------------------
--        UTILS         --
--------------------------
function print(msg)
	io.stdout:write(msg)
end

function eprint(msg)
	io.stderr:write(msg)
end

function error(msg)
	eprint("pass-gen: " .. msg .. "\n")
	os.exit(1)
end

function read_wordlist(path)
	local f = io.open(path, "r")

	if not f then
		error("wordlist not readable")
	end

	local words = {}
	for word in f:lines("l") do
		table.insert(words, word)
	end

	f:close()

	return words
end

function verify_exists(flag, val)
	if val == nil then
		error("missing argument to " .. flag)
	end

	return val
end

function verify_integer(flag, val)
	local int = tonumber(val)

	if int == nil or int < 1 then
		error(string.format("invalid argument to %s, expected integer got '%s'", flag, val))
	end

	return int
end


--------------------------
--      ARGUMENTS       --
--------------------------
function print_help()
	print([[
Usage: pass-gen-lua [OPTIONS]

Options:
  -w, --word N        generate password of N words
  -s, --sep STRING    set STRING as the word separator
  -f, --file PATH     set PATH as the wordlist
  -r, --report        print report of password strength
  -h, --help          display this help and exit

Examples:
  pass-gen -w 8 -s '-'
  pass-gen -r
]])

	os.exit(0)
end

function parse_args(args)
	local opts = {
		word_count = 6,
		word_sep   = " ",
		word_file  = os.getenv("HOME") .. "/.local/lib/pass-gen/wordlist.txt",
		report     = false,
	}

	local i = 1
	while args[i] do
		local flag = args[i]
		i = i + 1

		if flag == "-w" or flag == "--word" then
			local val = verify_exists(flag, args[i])

			opts.word_count = verify_integer(flag, val)
			i = i + 1
		elseif flag == "-s" or flag == "--sep" then
			local val = verify_exists(flag, args[i])

			opts.word_sep = val
			i = i + 1
		elseif flag == "-f" or flag == "--file" then
			local val = verify_exists(flag, args[i])

			opts.word_file = val
			i = i + 1
		elseif flag == "-r" or flag == "--report" then
			opts.report = true
		elseif flag == "-h" or flag == "--help" then
			print_help()
		else
			error("invalid option " .. flag)
		end
	end

	return opts
end


--------------------------
--        REPORT        --
--------------------------
function get_cols()
	local f = io.popen("tput cols 2>/dev/null || echo 60")
	local s = f:read("*a")
	f:close()
	return tonumber(s)
end

function tounit(x, unit)
	if x < 1e9 then
		return string.format("%.0f %s", x, unit)
	else
		return string.format("%.0e %s", x, unit)
	end
end

function format_time(t)
	local minute  = 60
	local hour    = minute * 60
	local day     = hour * 24
	local year    = day * 365.25
	local century = year * 100

	if t < 1 then
		return "less than a second"
	elseif t < minute then
		return tounit(t, "seconds")
	elseif t < hour then
		return tounit(t / minute, "minutes")
	elseif t < day then
		return tounit(t / hour, "hours")
	elseif t < year then
		return tounit(t / day, "days")
	elseif t < century then
		return tounit(t / year, "years")
	else
		return tounit(t / century, "centuries")
	end
end

function print_report(pool, count)
	local entropy = math.log(pool, 2)
	local total_entropy = entropy * count
	local report = [[
entropy per word:           %.1f bits
total entropy:              %.f bits
guess times:
  1 quadrillion / second:   %s
  1 quintillion / second:   %s
  1 sextillion / second:    %s
]]

	eprint(report:format(
		entropy,
		total_entropy,
		format_time(2 ^ (total_entropy - 51)),
		format_time(2 ^ (total_entropy - 61)),
		format_time(2 ^ (total_entropy - 71))
	))

	local cols = get_cols()
	for _ = 1, cols do
		eprint("-")
	end
	eprint("\n")
end


--------------------------
--         MAIN         --
--------------------------
function main(args)
	local opts  = parse_args(args)
	local words = read_wordlist(opts.word_file)

	if opts.report then
		print_report(#words, opts.word_count)
	end

	for i = 1, opts.word_count do
		print(words[math.random(1, #words)])

		if i ~= opts.word_count then
			print(opts.word_sep)
		end
	end
end

main(_G.arg)
