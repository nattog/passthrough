local utils = {}

utils.table_find_value = function(t, condition)
  for k,v in pairs(t, condition) do
    if condition(k, v) then
      return v
    end
  end
  return nil
end

return utils