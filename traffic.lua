-- los angeles traffic 
--
-- enc 1: circle of 5ths
-- enc 2: jump notes
-- enc 3: add/remove
-- key 2 (tap): major/minor
-- key 2 (hold) + enc 2:
-- select jump amount
-- key 3 (tap):
-- record pattern,
-- play pattern,
-- (hold) clear pattern 
--
--
--
--
--
--
--
--
-- slow down 


MusicUtil = require "musicutil"
local BeatClock = require "beatclock"
local MollyThePoly = require "molly_the_poly/lib/molly_the_poly_engine"
local pattern_time = require 'pattern_time'

engine.name = "MollyThePoly"

local options = {}
options.OUTPUT = {"Audio", "MIDI", "Audio + MIDI"}
options.STEP_LENGTH_NAMES = {"1 bar", "1/2", "1/3", "1/4", "1/6", "1/8", "1/12", "1/16", "1/24", "1/32", "1/48", "1/64"}
options.STEP_LENGTH_DIVIDERS = {1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64}
options.traffic_length_NAMES = {'sunday','rush hour', 'grid lock', 'reverse commute'}
options.traffic_length_DIVIDERS = {1, 2, 3, 4}
local triggerDuration

local gridDevice
local GRID_FRAMERATE = 30
local SCREEN_FRAMERATE = 15
local TRAIL_ANI_LENGTH = 6.0
local DOWN_ANI_LENGTH = 0.2
local gridDirty = true
local arcDirty = true
local gridLEDs = {}
local trails = {}
local downMarks = {}
local downKeys = {}
local removeAnimations = {}
local grid_w, grid_h = 16, 8


local notes = {}
local triggers = {}
local activeNotes = {}

local stepDuration 
local stepsPerBar
local tonality = 'Natural Minor'

local rootNote = math.random(12)
local octave = rootNote + (4*12)
local masterScale 
local gridScale = {}
local newGridScale = {}
local timeLast = util.time()
local currentScale
local stepsPerBar
local currentStep = 0
local bar = 0
local transposeAmount
local pivotAmount = 1
local clearBuffer 

local progression = {}
progression.isplaying = false
local patternClearer 

local prevTranspose = 60

local ar = arc.connect(1)
local midi_in_device 
	


function pitch_quantizer(n)
	local negative 
	if n < 0 then negative = true end
	n = math.abs(n)
	if n == 0 then return n end
	
	if n == 1 then n = 1 end
	if n == 2 then n = 1
	elseif n == 03 then n = 2
	elseif n == 04 then n = 2
	elseif n == 05 then n = 3
	elseif n == 06 then n = 3
	elseif n == 07 then n = 4
	elseif n == 08 then n = 4
	elseif n == 09 then n = 5
	elseif n == 10 then n = 6
	elseif n == 11 then n = 6
	elseif n == 12 then n = 7
	elseif n == 13 then n = 7
	elseif n == 14 then n = 1 + 7
	elseif n == 15 then n = 2 + 7
	elseif n == 16 then n = 2 + 7
	elseif n == 17 then n = 3 + 7
	elseif n == 18 then n = 3 + 7
	elseif n == 19 then n = 4 + 7
	elseif n == 20 then n = 4 + 7
	elseif n == 21 then n = 5 + 7
	elseif n == 22 then n = 6 + 7
	elseif n == 23 then n = 6 + 7
	elseif n == 24 then n = 7 + 7
	end
 	if negative then n = -(n) end

	return n
end


--for pattern 
function get_bar_length()
  if stepDuration == 1 then --1 bar
    stepsPerBar = 1
  elseif stepDuration == 2 then   -- "1/2"
    stepsPerBar = 2
  elseif stepDuration == 3 then   -- "1/3",
    stepsPerBar = 3
  elseif stepDuration == 4 then   -- "1/4", 
    stepsPerBar = 4
  elseif stepDuration == 5 then   -- "1/6", 
    stepsPerBar = 6
  elseif stepDuration == 6 then   -- "1/8",
    stepsPerBar = 8
  elseif stepDuration == 7 then   -- "1/12", 
    stepsPerBar = 12
  elseif stepDuration == 8 then   -- "1/16",
    stepsPerBar = 16
  elseif stepDuration == 9 then   -- "1/24",
    stepsPerBar = 24
  elseif stepDuration == 10 then  --  "1/32",
    stepsPerBar = 32
  elseif stepDuration == 11 then  --  "1/48",
    stepsPerBar = 48
  elseif stepDuration == 12 then  --  "1/64"}
    stepsPerBar = 64
	end
  return stepsPerBar
end

function change_tonality()
	if tonality == 'Natural Minor' then 
		tonality = 'Major' 
	else 
		tonality = 'Natural Minor' 
	end 
	change_scale(0, tonality)
end

function background_change_tonality()
	if progression.tonality == 'Natural Minor' then 
		progression.tonality = 'Major' 
	else 
		progression.tonality = 'Natural Minor' 
	end 
	background_change_scale(0, progression.tonality)
end

function set_octave(newOctave)
	octave = rootNote + (newOctave * 12)
end

function capture_scale()
	--print('capturing', MusicUtil.note_num_to_name(gridScale[1]))
	progression.gridscale = {}
	progression.masterscale = {}
	progression.tonality = tonality 
	progression.rootnote = rootNote
	progression.prevtranspose = prevTranspose
	
	for k,v in pairs(gridScale) do 
		progression.gridscale[k] = v
	end
	for k,v in pairs(masterScale) do 
		progression.masterscale[k] = v
	end
		
end

function change_scale(semitones,scaleType,clockwisemotion)
	local incomingScale = {}
  local notesToKeep = {}
  local incomingGridScale = {}
  local newRoot
	clockwisemotion = clockwisemotion or 1 

	if semitones == 0 and scaleType == tonality then return end
	newRoot = (rootNote + semitones) % 12
  incomingScale = MusicUtil.generate_scale_of_length(newRoot, scaleType, 128)
  --get tone map of new pitches
  for k,v in pairs(masterScale) do 
    for n_k, n_v in pairs(incomingScale) do
      if n_v == v then
        notesToKeep[k] = v 
        break
      elseif n_v ~= v then 
        if n_v - 1 == v then
          notesToKeep[k] = v + 1
          break 
        end
      else
        if n_v + 1 == v then 
          notesToKeep[k] = v - 1 
          break 
        end
      end
    end
  end
  --map scale to grid
  for k,v in pairs(notesToKeep) do
    if #incomingGridScale < 16 then
			if clockwisemotion < 0 then 
				if v >= (gridScale[1] - 1) then 
		      incomingGridScale[#incomingGridScale + 1] = v
				end
			elseif clockwisemotion > 0 then
				if v >= (gridScale[1]) then
					incomingGridScale[#incomingGridScale + 1] = v
				end
			end
		elseif #incomingGridScale == 16 then
			break
    end
  end
  --detect duplicates 
  for k,v in pairs(incomingGridScale) do
    if incomingGridScale [k] == incomingGridScale[k+1] then
			for a, b in pairs(incomingScale) do 
        if v == b then
          incomingGridScale[k+1] = incomingScale[a+1] 
          break
        end
      end
    end
  end
	gridScale = incomingGridScale
	rootNote = newRoot
	masterScale = incomingScale
	screenDirty = true
	arcDirty = true
end

function background_change_scale(semitones,scaleType,clockwisemotion)
	local incomingScale = {}
  local notesToKeep = {}
  local incomingGridScale = {}
  local newRoot
	clockwisemotion = clockwisemotion or 1 
	newRoot = (progression.rootnote + semitones) % 12
  incomingScale = MusicUtil.generate_scale_of_length(newRoot, scaleType, 128)
  --get tone map of new pitches
  for k,v in pairs(progression.masterscale) do 
    for n_k, n_v in pairs(incomingScale) do
      if n_v == v then
        notesToKeep[k] = v 
        break
      elseif n_v ~= v then 
        if n_v - 1 == v then
          notesToKeep[k] = v + 1
          break 
        end
      else
        if n_v + 1 == v then 
          notesToKeep[k] = v - 1 
          break 
        end
      end
    end
  end
  --map scale to grid
  for k,v in pairs(notesToKeep) do
    if #incomingGridScale < 16 then
			if clockwisemotion < 0 then 
				if v >= (gridScale[1] - 1) then 
		      incomingGridScale[#incomingGridScale + 1] = v
				end
			elseif clockwisemotion > 0 then
				if v >= (gridScale[1]) then
					incomingGridScale[#incomingGridScale + 1] = v
				end
			end
		elseif #incomingGridScale == 16 then
			break
    end
  end
  --detect duplicates 
  for k,v in pairs(incomingGridScale) do
    if incomingGridScale [k] == incomingGridScale[k+1] then
			for a, b in pairs(incomingScale) do 
        if v == b then
          incomingGridScale[k+1] = incomingScale[a+1] 
          break
        end
      end
    end
  end
	progression.gridscale = incomingGridScale
	progression.rootnote = newRoot
	progression.masterscale = incomingScale
end


function pivot_within_scale(pivot)

	if pivot == 0 then return end

	local counter = 0
	for mk, mv in pairs(masterScale) do
		if mv == gridScale[1] then
			for gk,gv in pairs(gridScale) do
				if not masterScale[mk + pivot + counter] then return end

				gridScale[gk] = masterScale[mk + pivot + counter]
				counter = counter + 1
			end 
			break
		end
			--[[if not masterScale[mk + pivot] then return end
			gridScale[counter] = masterScale[mk + pivot]
			counter = counter + 1
		end
		if counter == 17 then 
			counter = 1 
			break
		end]]
	end
	
end

function background_pivot_within_scale(pivot)
	local counter = 1
	for mk, mv in pairs(progression.masterscale) do
		if mv >= progression.gridscale[1] then
			if not progression.masterscale[mk + pivot] then return end

			progression.gridscale[counter] = progression.masterscale[mk + pivot]
			counter = counter + 1
		end
		if counter == 17 then 
			counter = 1 
			break
		end
	end
end


function play_progression(e)
	if pat.step <= 1 then

	prevTranspose = progression.prevtranspose
		for k,v in pairs(progression.gridscale) do 
			gridScale[k] = v
		end
		print('resetting to captured', MusicUtil.note_num_to_name(gridScale[1]))
		for k,v in pairs(progression.masterscale) do 
			masterScale[k] = v
		end
		tonality = progression.tonality
		rootNote = progression.rootnote

		screenDirty = true
	end
	if e then
		print(pat.step, e.id, e.number)
		if e.id == 'key' then
			key_event(e.number, e.state)
		elseif e.id == 'enc' then 
			enc_event(e.number, e.state)
		elseif e.id == 'midi' then
			midi_transpose_event(e.number)

		end
	end

end

function enc_event(n, delta)
  --enc 1 
	if n == 1 then
		if delta > 0 then 
			transposeAmount = 7
		elseif delta < 0 then 
			transposeAmount = -7
		end
		if util.time() - timeLast > .1 then
			change_scale(transposeAmount, tonality,delta)
		end
		--encoder 2
  elseif n == 2 then 
			local prevPivot = pivotAmount
      if delta > 0 then 
				pivotAmount = math.abs(pivotAmount) 
       elseif delta < 0 then 
				pivotAmount = pivotAmount * -1
      end
			if util.time() - timeLast > .1 then pivot_within_scale(pivotAmount) end
			pivotAmount = prevPivot
			if pivotAmount <= 0 then pivotAmount = 7 end
		--encoder 3
		elseif n == 3 then
			if delta > 0 then
			elseif delta < 0 then 
			end
		end
  timeLast = util.time()
end



function key_event(n, z)
  if z == 1 then
		clearBuffer = util.time() 
	end
	--key 1 
	if n == 1 then
	elseif n == 2 then
		if z == 0 then 
			if util.time() - clearBuffer < .5 then 
				change_tonality()
			end
		end
			--key 3 
	elseif n == 3 then 
	end
end

function midi_transpose_event(data)
	local note
	if data ~= prevTranspose then 
		note = pitch_quantizer(data - prevTranspose)
		if note then pivot_within_scale(note) end
	end
	prevTranspose = data 
end

function midi_event(data)
  local d = midi.to_msg(data)
	local note
	local e = {}
  if d.type == "note_on" then
		e.id = 'midi'
		e.number = d.note
		pat:watch(e) 
		if d.note ~= prevTranspose then 
			note = pitch_quantizer(d.note - prevTranspose)
			if note then pivot_within_scale(note) end
		end
		prevTranspose = d.note
	end
	
end

function enc(n, delta)
	local e = {}
	e.id = 'enc'
	e.number = n
	e.state = delta
	pat:watch(e) 
  --enc 1 
	if n == 1 then
		if delta > 0 then transposeAmount = 7
		elseif delta < 0 then transposeAmount = -7 end
		
		if util.time() - timeLast > .1 then
			if not progression.isplaying then
				change_scale(transposeAmount, tonality,delta)
			else
				background_change_scale(transposeAmount, tonality,delta)
			end
		end
		--encoder 2
  elseif n == 2 then 
    if not shiftA then
			local prevPivot = pivotAmount
      if delta > 0 then pivotAmount = math.abs(pivotAmount) 
      elseif delta < 0 then pivotAmount = pivotAmount * -1 end

			if util.time() - timeLast > .1 then 
				if not progression.isplaying then
					pivot_within_scale(pivotAmount) 
				else
					background_pivot_within_scale(pivotAmount)
				end
			end
			pivotAmount = prevPivot
			
		elseif shiftA then 
			--prevPivot = pivotAmount
			if delta > 0 then 
				if util.time() - timeLast > .1 then pivotAmount = pivotAmount%7+delta end
			elseif delta < 0 then 
				if util.time() - timeLast > .1 then pivotAmount = pivotAmount%9+delta end
			end
			if pivotAmount <= 0 then pivotAmount = 7 end
		end
		--encoder 3
	elseif n == 3 then
		if not shiftA then
			if delta > 0 then
				add_random()
			elseif delta < 0 then 
				remove_last()
			end
		else
			local x = params:get("traffic_length")
			if util.time() - timeLast > .1 then
				x = x + delta
				print('x + ', delta, ' = ', x)  
				if x > 4 then x = 1
				elseif x < (-2) then x = (-1) end
				params:set("traffic_length", x)
			end
		end
    
  end
  
  
  timeLast = util.time()

end

function key(n, z)

  if z == 1 then
		clearBuffer = util.time() 
	end

	--key 2 
	if n == 2 then
		local e = {}
		e.id = 'key'
		e.number = n
		e.state = z 
		--print(e.id, e.number, e.state)
		pat:watch(e) 
		if z == 1 then shiftA = true end
		if z == 0 then 
			shiftA = false
			if util.time() - clearBuffer < .5 then 
				if not progression.isplaying then 
					change_tonality()
				else 
					background_change_tonality()
				end
			end
		end
			--key 3 
	elseif n == 3 then 
		if z == 1 then
			patternClearer = true
			if pat.rec == 0 then
				if not progression.isplaying then
					capture_scale()
					pat:stop()
					pat:clear()
					pat:rec_start() 
				end
			elseif pat.rec == 1 then
				pat:rec_stop()
				pat:start()
				if pat.count > 0 then progression.isplaying = true end
			end
		elseif z == 0 then
			patternClearer = false 
			if pat.rec == 1 then 
				local e = {}
				e.id = 'key'
				e.number = n
				e.state = z 
			--print(e.id, e.number, e.state)
				pat:watch(e) 
			end
	
			if util.time() - clearBuffer > 1 then 
				pat:clear()
				print('cleared')
				progression.isplaying = false
			end
		end
	end
end

 
local function note_on(note_num)
  
  local min_vel, max_vel = params:get("min_velocity"), params:get("max_velocity")
  if min_vel > max_vel then
    max_vel = min_vel
  end
  local note_midi_vel = math.random(min_vel, max_vel)
  
  -- print("note_on", note_num, note_midi_vel)
  
  -- Audio engine out
  if params:get("output") == 1 or params:get("output") == 3 then
    engine.noteOn(note_num, MusicUtil.note_num_to_freq(note_num), note_midi_vel / 127)
  end
  
  -- MIDI out
  if (params:get("output") == 2 or params:get("output") == 3) then
    midi_out_device.note_on(note_num, note_midi_vel, midi_out_channel)
  end
  
end


function note_off(noteNum)
	if params:get("output") == 1 or params:get("output") == 3 then 
		engine.noteOff(noteNum)
	end

	if (params:get("output") == 2 or params:get("output") == 3) then
		midi_out_device.note_off(noteNum, nil, midi_out_channel)
	end
end

function all_notes_kill()
  engine.noteKillAll()

	if (params:get("output") == 2 or params:get("output") == 3) then 
		for _, a in pairs(activeNotes) do
			midi_out_device.note_off(a, 96, midi_out_channel)
		end
	end

	activeNotes = {}

end

function add_note(position, head, length, direction)
  length = length or 1
	direction = direction or 1

	local note = {position = position, head = head, length = length, advance_countdown = length, direction = direction, active = false}
	table.insert(notes, note)
	gridDirty = true
end

function add_trigger(position, head, length, direction)
local triggerDuration
	if params:get("traffic_length") == 1 then
		length = length or 1
		direction = direction or 1
	elseif params:get("traffic_length") == 2 then
		length = (length or 1) + 1
		direction = direction or 1
	elseif params:get("traffic_length") == 4 then
		length = length or 1
		direction = -1 * (direction or 1)
	end
  
	local trigger = {position = position, head = head, length = length, advance_countdown = length, direction = direction, active = false}
	table.insert(triggers, trigger)

	gridDirty = true
end

function remove_note(position, silent)
	local note
	if position then
		for k, v in pairs(notes) do 
			
			if v.position == position then 
				note= table.remove(notes, k)
				break
			end
		end
	else
		note = table.remove(notes)
	end

	if note and not silent then 
		gridDirty = true
	end

end

function remove_trigger(position, silent)
	local trigger
	if position then 
		for k,v in pairs(triggers) do 
			if v.position == position then
				trigger = table.remove(triggers, k)
				break
			end
		end
	else
		trigger = table.remove(triggers)
	end
	if trigger and not silent then 
		gridDirty = true
	end

end

function add_random()
	if #notes >= grid_w and #triggers >= grid_h then return end

	if math.random() >= .5 then 
		local availablePositions = {}
		for i = 1, grid_w do 
			local available = true
			for _, vn in pairs(notes) do
				if vn.position == i then 
					available = false
					break
				end
			end
			if available then 
				table.insert(availablePositions, i)
			end
		end

		if #availablePositions > 0 then 
			local length = util.round(math.pow(math.random(), 4) * (grid_h - 2) + 1)
			add_note(availablePositions[math.random(#availablePositions)],
			math.random(grid_h),
			length, 
			math.random() >= 0.5  and 1 or -1)
		end

	else
    local availablePositions = {}
    for i = 1, grid_h do
      local available = true
      for _, vt in pairs(triggers) do
        if vt.position == i then
          available = false
          break
        end
      end
      if available then
        table.insert(availablePositions, i)
      end
    end
    
    if #availablePositions > 0 then
      local length = util.round(math.pow(math.random(), 4) * (grid_w - 2) + 1)
      add_trigger(availablePositions[math.random(#availablePositions)], math.random(grid_w), length, (math.random() >= 0.5 and 1 or -1), true)
    end
    
  end
end

function remove_last()
  if #notes == 0 and #triggers == 0 then return end
	if math.random() >= .5 then
		remove_note(nil, true)
	else
		remove_trigger(nil, true)
	end
end

function advance_step()
	currentStep = currentStep  + 1
	if currentStep >= stepsPerBar then
		bar = bar + 1
		currentStep = 0
		--pivot_within_scale(math.random(-2,2),bar)
	end

  if gridDevice then
    grid_w = gridDevice.cols
    grid_h = gridDevice.rows
    if grid_w ~= 8 and grid_w ~= 16 then grid_w = 16 end
    if grid_h ~= 8 and grid_h ~= 16 then grid_h = 8 end
  end

  for _, n in pairs(notes) do
	 n.advance_countdown = n.advance_countdown - 1
    if n.advance_countdown == 0 then
      n.advance_countdown = n.length
      if n.direction > 0 then n.head = n.head % params:get("pattern_height") + 1
      else n.head = (n.head + params:get("pattern_height") - 2) % params:get("pattern_height") + 1 end
    end
    n.active = false
  end

  local activeNotesThisStep = {}
  
  for _, t in pairs(triggers) do
    -- Progress
		if params:get("traffic_length") == 3 then 
			t.advance_countdown = t.advance_countdown 
		else 
			t.advance_countdown = t.advance_countdown - 1
		end 
    if t.advance_countdown == 0 then
      t.advance_countdown = t.length
      if t.direction > 0 then t.head = t.head % params:get("pattern_width") + 1
      else t.head = (t.head + params:get("pattern_width") - 2) % params:get("pattern_width") + 1 end
    end
    t.active = false
    
    -- Check for intersections and generate trails
    local tx
    for ti = 0, t.length - 1 do
      tx = t.head + (ti * t.direction * -1)
      tx = (tx - 1) % params:get("pattern_width") + 1
      if tx <= grid_w then trails[tx][t.position] = TRAIL_ANI_LENGTH end
      for _, n in pairs(notes) do
        local ny
        for ni = 0, n.length - 1 do
          ny = n.head + (ni * n.direction * -1)
          ny = (ny - 1) % params:get("pattern_height") + 1
          if ny <= grid_h then trails[n.position][ny] = TRAIL_ANI_LENGTH end
          if tx == n.position and t.position == ny then
            if not n.active then
              table.insert(activeNotesThisStep, gridScale[n.position])
            end
            n.active = true
            t.active = true
            break
          end
        end
      end
    end
  end
  
  -- Generate trails for notes if need be
  if #triggers == 0 then
    for _, n in pairs(notes) do
      local ny
      for ni = 0, n.length - 1 do
        ny = n.head + (ni * n.direction * -1)
        ny = (ny - 1) % params:get("pattern_height") + 1
        if ny <= grid_h then trails[n.position][ny] = TRAIL_ANI_LENGTH end
      end
    end
  end
  
  -- Work out which need noteOffs
  for i = #activeNotes, 1, -1 do
    local still_active = false
    for sk, sa in pairs(activeNotesThisStep) do
      if sa == activeNotes[i] then
        still_active = true
        table.remove(activeNotesThisStep, sk)
        break
      end
    end
    if not still_active then
      note_off(activeNotes[i])
      table.remove(activeNotes, i)
    end
  end
  
  -- Add remaining, the new notes
   for _, sa in pairs(activeNotesThisStep) do
    if #activeNotes < params:get("max_active_notes") then
      note_on(sa)
      table.insert(activeNotes, sa)
    end
  end
 
  screenDirty = true
  gridDirty = true
	arcDirty = true
end



local function grid_update()
  
  if #downMarks > 0 or #removeAnimations > 0 then gridDirty = true end
  
  local time_increment = 1 / GRID_FRAMERATE
  
  -- Trails
  for x = 1, grid_w do
    for y = 1, grid_h do
      trails[x][y] = util.clamp(trails[x][y] - time_increment, 0, TRAIL_ANI_LENGTH)
      if trails[x][y] > 0 then gridDirty = true end
    end
  end
  
  -- Down marks
  for i = #downMarks, 1, -1 do
    if not downMarks[i].active then
      downMarks[i].time_remaining = downMarks[i].time_remaining - time_increment
      if downMarks[i].time_remaining <= 0 then
        table.remove(downMarks, i)
      end
    end
  end
  
  -- Remove animations
  for i = #removeAnimations, 1, -1 do
    removeAnimations[i].time_remaining = removeAnimations[i].time_remaining - time_increment
    if removeAnimations[i].time_remaining <= 0 then
      table.remove(removeAnimations, i)
    end
  end
  
end


local function stop()
  all_notes_kill()
end

local function reset_step()
  beat_clock:reset()
end


local function grid_update()
  
  if #downMarks > 0 then gridDirty = true end
  
  local time_increment = 1 / GRID_FRAMERATE
  
  -- Trails
  for x = 1, grid_w do
    for y = 1, grid_h do
      trails[x][y] = util.clamp(trails[x][y] - time_increment, 0, TRAIL_ANI_LENGTH)
      if trails[x][y] > 0 then gridDirty = true end
    end
  end
  
  -- Down marks
  for i = #downMarks, 1, -1 do
    if not downMarks[i].active then
      downMarks[i].time_remaining = downMarks[i].time_remaining - time_increment
      if downMarks[i].time_remaining <= 0 then
        table.remove(downMarks, i)
      end
    end
  end
end

function init()
	midi_in_device = midi.connect(1)
	midi_in_device.event = midi_event
  
	
	masterScale = MusicUtil.generate_scale_of_length(rootNote, tonality, 128)
	--set first scale
	for _, v in pairs(masterScale) do 
		if v >= octave then 
			gridScale[#gridScale + 1] = v
		end
		if #gridScale > 15 then	break end
	end


  for x = 1, 16 do
    gridLEDs[x] = {}
    trails[x] = {}
    for y = 1, 16 do
      gridLEDs[x][y] = 0
      trails[x][y] = 0
    end
  end

	capture_scale()
  gridDevice = grid.connect(1)
  gridDevice.key = gridKey

  
  beat_clock = BeatClock.new()
  beat_clock.on_step = advance_step
  beat_clock.on_stop = stop
  beat_clock.on_select_internal = function()
    beat_clock:start()
    screenDirty = true
  end
  beat_clock.on_select_external = function()
    reset_step()
    screenDirty = true
  end
  
  midi_out_device = midi.connect(1)
  midi_out_device.event = function() end
  
	local screen_refresh_metro = metro.init()
  screen_refresh_metro.event = function()
		if screenDirty then
      screenDirty = false
      redraw()
    end
  end
  
	local grid_redraw_metro = metro.init()
  grid_redraw_metro.event = function()
    grid_update()
    if gridDirty and gridDevice.device then
      gridDirty = false
      grid_redraw()
    end
	end

	local arc_redraw_metro = metro.init()
	arc_redraw_metro.event = function()
		if arcDirty then
			arcDirty = false
			arc_redraw()
		end
	end



  
  -- Add params
 
  params:add{type = "number", id = "gridDevice", name = "Grid Device", min = 1, max = 4, default = 1,
    action = function(value)
      gridDevice:all(0)
      gridDevice:refresh()
			gridDevice.key = nil
			gridDevice = grid.connect(value)
			gridDevice.key = gridKey
    end}
  
  params:add{type = "option", id = "output", name = "Output", options = options.OUTPUT, action = all_notes_kill}
 
	params:add{type = "number", id = "midi_device", name = "MIDI Device", min = 1, max = 4, default = 1, action = function(value)
    midi_in_device.event = nil
    midi_in_device = midi.connect(value)
    midi_in_device.event = midi_event
  end}
 
  params:add{type = "number", id = "midi_out_device", name = "MIDI Out Device", min = 1, max = 4, default = 1,
    action = function(value)
			midi_out_device = midi.connect(value)
    end}
  
  params:add{type = "number", id = "midi_out_channel", name = "MIDI Out Channel", min = 1, max = 16, default = 1,
    action = function(value)
      all_notes_kill()
      midi_out_channel = value
    end}
  params:add{type = "number", id = "max_active_notes", name = "Max Active Notes", min = 1, max = 10, default = 10}
  
  
	params:add{type = "option", id = "clock", name = "Clock", options = {"Internal", "External"}, default = beat_clock.external or 2 and 1,
    action = function(value)
      beat_clock:clock_source_change(value)
    end}
  
  params:add{type = "number", id = "clock_midi_in_device", name = "Clock MIDI In Device", min = 1, max = 4, default = 1,
    action = function(value)
			midi_in_device.event = nil
      midi_in_device = midi.connect(value)
      midi_in_device.event = midi_clock_event
    end}
  
  params:add{type = "option", id = "clock_out", name = "Clock Out", options = {"Off", "On"}, default = beat_clock.send or 2 and 1,
    action = function(value)
      if value == 1 then beat_clock.send = false
      else beat_clock.send = true end
    end}
  
  params:add_separator()

  params:add{type = "number", id = "bpm", name = "BPM", min = 1, max = 340, default =140,
    action = function(value)
      beat_clock:bpm_change(value)
      
    end}
 
	params:add{type = "option", 
		id = "step_length", 
		name = "Step Length", 
		options = options.STEP_LENGTH_NAMES, 
		default = 8, 
		action = function(value)
			stepDuration = value
			stepsPerBar = get_bar_length()
			beat_clock.steps_per_beat = options.STEP_LENGTH_DIVIDERS[value] / 4
			beat_clock:bpm_change(beat_clock.bpm)
			end}

   params:add{type = "option", 
		id = "traffic_length", 
		name = "Traffic", 
		options = options.traffic_length_NAMES, 
		default = 1, 
		action = function(value)
			triggerDuration = value
			end}
   
  params:add{type = "number", id = "pattern_width", name = "Pattern Width", min = 4, max = 64, default = 16,
    action = function()
      gridDirty = true
    end}
  params:add{type = "number", id = "pattern_height", name = "Pattern Height", min = 4, max = 64, default = 8,
    action = function()
      gridDirty = true
    end}
  
  params:add{type = "number", id = "min_velocity", name = "Min Velocity", min = 1, max = 127, default = 80}
  params:add{type = "number", id = "max_velocity", name = "Max Velocity", min = 1, max = 127, default = 100}
  
  params:add_separator()
  
  midi_out_channel = params:get("midi_out_channel")
  
  -- Engine params
  
  MollyThePoly.add_params()
  
  grid_redraw_metro:start(1 / GRID_FRAMERATE)
  screen_refresh_metro:start(1 / SCREEN_FRAMERATE)
  beat_clock:start()

	pat = pattern_time.new()
	pat.process = play_progression

end

function gridKey(x, y, z)
  
  if z == 1 then
    
    -- Is there a relevant down mark?
    local relevantDownMark = nil
    for k, v in pairs(downMarks) do
      
      -- Re-activate fading down mark
      if v.x == x and v.y == y then
        
        v.active = true
        v.time_remaining = DOWN_ANI_LENGTH
        relevantDownMark = v
        break
      
      -- Note
      elseif v.x == x and v.active then
        
        local threeKeys = false
        for _, kv in pairs(downKeys) do
          if kv.x == x then
            threeKeys = true
            break
          end
        end
        
        if threeKeys then
          remove_note(x, true, false)
        else
					remove_note(x, false, true)
          add_note(x, v.y, math.abs(v.y - y), (y < v.y and 1 or -1), false)
        end
        relevantDownMark = v
        
      -- Trigger
      elseif v.y == y and v.active then
        
        local threeKeys = false
        for _, kv in pairs(downKeys) do
          if kv.y == y then
            threeKeys = true
            break
          end
        end
        
        if threeKeys then
          remove_trigger(y, true, false)
        else
          remove_trigger(y, false, true)
          add_trigger(y, v.x, math.abs(v.x - x), (x < v.x and 1 or -1), false)
        end
        relevantDownMark = v
        
      end
    end
    
    -- Make it the down mark
    if relevantDownMark then
      if relevantDownMark.x ~= x or relevantDownMark.y ~= y then
        table.insert(downKeys, {x = x, y = y})
      end
    else
      table.insert(downMarks, {active = true, x = x, y = y, time_remaining = DOWN_ANI_LENGTH})
    end
    
  else
    for _, v in pairs(downMarks) do
      if v.x == x and v.y == y then
        v.active = false
        break
      end
    end
    for k, v in pairs(downKeys) do
      if v.x == x and v.y == y then
        table.remove(downKeys, k)
        break
      end
    end
    
  end
  
  gridDirty = true
end

function ar.delta(n, delta)
	print("enc: "..n)
	print("delta: "..delta)
end

function arc_redraw()
	print('arc redraw')
	if progression.isplaying then 
		print('hark! the ark shall be lit!')
		ar:led(1, 15, 15)
	end


end


function grid_redraw()
  
  local DOWN_BRIGHTNESS = 1
  local TRAIL_BRIGHTNESS = 1
  local OUTSIDE_BRIGHTNESS = 1
  local INACTIVE_BRIGHTNESS = 2
  local ACTIVE_BRIGHTNESS = 4
  
	
	local brightness
  -- Draw trails
  for x = 1, 16 do
    for y = 1, 16 do
      if trails[x][y] then gridLEDs[x][y] = util.round(util.linlin(0, TRAIL_ANI_LENGTH, 0, TRAIL_BRIGHTNESS, trails[x][y]))
      else gridLEDs[x][y] = 0 end
      if (x > params:get("pattern_width") or y > params:get("pattern_height")) and gridLEDs[x][y] < OUTSIDE_BRIGHTNESS then gridLEDs[x][y] = OUTSIDE_BRIGHTNESS end
    end
  end
  
  -- Draw down marks
  for k, v in pairs(downMarks) do
    brightness = util.round(util.linlin(0, DOWN_ANI_LENGTH, 0, DOWN_BRIGHTNESS, v.time_remaining))
    for i = 1, grid_w do
      if gridLEDs[i][v.y] < brightness then gridLEDs[i][v.y] = brightness end
    end
    for i = 1, grid_h do
      if gridLEDs[v.x][i] < brightness then gridLEDs[v.x][i] = brightness end
    end
    if v.active and gridLEDs[v.x][v.y] < INACTIVE_BRIGHTNESS then gridLEDs[v.x][v.y] = INACTIVE_BRIGHTNESS end
  end
  
  -- Draw remove animations
  for _, v in pairs(removeAnimations) do
    brightness = util.round(util.linlin(0, REMOVE_ANI_LENGTH, 0, 15, v.time_remaining))
    if v.orientation == "row" then
      for i = 1, grid_w do
        if gridLEDs[i][v.position] < brightness then gridLEDs[i][v.position] = brightness end
      end
    else
      for i = 1, grid_h do
        if gridLEDs[v.position][i] < brightness then gridLEDs[v.position][i] = brightness end
      end
    end
  end
  
  -- Draw notes
  for _, n in pairs(notes) do
    if n.active then brightness = ACTIVE_BRIGHTNESS
    else brightness = INACTIVE_BRIGHTNESS end
    if n.position <= grid_w then
      local ny
      for i = 0, n.length - 1 do
        ny = n.head + (i * n.direction * -1)
        ny = (ny - 1) % params:get("pattern_height") + 1
        if ny > 0 and ny <= grid_h then
          gridLEDs[n.position][ny] = brightness
        end
      end
    end
  end
  
  -- Draw triggers
  for _, t in pairs(triggers) do
    if t.active then brightness = ACTIVE_BRIGHTNESS
    else brightness = INACTIVE_BRIGHTNESS end
    if t.position <= grid_h then
      local tx
      for i = 0, t.length - 1 do
        tx = t.head + (i * t.direction * -1)
        tx = (tx - 1) % params:get("pattern_width") + 1
        if tx > 0 and tx <= grid_w then
          gridLEDs[tx][t.position] = brightness
        end
        
      end
    end
  end
  
  for x = 1, grid_w do
    for y = 1, grid_h do
      gridDevice:led(x, y, gridLEDs[x][y])
    end
  end
  gridDevice:refresh()
  
end



function redraw()
  screen.clear()
  --Scale name
      screen.move(5, 10)
      screen.level(15) 
      screen.text(MusicUtil.note_num_to_name(rootNote) .. " " .. tonality) 
			if string.find((MusicUtil.note_num_to_name(rootNote)),"%#") then
				screen.move_rel(-5,0)
			end
			screen.move(99, 10)
			screen.level(3)
			screen.text('jump: ')
			if shiftA then screen.level(15) else screen.level(3) end
			screen.text(pivotAmount)
			screen.move(100,17)
			screen.level(3)
			screen.text('octv: ')
			screen.text(math.floor(gridScale[1]/12))
			screen.move_rel(-29,7)
			screen.move(128,60)
			if shiftA then screen.level(15) else screen.level(3) end
			screen.text_right(options.traffic_length_NAMES[params:get("traffic_length")])

			local patternDisplay
			if pat.rec == 1 then
				patternDisplay = 'rec'
			else
				if progression.isplaying then patternDisplay = 'pattern' 
				else patternDisplay = nil end
			end

			if patternDisplay then 
				screen.move(128,53)
				screen.level(3)
				screen.text_right(patternDisplay) 
			else 
				screen.move(128,53)
				screen.level (0)



			end





			
  -- Scale notes
      local x, y = 5, 14
      local scale_note_names = MusicUtil.note_nums_to_names(gridScale, false)
      local COLS = 4
      --print (#scale_note_names)
      if #scale_note_names <17 then
        for i = 1, grid_w do
          if (i - 1) % COLS == 0 then x, y = 5, y + 11 end
          local is_active = false
          for _, n in pairs(notes) do
            if n.position == i and n.active then
              is_active = true
              break
            end
          end
          
          local underline_length = 10
          if scale_note_names[i] == nil then
              break
          elseif string.len(scale_note_names[i]) > 3 then
              underline_length = 18
					elseif string.len(scale_note_names[i]) > 2 then
              underline_length = 16
					end
          
          if is_active then screen.level(15)
          else screen.level(3) end
          screen.move(x, y)
          screen.text(scale_note_names[i])
          
          x = x + 18
       
      end
    end
		screen.update()
end

function cleanup()
  pat:stop()
  pat = nil
end
