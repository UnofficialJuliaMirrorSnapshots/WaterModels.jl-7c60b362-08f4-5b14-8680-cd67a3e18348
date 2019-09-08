"Enumerated type specifying the direction of flow along a link."
@enum FLOW_DIRECTION POSITIVE=1 NEGATIVE=-1 UNKNOWN=0

"Models with two positive flow variables, one for each direction."
abstract type AbstractDirectedFlowModel <: AbstractWaterModel end

"Models with one flow variable, with the sign of the variable indicating the flow direction."
abstract type AbstractUndirectedFlowModel <: AbstractWaterModel end

"Models derived from AbstractDirectedFlowModel"
abstract type AbstractCNLPModel <: AbstractDirectedFlowModel end
mutable struct CNLPWaterModel <: AbstractCNLPModel @wm_fields end
abstract type AbstractMILPRModel <: AbstractDirectedFlowModel end
mutable struct MILPRWaterModel <: AbstractMILPRModel @wm_fields end
abstract type AbstractMICPModel <: AbstractDirectedFlowModel end
mutable struct MICPWaterModel <: AbstractMICPModel @wm_fields end

"Models derived from AbstractUndirectedFlowModel"
abstract type AbstractNCNLPModel <: AbstractUndirectedFlowModel end
mutable struct NCNLPWaterModel <: AbstractNCNLPModel @wm_fields end
abstract type AbstractMILPModel <: AbstractUndirectedFlowModel end
mutable struct MILPWaterModel <: AbstractMILPModel @wm_fields end
