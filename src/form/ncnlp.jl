# Define NCNLP (non-convex nonlinear programming) implementations of water distribution models.

export NCNLPWaterModel, StandardNCNLPForm

abstract type AbstractNCNLPForm <: AbstractWaterFormulation end
abstract type StandardNCNLPForm <: AbstractNCNLPForm end

"The default NCNLP (non-convex nonlinear programming) model retains the exact head loss physics."
const NCNLPWaterModel = GenericWaterModel{StandardNCNLPForm}

"Default NCNLP constructor."
NCNLPWaterModel(data::Dict{String,Any}; kwargs...) = GenericWaterModel(data, StandardNCNLPForm; kwargs...)

function variable_head(wm::GenericWaterModel{T}, n::Int=wm.cnw) where T <: AbstractNCNLPForm
    variable_pressure_head(wm, n)
end

function variable_flow(wm::GenericWaterModel{T}, n::Int=wm.cnw; alpha::Float64=1.852) where T <: AbstractNCNLPForm
    variable_undirected_flow(wm, n, bounded=true)
end

function variable_flow_ne(wm::GenericWaterModel{T}, n::Int=wm.cnw; alpha::Float64=1.852) where T <: AbstractNCNLPForm
    variable_undirected_flow_ne(wm, n, bounded=true)
end

function constraint_resistance_selection_ne(wm::GenericWaterModel{T}, a::Int, n::Int=wm.cnw) where T <: AbstractNCNLPForm
    constraint_undirected_resistance_selection_ne(wm, a, n)
end

function constraint_potential_loss(wm::GenericWaterModel{T}, a::Int, n::Int=wm.cnw; alpha::Float64=1.852) where T <: AbstractNCNLPForm
    constraint_undirected_potential_loss(wm, a, n)
end

function constraint_potential_loss_ne(wm::GenericWaterModel{T}, a::Int, n::Int=wm.cnw; alpha::Float64=1.852) where T <: AbstractNCNLPForm
    constraint_undirected_potential_loss_ne(wm, a, n)
end

function constraint_flow_conservation(wm::GenericWaterModel{T}, i::Int, n::Int=wm.cnw) where T <: AbstractNCNLPForm
    constraint_undirected_flow_conservation(wm, i, n)
end

function constraint_flow_conservation_ne(wm::GenericWaterModel{T}, i::Int, n::Int=wm.cnw) where T <: AbstractNCNLPForm
    constraint_undirected_flow_conservation_ne(wm, i, n)
end

function constraint_link_flow_ne(wm::GenericWaterModel{T}, a::Int, n::Int=wm.cnw) where T <: AbstractNCNLPForm
    constraint_link_undirected_flow_ne(wm, a, n)
end

function constraint_link_flow(wm::GenericWaterModel{T}, a::Int, n::Int=wm.cnw) where T <: AbstractNCNLPForm
end

function constraint_source_flow(wm::GenericWaterModel{T}, i::Int, n::Int=wm.cnw) where T <: AbstractNCNLPForm
end

function constraint_sink_flow(wm::GenericWaterModel{T}, i::Int, n::Int=wm.cnw) where T <: AbstractNCNLPForm
end

function constraint_undirected_potential_loss_ne(wm::GenericWaterModel{T}, a::Int, n::Int) where T <: AbstractNCNLPForm
    if !haskey(wm.con[:nw][n], :potential_loss_ne)
        wm.con[:nw][n][:potential_loss_ne] = Dict{Int, JuMP.ConstraintRef}()
    end

    i = wm.ref[:nw][n][:links][a]["f_id"]

    if i in collect(ids(wm, n, :reservoirs))
        h_i = wm.ref[:nw][n][:reservoirs][i]["head"]
    else
        h_i = wm.var[:nw][n][:h][i]
    end

    j = wm.ref[:nw][n][:links][a]["t_id"]

    if j in collect(ids(wm, n, :reservoirs))
        h_j = wm.ref[:nw][n][:reservoirs][j]["head"]
    else
        h_j = wm.var[:nw][n][:h][j]
    end

    L = wm.ref[:nw][n][:links][a]["length"]
    q_ne = wm.var[:nw][n][:q_ne][a]
    resistances = wm.ref[:nw][n][:resistance][a]

    con = JuMP.@NLconstraint(wm.model, sum(r * f_alpha(q_ne[r_id]) for (r_id, r)
                             in enumerate(resistances)) - inv(L) * (h_i - h_j) == 0.0)

    wm.con[:nw][n][:potential_loss_ne][a] = con
end

function constraint_undirected_potential_loss(wm::GenericWaterModel{T}, a::Int, n::Int) where T <: AbstractNCNLPForm
    if !haskey(wm.con[:nw][n], :potential_loss)
        wm.con[:nw][n][:potential_loss] = Dict{Int, JuMP.ConstraintRef}()
    end

    i = wm.ref[:nw][n][:links][a]["f_id"]

    if i in collect(ids(wm, n, :reservoirs))
        h_i = wm.ref[:nw][n][:reservoirs][i]["head"]
    else
        h_i = wm.var[:nw][n][:h][i]
    end

    j = wm.ref[:nw][n][:links][a]["t_id"]

    if j in collect(ids(wm, n, :reservoirs))
        h_j = wm.ref[:nw][n][:reservoirs][j]["head"]
    else
        h_j = wm.var[:nw][n][:h][j]
    end

    L = wm.ref[:nw][n][:links][a]["length"]
    r = minimum(wm.ref[:nw][n][:resistance][a])
    q = wm.var[:nw][n][:q][a]

    con = JuMP.@NLconstraint(wm.model, r * f_alpha(q) - inv(L) * (h_i - h_j) == 0.0)

    wm.con[:nw][n][:potential_loss][a] = con
end

function objective_wf(wm::GenericWaterModel{T}, n::Int = wm.cnw) where T <: StandardNCNLPForm
    JuMP.set_objective_sense(wm.model, MOI.FEASIBILITY_SENSE)
end
