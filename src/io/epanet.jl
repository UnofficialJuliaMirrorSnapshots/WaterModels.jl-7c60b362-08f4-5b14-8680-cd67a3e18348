using JSON

_INP_SECTIONS = ["[OPTIONS]", "[TITLE]", "[JUNCTIONS]", "[RESERVOIRS]",
                 "[TANKS]", "[PIPES]", "[PUMPS]", "[VALVES]", "[EMITTERS]",
                 "[CURVES]", "[PATTERNS]", "[ENERGY]", "[STATUS]",
                 "[CONTROLS]", "[RULES]", "[DEMANDS]", "[QUALITY]",
                 "[REACTIONS]", "[SOURCES]", "[MIXING]",
                 "[TIMES]", "[REPORT]", "[COORDINATES]", "[VERTICES]",
                 "[LABELS]", "[BACKDROP]", "[TAGS]"]

function _add_link_ids!(data::Dict{String, <:Any})
    link_types = ["pipes", "pumps", "valves"]
    link_names = vcat([collect(keys(data[t])) for t in link_types]...)
    all_int = all([tryparse(Int64, x) != nothing for x in link_names])

    if all_int
        for link_type in link_types
            for (link_name, link) in data[link_type]
                link["index"] = parse(Int64, link_name)
                link["node_fr"] = data["node_map"][pop!(link, "start_node_name")]
                link["node_to"] = data["node_map"][pop!(link, "end_node_name")]
                data["link_map"][link_name] = link["index"]

                # Add default status for pump if not present (Open).
                if link_type == "pumps" && link["initial_status"] == nothing
                    link["initial_status"] = "Open"
                end
            end
        end
    else
        link_id::Int64 = 1

        for link_type in link_types
            starnode_to = link_id

            for (link_name, link) in data[link_type]
                link["index"] = link_id
                link["node_fr"] = data["node_map"][pop!(link, "start_node_name")]
                link["node_to"] = data["node_map"][pop!(link, "end_node_name")]
                data["link_map"][link_name] = link["index"]
                link_id += 1

                # Add default status for pump if not present (Open).
                if link_type == "pumps" && link["initial_status"] == nothing
                    link["initial_status"] = "Open"
                end
            end

            new_ids = starnode_to:(starnode_to+length(keys(data[link_type]))-1)
            new_keys = String[string(x) for x in new_ids]
            data[link_type] = DataStructures.OrderedDict{String,Any}(new_keys .=> values(data[link_type]))
        end
    end

    for link_type in ["pumps"]
        # Update the link IDs in time series.
        ts_link_ids = Array{Int64, 1}()

        for (link_name, link) in data["time_series"][link_type]
            ts_link_ids = vcat(ts_link_ids, data["link_map"][link_name])
        end

        new_keys = String[string(x) for x in ts_link_ids]
        data["time_series"][link_type] = Dict{String,Any}(new_keys .=> values(data["time_series"][link_type]))
    end

    # Convert to Dict to ensure compatibility with InfrastructureModels.
    for link_type in link_types
        data[link_type] = Dict{String, Any}(data[link_type])
    end
end

function _correct_status!(data::Dict{String, <:Any})
    for (id, pump) in data["pumps"]
        initial_status = pump["initial_status"]

        # TODO: This needs to be generic for controls not dependent on tanks.
        lt, gt = [nothing, nothing]
        node_type_lt, node_type_gt = [nothing, nothing]
        node_id_lt, node_id_gt = [nothing, nothing]

        for (control_id, control) in pump["controls"]
            if control["condition"]["operator"] == "<="
                lt = control["condition"]["threshold"]
                node_type_lt = control["condition"]["node_type"]
                node_id_lt = control["condition"]["node_id"]
            elseif control["condition"]["operator"] == ">="
                gt = control["condition"]["threshold"]
                node_type_gt = control["condition"]["node_type"]
                node_id_gt = control["condition"]["node_id"]
            end
        end

        if node_type_lt == "tanks" && node_type_gt == "tanks"
            if node_id_lt == node_id_gt
                node_id = string(node_id_lt)
                init_level = data["tanks"][node_id]["init_level"]

                if init_level <= lt
                    pump["initial_status"] = "Open"
                elseif init_level >= gt
                    pump["initial_status"] = "Closed"
                end
            end
        end
    end
end

function _correct_time_series!(data::Dict{String, <:Any})
    duration = data["options"]["time"]["duration"]
    time_step = data["options"]["time"]["hydraulic_timestep"]
    num_steps = convert(Int64, floor(duration / time_step))
    patterns = keys(data["patterns"])

    if num_steps >= 1 && patterns != ["1"]
        data["time_series"]["duration"] = data["options"]["time"]["duration"]
        data["time_series"]["time_step"] = data["options"]["time"]["hydraulic_timestep"]
        data["time_series"]["num_steps"] = num_steps

        for pattern in patterns
            if !(length(data["patterns"][pattern]) in [1, num_steps])
                Memento.error(_LOGGER, "Pattern \"$(pattern)\" does not have the correct number of entries")
            end
        end
    else
        delete!(data, "time_series")
    end
end

function _add_node_ids!(data::Dict{String, <:Any})
    node_types = ["junctions", "reservoirs", "tanks"]
    node_id_field = Dict(t => t * "_node" for t in node_types)
    node_names = vcat([collect(keys(data[t])) for t in node_types]...)

    if all([tryparse(Int64, x) != nothing for x in node_names])
        for node_type in node_types
            for (node_name, node) in data[node_type]
                node["index"] = parse(Int64, node_name)
                data["node_map"][node_name] = node["index"]
            end
        end
    else
        node_id::Int64 = 1

        for node_type in node_types
            starnode_to = node_id

            for (node_name, node) in data[node_type]
                node["index"] = node_id
                data["node_map"][node_name] = node["index"]
                node_id += 1
            end

            new_ids = starnode_to:(starnode_to+length(keys(data[node_type]))-1)
            new_keys = String[string(x) for x in new_ids]
            data[node_type] = DataStructures.OrderedDict{String,Any}(new_keys .=> values(data[node_type]))
        end
    end

    nodes = Dict{String, Any}()

    for node_type in node_types
        nid_field = node_id_field[node_type]

        for (i, comp) in data[node_type]
            @assert i == "$(comp["index"])"
            comp[nid_field] = comp["index"]
            node = Dict{String, Any}("index" => comp["index"],
                "source_id" => [node_type, comp["source_id"]])

            if haskey(comp, "name")
                node["name"] = comp["name"]
            end

            if haskey(comp, "elevation")
                #node["elevation"] = pop!(comp, "elevation")
                node["elevation"] = comp["elevation"]
            end

            if haskey(comp, "minimumHead")
                node["minimumHead"] = pop!(comp, "minimumHead")
            end

            if haskey(comp, "maximumHead")
                node["maximumHead"] = pop!(comp, "maximumHead")
            end

            if haskey(comp, "head")
                node["elevation"] = comp["head"]
            end

            @assert !haskey(nodes, i)
            nodes[i] = node
        end
    end

    data["nodes"] = nodes

    for (i, junction) in data["junctions"]
        if isapprox(junction["demand"], 0.0, atol=1.0e-7)
            Memento.info(_LOGGER, "Dropping junction $(i) due to zero demand.")
            delete!(data["junctions"], i)
        end
    end

    # Update the node IDs in time series.
    ts_node_ids = Array{Int64, 1}()

    for node_type in ["junctions", "reservoirs"]
        # Update the node IDs in time series.
        ts_node_ids = Array{Int64, 1}()

        for (node_name, node) in data["time_series"][node_type]
            ts_node_ids = vcat(ts_node_ids, data["node_map"][node_name])
        end

        new_keys = String[string(x) for x in ts_node_ids]
        data["time_series"][node_type] = Dict{String,Any}(new_keys .=> values(data["time_series"][node_type]))
    end

    # Convert to Dict to ensure compatibility with InfrastructureModels.
    for node_type in node_types
        data[node_type] = Dict{String, Any}(data[node_type])
    end
end

function _split_line(line::AbstractString)
    _vc = split(line, ",", limit=1)
    _values = nothing
    _comment = nothing

    if length(_vc) != 0
        if length(_vc) == 1
            _values = split(_vc[1])
        elseif _vc[1] == ""
            _comment = _vc[2]
        else
            _values = split(_vc[1])
            _comment = _vc[2]
        end
    end

    return _values, _comment
end

function _initialize_data()
    data = Dict{String, Any}()

    data["curves"] = DataStructures.OrderedDict{String, Array}()
    data["top_comments"] = []
    data["sections"] = DataStructures.OrderedDict{String, Array}()

    for section in _INP_SECTIONS
        data["sections"][section] = []
    end

    data["options"] = Dict{String, Any}()
    data["mass_units"] = nothing
    data["flow_units"] = nothing
    data["time_series"] = Dict{String, Any}()

    # Map EPANET indices to internal indices.
    data["node_map"] = Dict{String, Int}()
    data["link_map"] = Dict{String, Int}()

    return data
end

function _get_link_type_by_name(data::Dict{String, <:Any}, name::AbstractString)
    link_types = ["pumps", "pipes", "valves"]

    for link_type in link_types
        for (link_id, link) in data[link_type]
            if link["name"] == name
                return link_type
            end
        end
    end
end

function _get_link_by_name(data::Dict{String, <:Any}, name::AbstractString)
    link_types = ["pumps", "pipes", "valves"]

    for link_type in link_types
        for (link_id, link) in data[link_type]
            if link["name"] == name
                return link
            end
        end
    end
end

function _get_node_by_name(data::Dict{String, <:Any}, name::AbstractString)
    node_types = ["junctions", "reservoirs", "tanks"]

    for node_type in node_types
        for (node_id, node) in data[node_type]
            if node["name"] == name
                return node
            end
        end
    end
end

function _get_node_type_by_name(data::Dict{String, <:Any}, name::AbstractString)
    node_types = ["junctions", "reservoirs", "tanks"]

    for node_type in node_types
        for (node_id, node) in data[node_type]
            if node["name"] == name
                return node_type
            end
        end
    end
end

"""
Converts EPANET clocktime format to seconds.
Parameters
----------
s : string
    EPANET time string. Options are 'HH:MM:SS', 'HH:MM', HH'
am : string
    options are AM or PM
Returns
-------
Integer value of time in seconds
"""
function _clock_time_to_seconds(s::AbstractString, am_pm::AbstractString)
    if uppercase(am_pm) == "AM"
        am = true
    elseif uppercase(am_pm) == "PM"
        am = false
    else
        Memento.error(_LOG, "AM/PM option not recognized (options are AM or PM")
    end

    time_tuple = match(r"^(\d+):(\d+):(\d+)$", s)

    if time_tuple != nothing
        seconds_1 = parse(Int64, time_tuple[1]) * 3600
        seconds_2 = parse(Int64, time_tuple[2]) * 60
        seconds_3 = convert(Int64, round(parse(Float64, time_tuple[3])))
        time_seconds = seconds_1 + seconds_2 + seconds_3

        if startswith(s, "12")
            time_seconds -= 3600 * 12
        end

        if !am
            if time_seconds >= 3600*12
                Memento.error(_LOG, "Cannot specify AM/PM for times greater than 12:00:00")
            end

            time_seconds += 3600*12
        end

        return time_seconds
    else
        time_tuple = match(r"^(\d+):(\d+)$", s)

        if time_tuple != nothing
            seconds_1 = parse(Int64, time_tuple[1]) * 3600
            seconds_2 = parse(Int64, time_tuple[2]) * 60

            if startswith(s, "12")
                time_seconds -= 3600 * 12
            end

            if !am
                if time_seconds >= 3600*12
                    Memento.error(_LOG, "Cannot specify AM/PM for times greater than 12:00:00")
                end

                time_seconds += 3600*12
            end

            return time_seconds
        else
            time_tuple = match(r"^(\d+)$", s)

            if time_tuple != nothing
                time_seconds = parse(Int64, time_tuple[1]) * 3600
                
                if startswith(s, "12")
                    time_seconds -= 3600 * 12
                end

                if !am
                    if time_seconds >= 3600*12
                        Memento.error(_LOG, "Cannot specify AM/PM for times greater than 12:00:00")
                    end

                    time_seconds += 3600*12
                end

                return time_seconds
            else
                Memento.error(_LOGGER, "Time format in INP file not recognized")
            end
        end
    end
end

"""
Converts EPANET time format to seconds.
Parameters
----------
s : string
    EPANET time string. Options are 'HH:MM:SS', 'HH:MM', 'HH'
Returns
-------
 Integer value of time in seconds.
"""
function _string_time_to_seconds(s::AbstractString)
    time_tuple = match(r"^(\d+):(\d+):(\d+)$", s)

    if time_tuple != nothing
        seconds_1 = parse(Int64, time_tuple[1]) * 3600
        seconds_2 = parse(Int64, time_tuple[2]) * 60
        seconds_3 = convert(Int64, round(parse(Float64, time_tuple[3])))
        return seconds_1 + seconds_2 + seconds_3
    else
        time_tuple = match(r"^(\d+):(\d+)$", s)

        if time_tuple != nothing
            seconds_1 = parse(Int64, time_tuple[1]) * 3600
            seconds_2 = parse(Int64, time_tuple[2]) * 60
            return seconds_1 + seconds_2
        else
            time_tuple = match(r"^(\d+)$", s)

            if time_tuple != nothing
                return parse(Int64, time_tuple[1]) * 3600
            else
                Memento.error(_LOGGER, "Time format in INP file not recognized")
            end
        end
    end
end

function _clean_nothing!(data)
    for (key, value) in data
        if isa(value, Dict)
            value = _clean_nothing!(value)
        elseif value == nothing
            delete!(data, key)
        end
    end
end

"""
    parse_epanet(path)

Parses an [EPANET](https://www.epa.gov/water-research/epanet) (.inp) file from
the file path `path` and returns a WaterModels data structure (a dictionary of
data). See the [OpenWaterAnalytics
Wiki](https://github.com/OpenWaterAnalytics/EPANET/wiki/Input-File-Format) for
a thorough description of the EPANET format and its components.
"""
function parse_epanet(filename::String)
    data = _initialize_data()

    section = nothing
    line_number = 0
    file_contents = read(open(filename), String)

    for line in split(file_contents, "\n")
        line_number += 1
        line = strip(line)
        num_words = length(split(line))

        if length(line) == 0 || num_words == 0
            continue
        elseif startswith(line, "[")
            values = split(line, limit=1)
            section_tmp = uppercase(values[1])

            if section_tmp in _INP_SECTIONS
                section = section_tmp
                continue
            elseif section_tmp == "[END]"
                section = nothing
                break
            else
                Memento.error(_LOGGER, "$(filename): $(line_number): Invalid section \"$(section)\"")
            end
        elseif section == nothing && startswith(line, ";")
            data["top_comments"] = vcat(data["top_comments"], line[2:end])
            continue
        elseif section == nothing
            Memento.warn(_LOGGER, "$(filename): Found confusing line: $(line_number)")
            Memento.error(_LOGGER, "$(filename): $(line_number): Non-comment outside of valid section")
        end

        data["sections"][section] = vcat(data["sections"][section], (line_number, line))
    end

    # OPTIONS
    _read_options!(data)

    # TIMES
    _read_times!(data)

    # CURVES
    _read_curves!(data)

    # PATTERNS
    _read_patterns!(data)

    # JUNCTIONS
    _read_junctions!(data)

    # RESERVOIRS
    _read_reservoirs!(data)

    # TANKS
    _read_tanks!(data)

    # Create consistent node "index" fields.
    _add_node_ids!(data)

    # PIPES
    _read_pipes!(data)

    # PUMPS
    _read_pumps!(data)

    # VALVES
    _read_valves!(data)

    # ENERGY
    _read_energy!(data)

    # Create consistent link "index" fields.
    _add_link_ids!(data)

    # COORDINATES
    #_read_coordinates!(data)

    # SOURCES
    #_read_sources!(data)

    # STATUS
    _read_status!(data)
 
    # CONTROLS
    _read_controls!(data)

    # TITLE
    _read_title!(data)

    # DEMANDS
    #_read_demands!(data)

    # EMITTERS
    #_read_emitters!(data)

    # Correct status data based on control data.
    _correct_status!(data)

    # Add or remove time series information.
    _correct_time_series!(data)

    # Delete the data that has now been properly parsed.
    delete!(data, "sections")
    delete!(data, "node_map")
    delete!(data, "link_map")

    # Add other data required by InfrastructureModels.
    data["per_unit"] = false

    # Remove all keys that have values of nothing.
    _clean_nothing!(data)

    # Return the dictionary.
    return data
end

function _read_controls!(data::Dict{String, <:Any})
    # TODO: There are a lot of possible conditions that remain to be implemented.
    control_count = 0

    for (line_number, line) in data["sections"]["[CONTROLS]"]
        line = split(line, ";")[1]
        current = split(line)

        if length(current) == 0
            continue
        else
            link_name = current[2]
            link = _get_link_by_name(data, link_name)

            if uppercase(current[6]) != "TIME" && uppercase(current[6]) != "CLOCKTIME"
                node_name = current[6]
            end

            current = [uppercase(word) for word in current]
            current[2] = link_name # Don't capitalize the link name.

            # Create the control action object
            action = Dict{String, Any}()

            # Get the status attribute.
            status = uppercase(current[3])

            # TODO: Better way of doing all this?
            if status in ["OPEN", "OPENED", "CLOSED", "ACTIVE"]
                setting = status
                action["attribute"] = "state"
                action["value"] = status == "CLOSED" ? "off" : "on"
            else
                link_type = _get_link_type_by_name(data, link_name)

                if link_type == "pumps"
                    action["attribute"] = "base_speed"
                    action["value"] = parse(Float64, current[3])
                elseif link_type == "valves"
                    # TODO: Fill this in when necessary.
                else
                    Memento.error(_LOGGER, "Links of type $(link_type) can only have controls that change the link status. Control: $(line)")
                end
            end

            control_count += 1
            control_name = "control-" * string(control_count)

            # Create the control condition object.
            condition = Dict{String, Any}()

            if !("TIME" in current) && !("CLOCKTIME" in current)
                threshold = nothing

                if "IF" in current
                    node = _get_node_by_name(data, node_name)

                    if current[7] == "ABOVE"
                        condition["operator"] = ">="
                    elseif current[7] == "BELOW"
                        condition["operator"] = "<="
                    else
                        Memento.error(_LOGGER, "The following control is not recognized: $(line)")
                    end

                    node_type = _get_node_type_by_name(data, node_name)

                    if node_type == "junctions"
                        # TODO: Fill this out when necessary.
                    elseif node_type == "tanks"
                        condition["node_id"] = node["index"]
                        condition["node_type"] = node_type
                        condition["attribute"] = "level"

                        if data["options"]["hydraulic"]["units"] == "LPS" # If liters per second...
                            condition["threshold"] = parse(Float64, current[8])
                        elseif data["options"]["hydraulic"]["units"] == "GPM" # If gallons per minute...
                            condition["threshold"] = 0.3048 * parse(Float64, current[8])
                        end
                    end
                end

                control = Dict{String, Any}("action" => action, "condition" => condition)
                link["controls"][control_name] = control
            end
        end
    end
end

function _read_curves!(data::Dict{String, <:Any})
    data["curves"] = Dict{String, Array{Tuple{Float64, Float64}}}()

    for (line_number, line) in data["sections"]["[CURVES]"]
        line = split(line, ";")[1]
        current = split(line)

        if length(current) == 0
            continue
        else
            curve_name = current[1]

            if !(curve_name in keys(data["curves"]))
                data["curves"][curve_name] = Array{Tuple{Float64, Float64}, 1}()
            end

            x = parse(Float64, current[2])
            y = parse(Float64, current[3])

            data["curves"][curve_name] = vcat(data["curves"][curve_name], (x, y))
        end
    end
end

function _read_energy!(data::Dict{String, <:Any})
    for (line_number, line) in data["sections"]["[ENERGY]"]
        line = split(line, ";")[1]
        current = split(line)

        if length(current) == 0
            continue
        else
            if uppercase(current[1]) == "GLOBAL"
                if uppercase(current[2]) == "PRICE"
                    data["options"]["energy"]["global_price"] = parse(Float64, current[3])
                elseif uppercase(current[2]) == "PATTERN"
                    data["options"]["energy"]["global_pattern"] = current[3]
                elseif uppercase(current[2]) in ["EFFIC", "EFFICIENCY"]
                    data["options"]["energy"]["global_efficiency"] = parse(Float64, current[3])
                else
                    Memento.warning(_LOGGER, "Unknown entry in ENERGY section: $(line)")
                end
            elseif uppercase(current[1]) == "DEMAND"
                data["options"]["energy"]["demand_charge"] = parse(Float64, current[3])
            elseif uppercase(current[1]) == "PUMP"
                pump =  _get_link_by_name(data, current[2])

                if uppercase(current[3]) == "PRICE"
                    price = parse(Float64, current[4]) # Price per kilowatt hour.
                    pump["energy_price"] = price * 2.778e-7 # Price per Joule.
                elseif uppercase(current[3]) == "PATTERN"
                    pump["energy_pattern_name"] = current[4]
                elseif uppercase(current[3]) in ["EFFIC", "EFFICIENCY"]
                    pump["efficiency_curve_name"] = current[4]

                    # Obtain and scale head-versus-flow pump curve.
                    x = first.(data["curves"][current[4]]) # Flow rate.
                    y = 0.01 .* last.(data["curves"][current[4]]) # Efficiency.

                    if data["options"]["hydraulic"]["units"] == "LPS" # If liters per second...
                        # Convert from liters per second to cubic meters per second.
                        x *= 1.0e-3
                    elseif data["options"]["hydraulic"]["units"] == "GPM" # If gallons per minute...
                        # Convert from gallons per minute to cubic meters per second.
                        x *= 6.30902e-5
                    else
                        Memento.error(_LOGGER, "Could not find a valid \"Units\" option type.")
                    end

                    # Curve of efficiency (unitless) versus the flow rate through a pump.
                    pump["efficiency_curve"] = Array{Tuple{Float64, Float64}}([(x[j], y[j]) for j in 1:length(x)])
                else
                    Memento.warning(_LOGGER, "Unknown entry in ENERGY section: $(line)")
                end
            else
                Memento.warning(_LOGGER, "Unknown entry in ENERGY section: $(line)")
            end
        end
    end

    for (pump_id, pump) in data["pumps"]
        if "energy_pattern_name" in keys(pump) && "energy_price" in keys(pump)
            base_price = pump["energy_price"]
            pattern_name = pump["energy_pattern_name"]
            pattern = data["patterns"][pattern_name]
            price_pattern = base_price .* pattern

            entry = Dict{String, Array{Float64}}("energy_price" => price_pattern)
            data["time_series"]["pumps"][pump_id] = entry
        end
    end
end

function _read_junctions!(data::Dict{String, <:Any})
    data["junctions"] = DataStructures.OrderedDict{String, Dict{String, Any}}()
    data["time_series"]["junctions"] = DataStructures.OrderedDict{String, Any}()

    # Get the demand units (e.g., LPS, GPM).
    demand_units = data["options"]["hydraulic"]["units"]

    for (line_number, line) in data["sections"]["[JUNCTIONS]"]
        line = split(line, ";")[1]
        current = split(line)

        if length(current) == 0
            continue
        else
            junction = Dict{String, Any}()

            junction["name"] = current[1]
            junction["source_id"] = ["junctions", current[1]]

            if length(current) > 3
                junction["demand_pattern_name"] = current[4]
            elseif data["options"]["hydraulic"]["pattern"] != nothing
                junction["demand_pattern_name"] = data["options"]["hydraulic"]["pattern"]
            else
                junction["demand_pattern_name"] = data["options"]["hydraulic"]["pattern"]
                # TODO: What should the below be?
                #junction["pattern"] = data["patterns"]["default_pattern"]
            end

            junction["demand"] = 0.0

            if demand_units == "LPS" # If liters per second...
                # Retain the original value (in meters).
                junction["elevation"] = parse(Float64, current[2])
            elseif demand_units == "GPM" # If gallons per minute...
                # Convert elevation from feet to meters.
                junction["elevation"] = 0.3048 * parse(Float64, current[2])
            else
                Memento.error(_LOGGER, "Could not find a valid \"units\" option type.")
            end

            if length(current) > 2
                if demand_units == "LPS" # If liters per second...
                    # Convert from liters per second to cubic meters per second.
                    junction["demand"] = 1.0e-3 * parse(Float64, current[3])
                elseif demand_units == "GPM" # If gallons per minute...
                    # Convert from gallons per minute to cubic meters per second.
                    junction["demand"] = 6.30902e-5 * parse(Float64, current[3])
                end
            end

            data["junctions"][current[1]] = junction

            # Add time series of demand if necessary.
            pattern = junction["demand_pattern_name"]

            if pattern != nothing && length(data["patterns"][pattern]) > 1
                demand = junction["demand"] .* data["patterns"][pattern]
                entry = Dict{String, Array{Float64}}("demand" => demand)
                data["time_series"]["junctions"][current[1]] = entry
            elseif pattern != nothing && pattern != "1"
                junction["demand"] *= data["patterns"][pattern][1]
            end
        end
    end
end

function _read_options!(data::Dict{String, <:Any})
    data["options"] = DataStructures.OrderedDict{String, Any}(
        "energy" => Dict{String, Any}(), "hydraulic" => Dict{String, Any}(),
        "quality" => Dict{String, Any}(), "solver" => Dict{String, Any}(),
        "graphics" => Dict{String, Any}(), "time" => Dict{String, Any}(),
        "results" => Dict{String, Any}())

    for (line_number, line) in data["sections"]["[OPTIONS]"]
        words, comments = _split_line(line)

        if words != nothing && length(words) > 0
            if length(words) < 2
                Memento.error(_LOGGER, "No value provided for $(words[1])")
            end

            key = uppercase(words[1])

            if key == "UNITS"
                data["options"]["hydraulic"]["units"] = uppercase(words[2])
            elseif key == "HEADLOSS"
                data["options"]["hydraulic"]["headloss"] = uppercase(words[2])
            elseif key == "HYDRAULICS"
                data["options"]["hydraulic"]["hydraulics"] = uppercase(words[2])
                data["options"]["hydraulic"]["hydraulics_filename"] = words[3]
            elseif key == "QUALITY" # TODO: Implement this if/when needed.
            elseif key == "VISCOSITY"
                data["options"]["hydraulic"]["viscosity"] = 1.0e-3 * parse(Float64, words[2])
            elseif key == "DIFFUSIVITY"
                data["options"]["hydraulic"]["diffusivity"] = parse(Float64, words[2])
            elseif key == "SPECIFIC"
                data["options"]["hydraulic"]["specific_gravity"] = parse(Float64, words[3])
            elseif key == "TRIALS"
                data["options"]["solver"]["trials"] = parse(Int64, words[2])
            elseif key == "ACCURACY"
                data["options"]["solver"]["accuracy"] = parse(Float64, words[2])
            elseif key == "UNBALANCED"
                data["options"]["solver"]["unbalanced"] = uppercase(words[2])

                if length(words) > 2
                    data["options"]["solver"]["unbalanced_value"] = parse(Float64, words[3])
                end
            elseif key == "PATTERN"
                data["options"]["hydraulic"]["pattern"] = words[2]
            elseif key == "DEMAND"
                if length(words) > 2
                    data["options"]["hydraulic"]["demand_multiplier"] = parse(Float64, words[3])
                else
                    Memento.error(_LOGGER, "No value provided for Demand Multiplier")
                end
            elseif key == "EMITTER"
                if length(words) > 2
                    data["options"]["hydraulic"]["emitter_exponent"] = parse(Float64, words[3])
                else
                    Memento.error(_LOGGER, "No value provided for Emitter Exponent")
                end
            elseif key == "TOLERANCE"
                data["options"]["solver"]["tolerance"] = parse(Float64, words[2])
            elseif key == "CHECKFREQ"
                data["options"]["solver"]["checkfreq"] = parse(Float64, words[2])
            elseif key == "MAXCHECK"
                data["options"]["solver"]["maxcheck"] = parse(Float64, words[2])
            elseif key == "DAMPLIMIT"
                data["options"]["solver"]["damplimit"] = parse(Float64, words[2])
            elseif key == "MAP"
                data["options"]["graphics"]["map_filename"] = words[2]
            else
                if length(words) == 2
                    data["options"][lowercase(words[1])] = parse(Float64, words[2])
                    Memento.warn(_LOGGER, "Option \"$(key)\" is undocumented; adding, but please verify syntax")
                elseif length(words) == 3
                    fieldname = lowercase(words[1]) * "_" * lowercase(words[2])
                    data["options"][fieldname] = parse(Float64, words[3])
                    Memento.warn(_LOGGER, "Option \"$(key)\" is undocumented; adding, but please verify syntax")
                end
            end
        end
    end
end

function _read_patterns!(data::Dict{String, <:Any})
    data["patterns"] = DataStructures.OrderedDict{String, Array}()

    for (line_number, line) in data["sections"]["[PATTERNS]"]
        # Read the lines for each pattern. Patterns can be multiple lines of arbitrary length.
        line = split(line, ";")[1]
        current = split(line)

        if length(current) == 0
            continue
        else
            pattern_name = current[1]

            if !(pattern_name in keys(data["patterns"]))
                data["patterns"][pattern_name] = Array{Float64, 1}()

                for i in current[2:end]
                    value = parse(Float64, i)
                    data["patterns"][pattern_name] = vcat(data["patterns"][pattern_name], value)
                end
            else
                for i in current[2:end]
                    value = parse(Float64, i)
                    data["patterns"][pattern_name] = vcat(data["patterns"][pattern_name], value)
                end
            end
        end
    end

    # Ensure the hydraulic and pattern time steps are equal.
    if "pattern_timestep" in keys(data["options"]["time"])
        hydraulic_timestep = data["options"]["time"]["hydraulic_timestep"]
        pattern_timestep = data["options"]["time"]["pattern_timestep"]

        if hydraulic_timestep != pattern_timestep
            factor = convert(Int64, pattern_timestep / hydraulic_timestep)

            for (pattern_name, pattern) in data["patterns"]
                pattern = [pattern[div(i, factor)+1] for i=0:factor*length(pattern)-1]
                data["patterns"][pattern_name] = pattern
            end
        end
    end

    if data["options"]["hydraulic"]["pattern"] == "" && "1" in keys(data["patterns"])
        # If there is a pattern called "1", then it is the default pattern if no other is supplied.
        data["options"]["hydraulic"]["pattern"] = "1"
    elseif !(data["options"]["hydraulic"]["pattern"] in keys(data["patterns"]))
        # Sanity check: if the default pattern does not exist and it is not "1", then balk.
        # If default is "1" but it does not exist, then it is constant.
        # Any other default that does not exist is an error.
        if data["options"]["hydraulic"]["pattern"] != nothing && data["options"]["hydraulic"]["pattern"] != "1"
            Memento.error("Default pattern \"$(data["options"]["hydraulic"]["pattern"])\" is undefined.")
        end

        data["options"]["hydraulic"]["pattern"] = nothing
    end
end

function _read_pipes!(data::Dict{String, <:Any})
    data["pipes"] = DataStructures.OrderedDict{String, Dict{String, Any}}()

    # Get the demand units (e.g., LPS, GPM).
    demand_units = data["options"]["hydraulic"]["units"]

    # Get the headloss type (D-W or H-W).
    headloss = data["options"]["hydraulic"]["headloss"]

    for (line_number, line) in data["sections"]["[PIPES]"]
        line = split(line, ";")[1]
        current = split(line)

        if length(current) == 0
            continue
        else
            pipe = Dict{String, Any}()
            pipe["name"] = current[1]
            pipe["source_id"] = ["pipes", current[1]]
            pipe["start_node_name"] = current[2]
            pipe["end_node_name"] = current[3]
            pipe["controls"] = Dict{String, Any}()

            if demand_units == "LPS" # If liters per second...
                # Retain the original value (in meters).
                pipe["length"] = parse(Float64, current[4])

                # Convert diameter from millimeters to meters.
                pipe["diameter"] = 0.001 * parse(Float64, current[5])

                if headloss == "D-W"
                    # Convert roughness from millimeters to meters.
                    pipe["roughness"] = 0.001 * parse(Float64, current[6])
                elseif headloss == "H-W"
                    # Retain the original value (unitless).
                    pipe["roughness"] = parse(Float64, current[6])
                end
            elseif demand_units == "GPM" # If gallons per minute...
                # Convert length from feet to meters.
                pipe["length"] = 0.3048 * parse(Float64, current[4])

                # Convert diameter from inches to meters.
                pipe["diameter"] = 0.0254 * parse(Float64, current[5])

                if headloss == "D-W"
                    # Convert roughness from millifeet to meters.
                    pipe["roughness"] = 3.048e-4 * parse(Float64, current[6])
                elseif headloss == "H-W"
                    # Retain the original value (unitless).
                    pipe["roughness"] = parse(Float64, current[6])
                end
            else
                error("Could not find a valid \"units\" option type.")
            end

            pipe["minor_loss"] = parse(Float64, current[7])
            pipe["status"] = current[8]
            pipe["initial_status"] = current[8]

            # If the pipe has a check valve, ensure unidirectional flow.
            if uppercase(pipe["status"]) == "CV"
                pipe["flow_direction"] = POSITIVE
            else
                pipe["flow_direction"] = UNKNOWN
            end

            data["pipes"][current[1]] = pipe
        end
    end
end

function _read_pumps!(data::Dict{String, <:Any})
    data["pumps"] = DataStructures.OrderedDict{String, Dict{String, Any}}()
    data["time_series"]["pumps"] = DataStructures.OrderedDict{String, Any}()

    for (line_number, line) in data["sections"]["[PUMPS]"]
        line = split(line, ";")[1]
        current = split(line)

        if length(current) == 0
            continue
        else
            pump = Dict{String, Any}()
            pump["name"] = current[1]
            pump["source_id"] = ["pumps", current[1]]
            pump["start_node_name"] = current[2]
            pump["end_node_name"] = current[3]
            pump["controls"] = Dict{String, Any}()
            pump["initial_status"] = nothing

            pump["pump_type"] = nothing
            pump["power"] = nothing
            pump["pump_curve_name"] = nothing
            pump["base_speed"] = nothing
            pump["speed_pattern_name"] = nothing

            for i in range(4, length(current), step=2)
                if uppercase(current[i]) == "HEAD"
                    pump["pump_type"] = "HEAD"
                    pump["pump_curve_name"] = current[i+1]

                    # Obtain and scale head-versus-flow pump curve.
                    x = first.(data["curves"][current[i+1]]) # Flow.
                    y = last.(data["curves"][current[i+1]]) # Head.

                    if data["options"]["hydraulic"]["units"] == "LPS" # If liters per second...
                        # Convert from liters per second to cubic meters per second.
                        x *= 1.0e-3
                    elseif data["options"]["hydraulic"]["units"] == "GPM" # If gallons per minute...
                        # Convert from gallons per minute to cubic meters per second.
                        x *= 6.30902e-5

                        # Convert elevation from feet to meters.
                        y *= 0.3048
                    else
                        Memento.error(_LOGGER, "Could not find a valid \"units\" option type.")
                    end

                    # Curve of head (meters) versus flow (cubic meters per second).
                    pump["pump_curve"] = Array{Tuple{Float64, Float64}}([(x[j], y[j]) for j in 1:length(x)])
                # TODO: Fill in the remaining cases below.
                elseif uppercase(current[i]) == "POWER"
                elseif uppercase(current[i]) == "SPEED"
                elseif uppercase(current[i]) == "PATTERN"
                else
                    Memento.error(_LOGGER, "Pump keyword in INP file not recognized.")
                end
            end

            if pump["base_speed"] == nothing
                pump["base_speed"] = 1.0
            end

            if pump["pump_type"] == nothing
                Memento.error(_LOGGER, "Either head curve ID or pump power must be specified for all pumps.")
            end

            pump["flow_direction"] = POSITIVE

            data["pumps"][current[1]] = pump
        end
    end
end

function _read_reservoirs!(data::Dict{String, <:Any})
    data["reservoirs"] = DataStructures.OrderedDict{String, Dict{String, Any}}()
    data["time_series"]["reservoirs"] = DataStructures.OrderedDict{String, Any}()

    # Get the demand units (e.g., LPS, GPM).
    demand_units = data["options"]["hydraulic"]["units"]

    for (line_number, line) in data["sections"]["[RESERVOIRS]"]
        line = split(line, ";")[1]
        current = split(line)

        if length(current) == 0
            continue
        else
            reservoir = Dict{String, Any}()

            reservoir["name"] = current[1]
            reservoir["source_id"] = ["reservoirs", current[1]]

            if length(current) >= 2
                if demand_units == "LPS" # If liters per second...
                    # Retain the original value (in meters).
                    reservoir["head"] = parse(Float64, current[2])
                    reservoir["elevation"] = parse(Float64, current[2])
                elseif demand_units == "GPM" # If gallons per minute...
                    # Convert elevation from feet to meters.
                    reservoir["head"] = 0.3048 * parse(Float64, current[2])
                    reservoir["elevation"] = 0.3048 * parse(Float64, current[2])
                else
                    Memento.error(_LOGGER, "Could not find a valid \"units\" option type.")
                end

                if length(current) >= 3
                    reservoir["head_pattern_name"] = current[3]
                else
                    reservoir["head_pattern_name"] = nothing
                end
            end

            data["reservoirs"][current[1]] = reservoir

            # Add time series of demand if necessary.
            pattern = reservoir["head_pattern_name"]

            if pattern != nothing && length(data["patterns"][pattern]) > 1
                head = reservoir["head"] .* data["patterns"][pattern]
                entry = Dict{String, Array{Float64}}("head" => head, "elevation" => head)
                data["time_series"]["reservoirs"][current[1]] = entry
            elseif pattern != nothing && pattern != "1"
                reservoir["head"] *= data["patterns"][pattern][1]
                reservoir["elevation"] *= data["patterns"][pattern][1]
            end
        end
    end
end

function _read_status!(data::Dict{String, <:Any})
    for (line_number, line) in data["sections"]["[STATUS]"]
        line = split(line, ";")[1]
        current = split(line)

        if length(current) == 0
            continue
        else
            status_value = current[2]
            link =  _get_link_by_name(data, current[1])

            if uppercase(current[2]) in ["OPEN", "CLOSED", "ACTIVE"]
                link["status"] = current[2]
                link["initial_status"] = current[2]
            else
                if _get_link_type_by_name(data, current[1]) == "valves"
                    # TODO: Do something to fill valve statuses here.
                else
                    link["initial_setting"] = parse(Float64, current[2])
                    link["status"] = "Open"
                    link["initial_status"] = "Open"
                end
            end
        end
    end
end

function _read_tanks!(data::Dict{String, <:Any})
    data["tanks"] = DataStructures.OrderedDict{String, Dict{String, Any}}()

    for (line_number, line) in data["sections"]["[TANKS]"]
        line = split(line, ";")[1]
        current = split(line)

        if length(current) == 0
            continue
        else
            tank = Dict{String, Any}()

            tank["name"] = current[1]
            tank["source_id"] = ["tanks", current[1]]

            if data["options"]["hydraulic"]["units"] == "LPS" # If liters per second...
                # Retain the original values (in meters).
                tank["elevation"] = parse(Float64, current[2])
                tank["init_level"] = parse(Float64, current[3])
                tank["min_level"] = parse(Float64, current[4])
                tank["max_level"] = parse(Float64, current[5])
                tank["diameter"] = parse(Float64, current[6])

                # Retain the original values (in cubic meters).
                tank["min_vol"] = parse(Float64, current[7])
            elseif data["options"]["hydraulic"]["units"] == "GPM" # If gallons per minute...
                # Convert values from feet to meters.
                tank["elevation"] = 0.3048 * parse(Float64, current[2])
                tank["init_level"] = 0.3048 * parse(Float64, current[3])
                tank["min_level"] = 0.3048 * parse(Float64, current[4])
                tank["max_level"] = 0.3048 * parse(Float64, current[5])
                tank["diameter"] = 0.3048 * parse(Float64, current[6])

                # Convert values from cubic feet to cubic meters.
                tank["min_vol"] = 0.3048^3 * parse(Float64, current[7])
            else
                Memento.error(_LOGGER, "Could not find a valid \"Units\" option type.")
            end

            if length(current) == 8 # Volume curve provided.
                # TODO: Include the curve in the tank object.
                tank["curve_name"] = current[8]
            elseif length(current) == 7
                tank["curve_name"] = nothing
            else
                Memento.error(_LOGGER, "Tank entry format not recognized")
            end

            data["tanks"][current[1]] = tank
        end
    end
end

function _read_times!(data::Dict{String, <:Any})
    time_format = ["am", "AM", "pm", "PM"]
    data["options"]["time"] = Dict{String, Any}()

    for (line_number, line) in data["sections"]["[TIMES]"]
        line = split(line, ";")[1]
        current = split(line)

        if length(current) == 0
            continue
        end

        if uppercase(current[1]) == "DURATION"
            data["options"]["time"]["duration"] = _string_time_to_seconds(current[2])
        elseif uppercase(current[1]) == "HYDRAULIC"
            data["options"]["time"]["hydraulic_timestep"] = _string_time_to_seconds(current[3])
        elseif uppercase(current[1]) == "QUALITY"
            data["options"]["time"]["quality_timestep"] = _string_time_to_seconds(current[3])
        elseif uppercase(current[1]) == "CLOCKTIME"
            if length(current) > 3
                time_format = uppercase(current[4])
            else
                # Kludge for 24 hour time that needs AM/PM.
                time_format = "AM"
            end

            data["options"]["time"]["start_clocktime"] = _clock_time_to_seconds(current[3], time_format)
        elseif uppercase(current[1]) == "STATISTIC"
            data["options"]["results"]["statistic"] = uppercase(current[2])
        else
            # Other time options: RULE TIMESTEP, PATTERN TIMESTEP, REPORT TIMESTEP, REPORT START
            key_string = lowercase(current[1] * '_' * current[2])
            data["options"]["time"][key_string] = _string_time_to_seconds(current[3])
        end
    end
end

function _read_title!(data::Dict{String, <:Any})
    lines = Array{String}[]

    for (line_number, line) in data["sections"]["[TITLE]"]
        line = split(line, ";")[1]
        current = split(line)

        if length(current) == 0
            continue
        else
            lines = vcat(lines, line)
        end
    end

    data["name"] = join(lines, " ")
end

function _read_valves!(data::Dict{String, <:Any})
    data["valves"] = DataStructures.OrderedDict{String, Dict{String, Any}}()

    for (line_number, line) in data["sections"]["[VALVES]"]
        line = split(line, ";")[1]
        current = split(line)

        if length(current) == 0
            continue
        else
            valve = Dict{String, Any}()
            valve["name"] = current[1]
            valve["source_id"] = ["valves", current[1]]
            valve["controls"] = Dict{String, Any}()

            # TODO: Finish the rest of valve parsing before appending.
            data["valves"][current[1]] = valve
        end
    end
end
