-- Script to group focus bracketed images created with OM Solution / Olympus cameras
-- Requires exiftool to be installed since the MakerNotes:FocusStepCount field is not available in the darktable lua API
-- Groups Images based on focus distance and time exif_datetime_taken

local dt = require "darktable"

-- SETTINGS
local MODULE_NAME = "focus_step_gui"
local FOCUS_STEP_DIFF_THRESHOLD = 150
local TIME_GAP = 10

local function exif_time_to_unix(exif_str)
    -- exif_str expected format: "YYYY:MM:DD HH:MM:SS"
    local y, m, d, H, M, S = string.match(exif_str, "(%d+):(%d+):(%d+) (%d+):(%d+):(%d+)")
    if y and m and d and H and M and S then
        return os.time({
            year = y,
            month = m,
            day = d,
            hour = H,
            min = M,
            sec = S
        })
    else
        return 0
    end
end

-- Get FocusStepCount from exiftool
local function get_focus_step_count(img)
    local full_path = img.path .. "/" .. img.filename
    local cmd = 'exiftool -s -s -s -MakerNotes:FocusStepCount "' .. full_path .. '"'
    local handle = io.popen(cmd)
    if not handle then
        dt.print_error("Failed to run exiftool on " .. full_path)
        return 0
    end
    local result = handle:read("*a")
    handle:close()
    return tonumber(result) or 0
end

local function is_grouped(img)
  return img.group_leader.id ~= img.id
end

-- Group images by FocusStepCount difference and timestamp
local function group_focus_bracketed_images()
    local images = dt.gui.selection()
    -- Filter out already-grouped images
    local ungrouped = {}
    for _, img in ipairs(images) do
      if not is_grouped(img) then
        table.insert(ungrouped, img)
      else
        dt.print_log("Skipping already grouped image: " .. img.filename)
      end
    end

    if #ungrouped < 2 then
      dt.print("Not enough ungrouped images to process.")
      return
    end

    images = ungrouped
    dt.print("Processing " .. #images .. " ungrouped images.")

  
    dt.print("Running focus bracket grouping on " .. #images .. " images.")
  
    -- TODO: does this work with small increments? No ms saved?
    table.sort(images, function(a, b)
     -- return a.exif_datetime_taken < b.exif_datetime_taken
     return a.filename < b.filename
    end)
  
    local current_group = {}
    local last_image = images[1]
    local last_step = get_focus_step_count(last_image)
    table.insert(current_group, last_image)
  
    local total_groups = 0
  
    for i = 2, #images do
      local img = images[i]
      local ts1 = exif_time_to_unix(last_image.exif_datetime_taken)
      local ts2 = exif_time_to_unix(img.exif_datetime_taken)
      local time_diff = os.difftime(ts2, ts1)
      local step1 = last_step
      local step2 = get_focus_step_count(img)
      local step_diff = math.abs(step2 - step1)
  
      dt.print_log(string.format(
        "[%d → %d] Δt = %ds, Δfocus = %d (values: %d → %d)",
        i - 1, i, time_diff, step_diff, step1, step2
      ))
  
      if time_diff <= TIME_GAP and step_diff <= FOCUS_STEP_DIFF_THRESHOLD then
        dt.print_log("→ Added to current group")
        table.insert(current_group, img)
      else
        if #current_group > 1 then
          dt.print_log("→ Grouped " .. #current_group .. " images")
          local leader = current_group[1]
          for j = 2, #current_group do
            current_group[j]:group_with(leader)
          end
          total_groups = total_groups + 1
        else
          dt.print_log("→ Skipped single image (not grouped)")
        end
  
        current_group = { img }
      end
  
      last_image = img
      last_step = step2
    end
  
    -- Final group
    if #current_group > 1 then
      dt.print_log("→ Final group of " .. #current_group .. " images")
      local leader = current_group[1]
      for j = 2, #current_group do
        current_group[j]:group_with(leader)
      end
      total_groups = total_groups + 1
    end
  
    dt.print(string.format("Grouping complete. %d group(s) created.", total_groups))
  end
  

-- GUI WIDGET
local GUI = dt.new_widget("box") {
    orientation = "vertical",
    dt.new_widget("label") {
        label = "Focus Bracket Grouping"
    },
    dt.new_widget("button") {
        label = "Group by FocusStepCount",
        clicked_callback = group_focus_bracketed_images
    }
}

-- REGISTER MODULE IN LIGHTTABLE VIEW
dt.register_lib(MODULE_NAME, "Focus Bracket Grouping", true, false, {
    [dt.gui.views.lighttable] = {"DT_UI_CONTAINER_PANEL_RIGHT_CENTER", 100}
}, GUI)
