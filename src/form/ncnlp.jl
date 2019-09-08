# Define NCNLP (non-convex nonlinear programming) implementations of water distribution models.

function variable_head(wm::AbstractNCNLPModel, n::Int=wm.cnw) 
    variable_hydraulic_head(wm, n)
    variable_head_gain(wm, n)
end

function variable_flow(wm::AbstractNCNLPModel, n::Int=wm.cnw) 
    variable_undirected_flow(wm, n, bounded=true)
end

function variable_flow_ne(wm::AbstractNCNLPModel, n::Int=wm.cnw) 
    variable_undirected_flow_ne(wm, n, bounded=true)
end

function variable_pump(wm::AbstractNCNLPModel, n::Int=wm.cnw) 
    variable_fixed_speed_pump_operation(wm, n)
    # TODO: The below need not be created in the OWF.
    variable_fixed_speed_pump_threshold(wm, n) 
end

function constraint_potential_loss_ub_pipe_ne(wm::AbstractNCNLPModel, n::Int, a::Int, alpha, len, pipe_resistances) 
end

function constraint_potential_loss_pipe_ne(wm::AbstractNCNLPModel, n::Int, a::Int, alpha, node_fr, node_to, len, pipe_resistances) 
    if !haskey(con(wm, n), :potential_loss_ne)
        con(wm, n)[:potential_loss_ne] = Dict{Int, JuMP.ConstraintRef}()
    end

    h_i = var(wm, n, :h, node_fr)
    h_j = var(wm, n, :h, node_to)
    q_ne = var(wm, n, :q_ne, a)

    c = JuMP.@NLconstraint(wm.model, sum(r * head_loss(q_ne[r_id]) for (r_id, r)
        in enumerate(pipe_resistances)) - inv(len) * (h_i - h_j) == 0.0)

    con(wm, n, :potential_loss_ne)[a] = c
end


function constraint_head_difference(wm::AbstractNCNLPModel, n::Int, a::Int, node_fr, node_to, head_fr, head_to) 
end

function constraint_potential_loss_ub_pipe(wm::AbstractNCNLPModel, n::Int, a::Int, alpha, len, r_max) 
end

function constraint_potential_loss_check_valve(wm::AbstractNCNLPModel, n::Int, a::Int, node_fr::Int, node_to::Int, len::Float64, r::Float64) 
    q = var(wm, n, :q, a)
    h_i = var(wm, n, :h, node_fr)
    h_j = var(wm, n, :h, node_to)
    x_cv = var(wm, n, :x_cv, a)

    # TODO: Possible formulation below (expand out...)?
    #c = JuMP.@NLconstraint(wm.model, x_cv * r * head_loss(q) - inv(len) * x_cv * (h_i - h_j) == 0.0)
    #c = JuMP.@NLconstraint(wm.model, (1 - x_cv) * h_j >= (1 - x_cv) * h_i)
    c_1 = JuMP.@NLconstraint(wm.model, r * head_loss(q) - inv(len) * (h_i - h_j) <= 1.0e6 * (1 - x_cv))
    c_2 = JuMP.@NLconstraint(wm.model, r * head_loss(q) - inv(len) * (h_i - h_j) >= -1.0e6 * (1 - x_cv))
end

function constraint_potential_loss_pipe(wm::AbstractNCNLPModel, n::Int, a::Int, alpha, node_fr, node_to, len, r_min) 
    if !haskey(con(wm, n), :potential_loss)
        con(wm, n)[:potential_loss] = Dict{Int, JuMP.ConstraintRef}()
    end

    h_i = var(wm, n, :h, node_fr)
    h_j = var(wm, n, :h, node_to)
    q = var(wm, n, :q, a)

    c = JuMP.@NLconstraint(wm.model, r_min * head_loss(q) - inv(len) * (h_i - h_j) == 0.0)
    con(wm, n, :potential_loss)[a] = c
end

function constraint_potential_loss_pump(wm::AbstractNCNLPModel, n::Int, a::Int, node_fr::Int, node_to::Int) 
    if !haskey(con(wm, n), :potential_loss_1)
        con(wm, n)[:potential_loss_1] = Dict{Int, JuMP.ConstraintRef}()
        con(wm, n)[:potential_loss_2] = Dict{Int, JuMP.ConstraintRef}()
        con(wm, n)[:potential_loss_3] = Dict{Int, JuMP.ConstraintRef}()
        con(wm, n)[:potential_loss_4] = Dict{Int, JuMP.ConstraintRef}()
        con(wm, n)[:potential_loss_5] = Dict{Int, JuMP.ConstraintRef}()
        con(wm, n)[:potential_loss_6] = Dict{Int, JuMP.ConstraintRef}()
    end

    h_i = var(wm, n, :h, node_fr)
    h_j = var(wm, n, :h, node_to)

    q = var(wm, n, :q, a)
    g = var(wm, n, :g, a)
    x_pump = var(wm, n, :x_pump, a)

    # TODO: Big- and little-M values below need to be improved.
    M = 1.0e6
    m = 1.0e-6

    c_1 = JuMP.@constraint(wm.model, -(h_i - h_j) - g <= M * (1 - x_pump))
    c_2 = JuMP.@constraint(wm.model, -(h_i - h_j) - g >= -M * (1 - x_pump))
    con(wm, n, :potential_loss_1)[a] = c_1
    con(wm, n, :potential_loss_2)[a] = c_2

    # TODO: These can probably be stronger.
    c_3 = JuMP.@constraint(wm.model, q <= M * x_pump)
    c_4 = JuMP.@constraint(wm.model, q >= m * x_pump)
    #con(wm, n, :potential_loss_3)[a] = c_3
    #con(wm, n, :potential_loss_4)[a] = c_4

    # TODO: Why does the problem become infeasible when these are active?
    #con(wm, n, :potential_loss_5)[a] = JuMP.@constraint(wm.model, q <= JuMP.upper_bound(q) * x_pump)
    #con(wm, n, :potential_loss_6)[a] = JuMP.@NLconstraint(wm.model, x_pump * h_i <= x_pump * h_j)
end

function get_function_from_pump_curve(pump_curve::Array{Tuple{Float64,Float64}})
    LsqFit.@. func(x, p) = p[1]*x*x + p[2]*x + p[3]

    if length(pump_curve) > 1
        fit = LsqFit.curve_fit(func, first.(pump_curve), last.(pump_curve), [0.0, 0.0, 0.0])
        return LsqFit.coef(fit)
    elseif length(pump_curve) == 1
        new_points = [(0.0, 1.33 * pump_curve[1][2]), (2.0 * pump_curve[1][1], 0.0)]
        pump_curve = vcat(new_points, pump_curve)
        fit = LsqFit.curve_fit(func, first.(pump_curve), last.(pump_curve), [0.0, 0.0, 0.0])
        return LsqFit.coef(fit)
    end
end

function constraint_head_gain_pump_quadratic_fit(wm::AbstractNCNLPModel, n::Int, a::Int, A, B, C) 
    q = var(wm, n, :q, a)
    g = var(wm, n, :g, a)
    x_pump = var(wm, n, :x_pump, a)

    c = JuMP.@NLconstraint(wm.model, A*q^2 + B*q + C*x_pump == g)
    con(wm, n, :head_gain)[a] = c
end

function objective_wf(wm::AbstractNCNLPModel, n::Int=wm.cnw) 
    JuMP.set_objective_sense(wm.model, _MOI.FEASIBILITY_SENSE)
end

function objective_owf(wm::AbstractNCNLPModel) 
    expr = JuMP.AffExpr(0.0)

    for (n, nw_ref) in nws(wm)
        pump_ids = ids(wm, n, :pumps)
        costs = JuMP.@variable(wm.model, [a in pump_ids], base_name="costs[$(n)]",
                               start=get_start(ref(wm, n, :pumps), a, "costs", 0.0))

        efficiency = 0.85 # TODO: Change this after discussion. 0.85 follows Fooladivanda.
        rho = 1000.0 # Water density.
        g = 9.80665 # Gravitational acceleration.

        time_step = nw_ref[:options]["time"]["hydraulic_timestep"]
        constant = rho * g * time_step * inv(efficiency)

        for (a, pump) in nw_ref[:pumps]
            if haskey(pump, "energy_price")
                g = var(wm, n)[:g][a]
                q = var(wm, n)[:q][a]

                energy_price = pump["energy_price"]
                pump_cost = JuMP.@NLexpression(wm.model, constant * energy_price * g * q)
                con = JuMP.@NLconstraint(wm.model, pump_cost <= costs[a])
            else
                Memento.error(_LOGGER, "No cost given for pump \"$(pump["name"])\"")
            end
        end

        expr += sum(costs)
    end

    return JuMP.@objective(wm.model, _MOI.MIN_SENSE, expr)
end
