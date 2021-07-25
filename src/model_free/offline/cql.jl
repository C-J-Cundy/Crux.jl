function CQL_alpha_loss(π, 𝒫, 𝒟; info = Dict())
    ignore() do
        info["CQL alpha"] = exp(𝒫[:CQL_log_α][1])
    end
    -conservative_loss(π, 𝒫, 𝒟)
end

function importance_sampling(πsamp, π, obs, Nsamples)
    @assert ndims(obs) == 2 # does not support multidimensional observations yet
    @assert critic(π) isa DoubleNetwork # Assumes we have a double network
    
    rep_obs, flat_actions, logprobs = Zygote.ignore() do
        actions_and_logprobs = [exploration(πsamp, obs) for i=1:Nsamples]
        actions = cat([a for (a, _) in actions_and_logprobs]..., dims=3)
        logprobs = cat([lp for (_, lp) in actions_and_logprobs]..., dims=3)
        rep_obs = repeat(obs, 1, Nsamples)
        flat_actions = reshape(actions, size(actions)[1], :)
        rep_obs, flat_actions, logprobs
    end
    
    qvals = reshape(mean(value(π, rep_obs, flat_actions)), 1, :, Nsamples)
    
    return qvals .- logprobs
end

function conservative_loss(π, 𝒫, 𝒟; info=Dict())
    pol_values = importance_sampling(π, π, 𝒟[:s], 𝒫[:CQL_n_action_samples])
    unif_values = importance_sampling(𝒫[:CQL_is_distribution], π, 𝒟[:s], 𝒫[:CQL_n_action_samples])
    combined = cat(pol_values, unif_values, dims=3)
    lse = logsumexp(combined, dims=3)
    loss = mean(lse) - mean(mean(value(π, 𝒟[:s], 𝒟[:a])))
    
    β = clamp(exp(𝒫[:CQL_log_α][1]), 0f0, 1f6)
    β * (5f0*loss - 𝒫[:CQL_α_thresh])
end

function CQL_critic_loss(π, 𝒫, 𝒟, y; info=Dict(), weighted=false)
    loss = double_Q_loss(π, 𝒫, 𝒟, y, info=info)
    c_loss = conservative_loss(π, 𝒫, 𝒟, info=info)
    loss + c_loss
end

function CQL(;π::ActorCritic{T, DoubleNetwork{ContinuousNetwork, ContinuousNetwork}}, 
    SAC_α::Float32=1f0, 
    SAC_H_target::Float32=Float32(-prod(Crux.dim(action_space(π)))),
    CQL_α::Float32=1f0,
    CQL_is_distribution = DistributionPolicy(product_distribution([Uniform(-1,1) for i=1:dim(action_space(π))[1]])),
    CQL_α_thresh::Float32 = 10f0,
    CQL_n_action_samples::Int = 10,
    SAC_α_opt::NamedTuple=(;), 
    CQL_α_opt::NamedTuple=(;),
    a_opt::NamedTuple=(;), 
    c_opt::NamedTuple=(;), 
    log::NamedTuple=(;), 
    kwargs...) where T
    # Fill the parameters
    𝒫 = (SAC_log_α=[Base.log(SAC_α)], 
          SAC_H_target=SAC_H_target,
          CQL_log_α=[Base.log(CQL_α)],
          CQL_is_distribution=CQL_is_distribution,
          CQL_n_action_samples=CQL_n_action_samples,
          CQL_α_thresh=CQL_α_thresh)
    BatchSolver(;
        π = π,
        𝒫 = 𝒫,
        log = LoggerParams(;dir = "log/cql", log...),
        param_optimizers = Dict(Flux.params(𝒫[:SAC_log_α]) => TrainingParams(;loss=SAC_temp_loss, name="SAC_alpha_", SAC_α_opt...),
                                Flux.params(𝒫[:CQL_log_α]) => TrainingParams(;loss=CQL_alpha_loss, name="CQL_alpha_", CQL_α_opt...)),
        a_opt = TrainingParams(;loss=SAC_actor_loss, name="actor_", a_opt...),
        c_opt = TrainingParams(;loss=CQL_critic_loss, name="critic_", c_opt...),
        target_fn = SAC_deterministic_target(π),
        kwargs...)
end
