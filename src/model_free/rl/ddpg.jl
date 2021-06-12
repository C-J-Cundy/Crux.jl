# Set yᵢ = rᵢ + γQ′(sᵢ₊₁, μ′(sᵢ₊₁ | θᵘ′) | θᶜ′)
DDPG_target(π, 𝒟, γ::Float32; kwargs...) = 𝒟[:r] .+ γ .* (1.f0 .- 𝒟[:done]) .* value(π, 𝒟[:sp], action(π, 𝒟[:sp]))

function smoothed_DDPG_target(π_smooth=GaussianNoiseExplorationPolicy(0.1f0, ϵ_min=-0.5f0, ϵ_max=0.5f0))
    (π, 𝒟, γ::Float32; i) -> begin
        ap, _ = exploration(π_smooth, 𝒟[:sp], π_on=π, i=i)
        y = 𝒟[:r] .+ γ .* (1.f0 .- 𝒟[:done]) .* value(π, 𝒟[:sp], ap)
    end
end

# ∇_θᵘ 𝐽 ≈ 1/𝑁 Σᵢ ∇ₐQ(s, a | θᶜ)|ₛ₌ₛᵢ, ₐ₌ᵤ₍ₛᵢ₎ ∇_θᵘ μ(s | θᵘ)|ₛᵢ
DDPG_actor_loss(π, 𝒟; info=Dict()) = -mean(value(π, 𝒟[:s], action(π, 𝒟[:s])))

# T. P. Lillicrap, et al., "Continuous control with deep reinforcement learning", ICLR 2016.
DDPG(;π::ActorCritic, ΔN=50, π_explore=GaussianNoiseExplorationPolicy(0.1f0),  a_opt::NamedTuple=(;), c_opt::NamedTuple=(;), log::NamedTuple=(;), kwargs...) = 
    OffPolicySolver(;
        π=π, 
        ΔN=ΔN,
        log=LoggerParams(;dir = "log/ddpg", log...),
        a_opt=TrainingParams(;loss=DDPG_actor_loss, name="actor_", a_opt...),
        c_opt=TrainingParams(;loss=td_loss, name="critic_", epochs=ΔN, c_opt...),
        π_explore=π_explore,
        target_fn=DDPG_target,
        kwargs...)

