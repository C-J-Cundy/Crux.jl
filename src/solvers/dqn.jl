@with_kw mutable struct DQNSolver <: Solver 
    π::DiscreteNetwork
    S::AbstractSpace
    A::DiscreteSpace = action_space(π)
    N::Int = 1000
    rng::AbstractRNG = Random.GLOBAL_RNG
    exploration_policy::ExplorationPolicy = EpsGreedyPolicy(LinearDecaySchedule(start=1., stop=0.1, steps=N/2), rng, π.outputs)
    loss::Function = Flux.Losses.huber_loss
    regularizer = (θ) -> 0
    opt = ADAM(1e-3)
    batch_size::Int = 32
    max_steps::Int = 100
    eval_eps::Int = 10
    ΔN::Int = 4
    epochs::Int = ΔN
    Δtarget_update::Int = 2000
    buffer_size = 1000
    buffer::ExperienceBuffer = ExperienceBuffer(S, A, buffer_size)
    buffer_init::Int = max(batch_size, 200)
    log::Union{Nothing, LoggerParams} = LoggerParams(dir = "log/dqn", period = 500)
    π⁻::DiscreteNetwork = deepcopy(π) # Target network
    device = device(π)
    i::Int = 0
end

DQN_target(π, 𝒟, γ::Float32) = 𝒟[:r] .+ γ .* (1.f0 .- 𝒟[:done]) .* maximum(value(π, 𝒟[:sp]), dims=1) # DQN

function POMDPs.solve(𝒮::DQNSolver, mdp, extra_buffers...)
    isprioritized = prioritized(𝒮.buffer)
    required_columns = isprioritized ? [:weight] : Symbol[]
    
    # Initialize minibatch buffer and sampler
    𝒟 = ExperienceBuffer(𝒮.S, 𝒮.A, 𝒮.batch_size, required_columns, device = 𝒮.device)
    γ = Float32(discount(mdp))
    s = Sampler(mdp, 𝒮.π, 𝒮.S, required_columns = required_columns, max_steps = 𝒮.max_steps, exploration_policy = 𝒮.exploration_policy, rng = 𝒮.rng)
    
    # Log the pre-train performance
    𝒮.i == 0 && log(𝒮.log, 𝒮.i, log_undiscounted_return(s, Neps = 𝒮.eval_eps))
    
    # Fill the buffer as needed
    𝒮.i += fillto!(𝒮.buffer, s, 𝒮.buffer_init, i = 𝒮.i, explore = true)
    
    for 𝒮.i = range(𝒮.i, stop = 𝒮.i + 𝒮.N - 𝒮.ΔN, step = 𝒮.ΔN)
        # Take ΔN steps in the environment
        push!(𝒮.buffer, steps!(s, explore = true, i = 𝒮.i, Nsteps = 𝒮.ΔN))
        
        infos = []
        for _ in 1:𝒮.epochs
            # Sample a minibatch
            rand!(𝒮.rng, 𝒟, 𝒮.buffer, extra_buffers..., i = 𝒮.i)

            # Compute target, td_error and td_loss for backprop
            y = DQN_target(𝒮.π⁻, 𝒟, γ)
            isprioritized && update_priorities!(𝒮.buffer, 𝒟.indices, cpu(td_error(𝒮.π, 𝒟, y)))
            info = train!(𝒮.π, (;kwargs...) -> td_loss(𝒮.π, 𝒟, y, 𝒮.loss, isprioritized; kwargs...), 𝒮.opt, regularizer = 𝒮.regularizer)
            push!(infos, info)
        end
        
        # Update target network
        elapsed(𝒮.i + 1:𝒮.i + 𝒮.ΔN, 𝒮.Δtarget_update) && copyto!(𝒮.π⁻, 𝒮.π)
        
        # Log results
        log(𝒮.log, 𝒮.i + 1:𝒮.i + 𝒮.ΔN, log_undiscounted_return(s, Neps = 𝒮.eval_eps), 
                                            aggregate_info(infos),
                                            log_exploration(𝒮.exploration_policy, 𝒮.i))
    end
    𝒮.i += 𝒮.ΔN
    𝒮.π
end

