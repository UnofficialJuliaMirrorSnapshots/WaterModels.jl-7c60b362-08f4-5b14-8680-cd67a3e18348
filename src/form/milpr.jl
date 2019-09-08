# Define MILPR (mixed-integer linear, relaxed program) implementations of water distribution models.

function variable_head(wm::AbstractMILPRModel, n::Int=wm.cnw) 
    variable_hydraulic_head(wm, n)
    variable_directed_head_difference(wm, n)
end

function variable_flow(wm::AbstractMILPRModel, n::Int=wm.cnw) 
    variable_undirected_flow(wm, n, bounded=true)
    variable_directed_flow(wm, n, bounded=true)
    variable_flow_direction(wm, n)
end

function variable_flow_ne(wm::AbstractMILPRModel, n::Int=wm.cnw) 
    variable_directed_flow_ne(wm, n, bounded=true)
end

function variable_pump(wm::AbstractMILPRModel, n::Int=wm.cnw) 
end

function constraint_potential_loss_pump(wm::AbstractMILPRModel, n::Int, a::Int, node_fr::Int, node_to::Int) 
end


function get_linear_outer_approximation(q::JuMP.VariableRef, q_hat::Float64, alpha::Float64)
    return q_hat^alpha + alpha * q_hat^(alpha - 1.0) * (q - q_hat)
end

function constraint_potential_loss_pipe_ne(wm::AbstractMILPRModel, n::Int, a::Int, alpha, node_fr, node_to, len, pipe_resistances) 
    if !haskey(con(wm, n), :potential_loss_pipe_n_ne)
        con(wm, n)[:potential_loss_pipe_n_ne] = Dict{Int, Dict{Int, JuMP.ConstraintRef}}()
        con(wm, n)[:potential_loss_pipe_p_ne] = Dict{Int, Dict{Int, JuMP.ConstraintRef}}()
    end

    con(wm, n, :potential_loss_pipe_n_ne)[a] = Dict{Int, JuMP.ConstraintRef}()
    con(wm, n, :potential_loss_pipe_p_ne)[a] = Dict{Int, JuMP.ConstraintRef}()

    L = len

    for (r_id, r) in enumerate(pipe_resistances)
        qn_ne = var(wm, n, :qn_ne, a)[r_id]
        qn_ne_ub = JuMP.upper_bound(qn_ne)
        dhn = var(wm, n, :dhn, a)

        if qn_ne_ub > 0.0
            for q_hat in range(0.0, stop=qn_ne_ub, length=5)
                cut_lhs = r * get_linear_outer_approximation(qn_ne, q_hat, alpha)
                con_n = JuMP.@constraint(wm.model, cut_lhs - inv(L) * dhn <= 0.0)
            end
        end

        qp_ne = var(wm, n, :qp_ne, a)[r_id]
        qp_ne_ub = JuMP.upper_bound(qp_ne)
        dhp = var(wm, n, :dhp, a)

        if qp_ne_ub > 0.0
            for q_hat in range(0.0, stop=qp_ne_ub, length=5)
                cut_lhs = r * get_linear_outer_approximation(qp_ne, q_hat, alpha)
                con_p = JuMP.@constraint(wm.model, cut_lhs - inv(L) * dhp <= 0.0)
            end
        end
    end
end

function constraint_potential_loss_pipe(wm::AbstractMILPRModel, n::Int, a::Int, alpha, node_fr, node_to, len, r_min) 
    if !haskey(con(wm, n), :potential_loss_pipe_n)
        con(wm, n)[:potential_loss_pipe_n] = Dict{Int, JuMP.ConstraintRef}()
        con(wm, n)[:potential_loss_pipe_p] = Dict{Int, JuMP.ConstraintRef}()
    end

    L = len
    r = r_min

    qn = var(wm, n, :qn, a)
    qn_ub = JuMP.upper_bound(qn)
    dhn = var(wm, n, :dhn, a)

    if qn_ub > 0.0
        for q_hat in range(0.0, stop=qn_ub, length=5)
            cut_lhs = r * get_linear_outer_approximation(qn, q_hat, alpha)
            con_n = JuMP.@constraint(wm.model, cut_lhs - inv(L) * dhn <= 0.0)
        end
    end

    qp = var(wm, n, :qp, a)
    qp_ub = JuMP.upper_bound(qp)
    dhp = var(wm, n, :dhp, a)

    if qp_ub > 0.0
        for q_hat in range(0.0, stop=qp_ub, length=5)
            cut_lhs = r * get_linear_outer_approximation(qp, q_hat, alpha)
            con_p = JuMP.@constraint(wm.model, cut_lhs - inv(L) * dhp <= 0.0)
        end
    end
end

function objective_wf(wm::AbstractMILPRModel, n::Int=wm.cnw) 
    JuMP.set_objective_sense(wm.model, _MOI.FEASIBILITY_SENSE)
end

function objective_owf(wm::AbstractMILPRModel) 
    JuMP.set_objective_sense(wm.model, _MOI.FEASIBILITY_SENSE)
end
