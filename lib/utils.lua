local utils = {}

local data_counter = 1
local screen_data = {}

utils.table_find_value = function(t, condition)
  for k,v in pairs(t, condition) do
    if condition(k, v) then
      return v
    end
  end
  return nil
end

utils.examples_get_screen_text = function(datum_type)
  if datum_type == 'program_change' then
    return "!"
  elseif datum_type == 'note_on' then
    return '"'
  elseif datum_type == 'note_off' then
    return '.'
  elseif datum_type == 'cc' then
    return "<"
  elseif datum_type =="channel_pressure" then
    return "%"
  elseif datum_type =='pitchbend' then
    return "~"
  elseif datum_type == 'key_pressure' then
    return "&"
  else
    return "-"
  end
end

utils.examples_start_screen_datum = function (datum)
  local screen_datum = {type = datum.type, repeat_timer = 24, x = math.random(128), y = 15 * datum.port, text = utils.examples_get_screen_text(datum.type) }
  screen_data[data_counter] = screen_datum
  data_counter = util.wrap(data_counter, 1, 8)
end

utils.examples_screen_init = function()
  data_counter = 1
  screen_data={}
end

utils.examples_draw = function()
  screen.clear()
  screen.aa(0)
  screen.line_width(1)

  for n_key, n_val in pairs(screen_data) do
    if n_val.repeat_timer ~= 0 then 
      n_val.repeat_timer = n_val.repeat_timer - 1
      screen.font_size(n_val.repeat_timer * 2)
      screen.move(n_val.x, n_val.y)
      screen.text(n_val.text)
    end
  end

  screen.update()
end

return utils