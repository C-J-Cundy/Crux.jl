@with_kw mutable struct VPGSolver <: Solver 
    π::Policy
    baseline::Union{Baseline, Nothing}
    N::Int64
    buffer::BufferParams = BufferParams(size = 100)
    max_steps::Int64 = 100
    opt = ADAM(1e-3)
    device = cpu
    rng::AbstractRNG = Random.GLOBAL_RNG
    log = LoggerParams(dir = "log/vpg", period = 500)
end

vpg_loss(π, 𝒟) = -mean(logpdf(π, 𝒟[:s], 𝒟[:a]) .* 𝒟[:advantage])

function POMDPs.solve(𝒮::VPGSolver, mdp)
    𝒟 = ExperienceBuffer(mdp, 𝒮.buffer.size, device = 𝒮.device, gae = true, Nelements = 𝒮.buffer.size)
    println("device: ", device(𝒟))
    ΔN = length(𝒟)
    
    log(𝒮.log, 0, mdp, 𝒮.π, rng = 𝒮.rng)
    for i=ΔN+1:ΔN:𝒮.N
        fill!(𝒟, mdp, 𝒮.π, baseline = 𝒮.baseline, max_steps = 𝒮.max_steps, rng = 𝒮.rng) # Sample episodes
        !isnothing(𝒮.baseline) && train!(𝒮.baseline, 𝒟) # train baseline
        loss, grad = train!(𝒮.π, () -> vpg_loss(𝒮.π, 𝒟), 𝒮.opt, 𝒮.device) # train vpg
        log(𝒮.log, i, mdp, 𝒮.π, data = [logloss(loss, grad)], rng = 𝒮.rng, last_i = i-ΔN)
    end
end

