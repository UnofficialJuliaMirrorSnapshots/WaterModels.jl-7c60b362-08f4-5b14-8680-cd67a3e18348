function run_ne(network, model_constructor, optimizer; relaxed::Bool=false, kwargs...)
    return run_generic_model(network, model_constructor, optimizer, post_ne, relaxed=relaxed; kwargs...)
end

function post_ne(wm::GenericWaterModel{T}) where T
    if T <: AbstractCNLPForm
        Memento.error(_LOGGER, "CNLP formulation does not support network expansion.")
    end

    function_head_loss(wm)

    variable_reservoir(wm)
    variable_tank(wm)
    variable_check_valve(wm)
    variable_head(wm)
    variable_flow(wm)
    variable_volume(wm)
    variable_pump(wm)
    variable_flow_ne(wm)
    variable_resistance_ne(wm)

    for a in ids(wm, :links)
        constraint_link_flow(wm, a)
    end

    for a in setdiff(ids(wm, :pipes), ids(wm, :pipes_ne))
        constraint_potential_loss_pipe(wm, a)
    end

    for a in ids(wm, :check_valves)
        constraint_check_valve(wm, a)
        constraint_potential_loss_check_valve(wm, a)
    end

    for a in ids(wm, :pipes_ne)
        constraint_potential_loss_pipe_ne(wm, a)
        constraint_resistance_selection_ne(wm, a)
        constraint_link_flow_ne(wm, a)
    end

    for a in ids(wm, :pumps)
        constraint_potential_loss_pump(wm, a)
    end

    for a in ids(wm, :check_valves)
        constraint_check_valve(wm, a)
    end

    for (i, node) in ref(wm, :nodes)
        constraint_flow_conservation(wm, i)

        #if junction["demand"] > 0.0
        #    constraint_sink_flow(wm, i)
        #end
    end

    for i in ids(wm, :tanks)
        constraint_link_volume(wm, i)
    end

    #for i in collect(ids(wm, :reservoirs))
    #    constraint_source_flow(wm, i)
    #end

    objective_ne(wm)
end
